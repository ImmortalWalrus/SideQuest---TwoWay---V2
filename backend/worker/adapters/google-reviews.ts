import type { WorkerConfig } from "../lib/config";
import {
  sanitizeReviewRating,
  sanitizeReviewCount,
  venueReviewKey,
} from "../lib/normalize";
import {
  upsertVenueReview,
  getCachedVenueReviews,
  type SupabaseClient,
} from "../lib/supabase";
import type { EventResult } from "./ticketmaster";

interface ReviewSignal {
  rating: number;
  reviewCount: number;
  url?: string;
  placeId?: string;
}

export async function enrichEventsWithReviews(
  events: EventResult[],
  config: WorkerConfig,
  supabase: SupabaseClient
): Promise<{
  events: EventResult[];
  hitCount: number;
  missCount: number;
  errorCount: number;
}> {
  let hitCount = 0;
  let missCount = 0;
  let errorCount = 0;

  const venueKeyMap = new Map<string, EventResult[]>();
  for (const event of events) {
    const key = venueReviewKey(
      event.venueName || event.title,
      event.city,
      event.state,
      event.postalCode
    );
    if (!key || key === "venue:") continue;
    const existing = venueKeyMap.get(key) || [];
    existing.push(event);
    venueKeyMap.set(key, existing);
  }

  const allKeys = Array.from(venueKeyMap.keys());
  const cached = await getCachedVenueReviews(supabase, allKeys);

  const uncachedKeys: string[] = [];
  for (const key of allKeys) {
    if (!cached.has(key)) uncachedKeys.push(key);
  }

  const freshSignals = new Map<string, ReviewSignal>();

  if (uncachedKeys.length > 0 && config.googlePlacesApiKey) {
    const batchSize = 5;
    for (let i = 0; i < uncachedKeys.length; i += batchSize) {
      const batch = uncachedKeys.slice(i, i + batchSize);
      const results = await Promise.allSettled(
        batch.map(async (key) => {
          const representativeEvents = venueKeyMap.get(key);
          if (!representativeEvents || representativeEvents.length === 0) return null;
          const rep = representativeEvents[0];
          return fetchGooglePlacesReview(
            rep.venueName || rep.title,
            rep.city,
            rep.state,
            rep.latitude,
            rep.longitude,
            config.googlePlacesApiKey!
          );
        })
      );

      for (let j = 0; j < batch.length; j++) {
        const key = batch[j];
        const settled = results[j];
        const representativeEvents = venueKeyMap.get(key);
        const rep = representativeEvents?.[0];

        if (settled.status === "fulfilled" && settled.value) {
          const signal = settled.value;
          freshSignals.set(key, signal);
          hitCount++;

          await upsertVenueReview(supabase, {
            venue_key: key,
            venue_name: rep?.venueName || rep?.title || "",
            city: rep?.city ?? undefined,
            state: rep?.state ?? undefined,
            postal_code: rep?.postalCode ?? undefined,
            latitude: rep?.latitude ?? undefined,
            longitude: rep?.longitude ?? undefined,
            google_rating: signal.rating,
            google_review_count: signal.reviewCount,
            google_maps_url: signal.url,
            google_place_id: signal.placeId,
            review_source: "google_places_api",
            is_poisoned: false,
          });
        } else if (settled.status === "rejected") {
          errorCount++;
        } else {
          missCount++;
        }
      }

      if (i + batchSize < uncachedKeys.length) {
        await new Promise((r) => setTimeout(r, 200));
      }
    }
  }

  const enrichedEvents = events.map((event) => {
    const key = venueReviewKey(
      event.venueName || event.title,
      event.city,
      event.state,
      event.postalCode
    );

    const cachedReview = cached.get(key);
    const freshReview = freshSignals.get(key);
    const review = freshReview || cachedReview;

    if (!review) return event;

    const sanitizedRating = sanitizeReviewRating(review.rating);
    const sanitizedCount = sanitizeReviewCount(review.reviewCount);

    if (!sanitizedRating) return event;

    return {
      ...event,
      rawSourcePayload: {
        ...event.rawSourcePayload,
        google_places_rating: sanitizedRating,
        google_places_user_rating_count: sanitizedCount,
        google_places_url: review.url,
        google_review_signal_source: "server_google_places_api",
      },
    };
  });

  return { events: enrichedEvents, hitCount, missCount, errorCount };
}

async function fetchGooglePlacesReview(
  venueName: string,
  city: string | undefined,
  state: string | undefined,
  latitude: number | undefined,
  longitude: number | undefined,
  apiKey: string
): Promise<ReviewSignal | null> {
  const query = [venueName, city, state].filter(Boolean).join(", ");

  const searchUrl = new URL(
    "https://places.googleapis.com/v1/places:searchText"
  );

  const body: Record<string, unknown> = {
    textQuery: query,
    maxResultCount: 1,
  };

  if (latitude && longitude) {
    body.locationBias = {
      circle: {
        center: { latitude, longitude },
        radius: 5000,
      },
    };
  }

  try {
    const response = await fetch(searchUrl.toString(), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask":
          "places.id,places.rating,places.userRatingCount,places.googleMapsUri",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) return null;

    const data = await response.json();
    const place = data?.places?.[0];
    if (!place) return null;

    const rating = sanitizeReviewRating(place.rating);
    if (!rating) return null;

    return {
      rating,
      reviewCount: sanitizeReviewCount(place.userRatingCount) ?? 0,
      url: place.googleMapsUri,
      placeId: place.id,
    };
  } catch {
    return null;
  }
}
