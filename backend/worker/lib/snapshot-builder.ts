import type { EventResult } from "../adapters/ticketmaster";
import type { Metro } from "./supabase";
import {
  dedupeBucketKey,
  isLikelyDuplicate,
  normalizeToken,
  sanitizeReviewRating,
  sanitizeReviewCount,
} from "./normalize";

export interface BuiltSnapshot {
  fetchedAt: string;
  searchLocation: {
    city: string;
    state: string;
    postalCode: string | null;
    countryCode: string;
    latitude: number;
    longitude: number;
    displayName: string;
  };
  appliedProfiles: Array<{
    step: number;
    hyperlocalRadiusMiles: number;
    nightlifeRadiusMiles: number;
    headlineRadiusMiles: number;
  }>;
  venueSnapshot: null;
  eventSnapshot: {
    fetchedAt: string;
    query: {
      countryCode: string;
      city: string;
      state: string;
      postalCode: string | null;
      latitude: number;
      longitude: number;
      radiusMiles: number;
      pageSize: number;
      page: number;
      sourcePageDepth: number;
      includePast: boolean;
      hyperlocalRadiusMiles: number;
      nightlifeRadiusMiles: number;
      headlineRadiusMiles: number;
      adaptiveRadiusExpansion: boolean;
      discoveryIntent: string;
    };
    sourceResults: Array<{
      source: string;
      usedCache: boolean;
      fetchedAt: string;
      endpoints: Array<{
        label: string;
        requestURL: string;
        responseStatusCode: number | null;
        worked: boolean;
        note: string | null;
      }>;
      note: string | null;
      nextCursor: null;
      events: SnapshotEvent[];
    }>;
    mergedEvents: SnapshotEvent[];
    dedupeGroups: Array<{
      dedupeKey: string;
      canonicalEventID: string;
      mergedEventIDs: string[];
      mergedSources: string[];
      reason: string;
    }>;
  };
  mergedEvents: SnapshotEvent[];
  notes: string[];
}

export interface SnapshotEvent {
  id: string;
  source: string;
  sourceEventID: string;
  sourceParentID?: string;
  sourceURL?: string;
  mergedSources: string[];
  title: string;
  shortDescription?: string;
  fullDescription?: string;
  category?: string;
  subcategory?: string;
  eventType: string;
  startAtUTC?: string;
  endAtUTC?: string;
  startLocal?: string;
  endLocal?: string;
  timezone?: string;
  salesStartAtUTC?: string;
  salesEndAtUTC?: string;
  venueName?: string;
  venueID?: string;
  addressLine1?: string;
  addressLine2?: string;
  city?: string;
  state?: string;
  postalCode?: string;
  country?: string;
  latitude?: number;
  longitude?: number;
  imageURL?: string;
  fallbackThumbnailAsset?: string;
  status: string;
  availabilityStatus: string;
  urgencyBadge?: string;
  socialProofCount?: number;
  socialProofLabel?: string;
  venuePopularityCount?: number;
  venueRating?: number;
  ticketProviderCount?: number;
  priceMin?: number;
  priceMax?: number;
  currency?: string;
  organizerName?: string;
  organizerEventCount?: number;
  organizerVerified?: boolean;
  tags: string[];
  distanceValue?: number;
  distanceUnit?: string;
  raceType?: string;
  registrationURL?: string;
  ticketURL?: string;
  rawSourcePayload: string;
  sourceType: string;
  recordKind: string;
  neighborhood?: string;
  reservationURL?: string;
  artistsOrTeams: string[];
  ageMinimum?: number;
  doorPolicyText?: string;
  dressCodeText?: string;
  guestListAvailable?: boolean;
  bottleServiceAvailable?: boolean;
  tableMinPrice?: number;
  coverPrice?: number;
  openingHoursText?: string;
  sourceConfidence?: number;
  popularityScoreRaw?: number;
  venueSignalScore?: number;
  exclusivityScore?: number;
  trendingScore?: number;
  crossSourceConfirmationScore?: number;
  distanceFromUser?: number;
  entryPolicySummary?: string;
  womenEntryPolicyText?: string;
  menEntryPolicyText?: string;
  exclusivityTierLabel?: string;
}

export function buildSnapshot(
  metro: Metro,
  intent: string,
  eventsBySource: Map<string, EventResult[]>,
  notes: string[]
): BuiltSnapshot {
  const now = new Date().toISOString();

  const allEvents: EventResult[] = [];
  for (const events of eventsBySource.values()) {
    allEvents.push(...events);
  }

  const deduped = deduplicateEvents(allEvents);
  const snapshotEvents = deduped.events.map((e) => toSnapshotEvent(e));

  snapshotEvents.sort((a, b) => {
    const aDate = a.startAtUTC || "9999";
    const bDate = b.startAtUTC || "9999";
    return aDate.localeCompare(bDate);
  });

  const sourceResults = Array.from(eventsBySource.entries()).map(
    ([source, events]) => ({
      source,
      usedCache: false,
      fetchedAt: now,
      endpoints: [
        {
          label: `${source} server fetch`,
          requestURL: `server://${source}`,
          responseStatusCode: 200,
          worked: events.length > 0,
          note: null,
        },
      ],
      note: events.length === 0 ? `${source}: no events returned` : null,
      nextCursor: null,
      events: events.map((e) => toSnapshotEvent(e)),
    })
  );

  return {
    fetchedAt: now,
    searchLocation: {
      city: metro.city,
      state: metro.state,
      postalCode: metro.postal_code,
      countryCode: metro.country_code,
      latitude: metro.latitude,
      longitude: metro.longitude,
      displayName: metro.display_name,
    },
    appliedProfiles: [
      {
        step: 0,
        hyperlocalRadiusMiles: 2,
        nightlifeRadiusMiles: 6,
        headlineRadiusMiles: 15,
      },
    ],
    venueSnapshot: null,
    eventSnapshot: {
      fetchedAt: now,
      query: {
        countryCode: metro.country_code,
        city: metro.city,
        state: metro.state,
        postalCode: metro.postal_code,
        latitude: metro.latitude,
        longitude: metro.longitude,
        radiusMiles: 15,
        pageSize: 50,
        page: 0,
        sourcePageDepth: 2,
        includePast: false,
        hyperlocalRadiusMiles: 2,
        nightlifeRadiusMiles: 6,
        headlineRadiusMiles: 15,
        adaptiveRadiusExpansion: true,
        discoveryIntent: intent,
      },
      sourceResults,
      mergedEvents: snapshotEvents,
      dedupeGroups: deduped.groups,
    },
    mergedEvents: snapshotEvents,
    notes,
  };
}

function deduplicateEvents(events: EventResult[]): {
  events: EventResult[];
  groups: Array<{
    dedupeKey: string;
    canonicalEventID: string;
    mergedEventIDs: string[];
    mergedSources: string[];
    reason: string;
  }>;
} {
  const buckets = new Map<string, EventResult[]>();

  for (const event of events) {
    const key = dedupeBucketKey(event);
    const bucket = buckets.get(key) || [];
    bucket.push(event);
    buckets.set(key, bucket);
  }

  const deduped: EventResult[] = [];
  const groups: Array<{
    dedupeKey: string;
    canonicalEventID: string;
    mergedEventIDs: string[];
    mergedSources: string[];
    reason: string;
  }> = [];

  for (const [bucketKey, bucketEvents] of buckets) {
    const clusters: EventResult[][] = [];

    for (const event of bucketEvents) {
      let placed = false;
      for (const cluster of clusters) {
        if (cluster.some((e) => isLikelyDuplicate(e, event))) {
          cluster.push(event);
          placed = true;
          break;
        }
      }
      if (!placed) clusters.push([event]);
    }

    for (const cluster of clusters) {
      cluster.sort((a, b) => completenessScore(b) - completenessScore(a));
      const canonical = cluster[0];
      deduped.push(canonical);

      if (cluster.length > 1) {
        groups.push({
          dedupeKey: bucketKey,
          canonicalEventID: canonical.id,
          mergedEventIDs: cluster.map((e) => e.id),
          mergedSources: [...new Set(cluster.map((e) => e.source))],
          reason: "Server-side dedup: shared day, fuzzy title, venue overlap",
        });
      }
    }
  }

  return { events: deduped, groups };
}

function completenessScore(event: EventResult): number {
  let score = 0;
  if (event.latitude && event.longitude) score += 6;
  if (event.startAtUTC) score += 5;
  if (event.timezone) score += 3;
  if (event.venueName) score += 3;
  if (event.addressLine1) score += 4;
  if (event.city) score += 2;
  if (event.imageUrl) score += 4;
  if (event.shortDescription) score += 2;
  if (event.ticketUrl) score += 2;
  const rating = sanitizeReviewRating(event.rawSourcePayload?.google_places_rating);
  if (rating) score += 3;
  const count = sanitizeReviewCount(event.rawSourcePayload?.google_places_user_rating_count);
  if (count) score += 2;
  return score;
}

function toSnapshotEvent(event: EventResult): SnapshotEvent {
  const rating = sanitizeReviewRating(
    event.rawSourcePayload?.google_places_rating
  );
  const reviewCount = sanitizeReviewCount(
    event.rawSourcePayload?.google_places_user_rating_count
  );

  return {
    id: event.id,
    source: event.source,
    sourceEventID: event.sourceEventId,
    sourceParentID: event.sourceParentId,
    sourceURL: event.sourceUrl,
    mergedSources: [event.source],
    title: event.title,
    shortDescription: event.shortDescription,
    fullDescription: event.fullDescription,
    category: event.category,
    subcategory: event.subcategory,
    eventType: event.eventType,
    startAtUTC: event.startAtUTC,
    endAtUTC: event.endAtUTC,
    startLocal: event.startLocal,
    endLocal: event.endLocal,
    timezone: event.timezone,
    venueName: event.venueName,
    venueID: event.venueId,
    addressLine1: event.addressLine1,
    city: event.city,
    state: event.state,
    postalCode: event.postalCode,
    country: event.country,
    latitude: event.latitude,
    longitude: event.longitude,
    imageURL: event.imageUrl,
    status: event.status || "scheduled",
    availabilityStatus: event.status === "onsale" ? "onsale" : "unknown",
    tags: event.tags || [],
    priceMin: event.priceMin,
    priceMax: event.priceMax,
    currency: event.currency,
    ticketURL: event.ticketUrl,
    rawSourcePayload: JSON.stringify(event.rawSourcePayload || {}),
    sourceType: sourceTypeFor(event.source),
    recordKind: "event",
    artistsOrTeams: [],
    venueRating: rating ?? undefined,
    venuePopularityCount: reviewCount ?? undefined,
  };
}

function sourceTypeFor(source: string): string {
  switch (source) {
    case "ticketmaster":
    case "seatGeek":
    case "stubHub":
      return "ticketing_api";
    case "eventbrite":
      return "ticketing_api";
    case "googleEvents":
      return "scraped";
    case "appleMaps":
    case "googlePlaces":
    case "yelpFusion":
      return "venue_discovery_api";
    default:
      return "scraped";
  }
}
