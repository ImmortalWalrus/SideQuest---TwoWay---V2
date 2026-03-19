import type { WorkerConfig } from "../lib/config";
import {
  sanitizeReviewRating,
  sanitizeReviewCount,
  venueReviewKey,
  normalizeToken,
  normalizeStateToken,
} from "../lib/normalize";
import {
  upsertVenueReview,
  getCachedVenueReviews,
  type SupabaseClient,
} from "../lib/supabase";
import type { EventResult } from "./ticketmaster";

interface ReviewSignal {
  rating: number;
  reviewCount: number | null;
  url: string;
  source: "scraped_google_maps" | "google_places_api";
}

interface ReviewLookup {
  cacheKey: string;
  venueName: string;
  addressLine1?: string;
  city?: string;
  state?: string;
  postalCode?: string;
  query: string;
  reviewURLs: string[];
}

const DESKTOP_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

const NIGHTLIFE_BLOCK_SIGNALS = [
  "nightclub",
  "night club",
  "strip club",
  "gentlemen's club",
  "gentlemens club",
];

export async function enrichEventsWithReviews(
  events: EventResult[],
  config: WorkerConfig,
  supabase: SupabaseClient
): Promise<{
  events: EventResult[];
  hitCount: number;
  missCount: number;
  errorCount: number;
  poisonedCount: number;
}> {
  let hitCount = 0;
  let missCount = 0;
  let errorCount = 0;
  let poisonedCount = 0;

  const venueKeyMap = new Map<string, EventResult[]>();
  for (const event of events) {
    if (!shouldScrapeGoogleReviews(event)) continue;
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

  if (uncachedKeys.length > 0) {
    const batchSize = 3;
    for (let i = 0; i < uncachedKeys.length; i += batchSize) {
      const batch = uncachedKeys.slice(i, i + batchSize);
      const results = await Promise.allSettled(
        batch.map(async (key) => {
          const representativeEvents = venueKeyMap.get(key);
          if (!representativeEvents || representativeEvents.length === 0)
            return null;
          const rep = representativeEvents[0];
          const lookup = buildReviewLookup(rep);
          if (!lookup) return null;
          return fetchReviewSignal(lookup, config);
        })
      );

      for (let j = 0; j < batch.length; j++) {
        const key = batch[j];
        const settled = results[j];
        const representativeEvents = venueKeyMap.get(key);
        const rep = representativeEvents?.[0];

        if (settled.status === "fulfilled" && settled.value) {
          const signal = settled.value;

          const sanitizedRating = sanitizeReviewRating(signal.rating);
          const sanitizedCount = sanitizeReviewCount(signal.reviewCount);

          if (!sanitizedRating) {
            poisonedCount++;
            await upsertVenueReview(supabase, {
              venue_key: key,
              venue_name: rep?.venueName || rep?.title || "",
              city: rep?.city ?? undefined,
              state: rep?.state ?? undefined,
              postal_code: rep?.postalCode ?? undefined,
              latitude: rep?.latitude ?? undefined,
              longitude: rep?.longitude ?? undefined,
              google_rating: signal.rating,
              google_review_count: signal.reviewCount ?? undefined,
              google_maps_url: signal.url,
              review_source: signal.source,
              is_poisoned: true,
              poison_reason: `Rating ${signal.rating} failed sanitization`,
            });
            continue;
          }

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
            google_rating: sanitizedRating,
            google_review_count: sanitizedCount ?? undefined,
            google_maps_url: signal.url,
            review_source: signal.source,
            is_poisoned: false,
          });
        } else if (settled.status === "rejected") {
          errorCount++;
        } else {
          missCount++;
        }
      }

      if (i + batchSize < uncachedKeys.length) {
        await new Promise((r) => setTimeout(r, 400 + Math.random() * 300));
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
        google_review_signal_source:
          "source" in review ? review.source : "scraped_google_maps",
      },
    };
  });

  return { events: enrichedEvents, hitCount, missCount, errorCount, poisonedCount };
}

function shouldScrapeGoogleReviews(event: EventResult): boolean {
  if (event.status === "cancelled" || event.status === "ended") return false;

  const eventType = (event.eventType || "").toLowerCase();
  if (eventType === "party / nightlife" || eventType === "party_nightlife") {
    const haystack = normalizeToken(
      [
        event.venueName,
        event.title,
        JSON.stringify(event.rawSourcePayload || {}),
      ].join(" ")
    );
    if (isLikelyClubLikeNightlifeVenue(haystack)) return false;
  }

  return true;
}

function isLikelyClubLikeNightlifeVenue(haystack: string): boolean {
  return NIGHTLIFE_BLOCK_SIGNALS.some((s) => haystack.includes(s));
}

function buildReviewLookup(event: EventResult): ReviewLookup | null {
  const venueName = event.venueName || event.title;
  if (!venueName) return null;

  const existingRating = sanitizeReviewRating(
    event.rawSourcePayload?.google_places_rating
  );
  if (existingRating) return null;

  const queryParts = [
    venueName,
    event.addressLine1,
    event.city,
    event.state,
    event.postalCode,
  ].filter(Boolean) as string[];

  if (queryParts.length === 0) return null;
  const query = queryParts.join(" ");

  const cacheKey = venueReviewKey(
    venueName,
    event.city,
    event.state,
    event.postalCode
  );

  const reviewURLs = buildGoogleReviewURLs(query);

  return {
    cacheKey,
    venueName,
    addressLine1: event.addressLine1,
    city: event.city,
    state: event.state,
    postalCode: event.postalCode,
    query,
    reviewURLs,
  };
}

function buildGoogleReviewURLs(query: string): string[] {
  const urls: string[] = [];

  const mapSearchParams = new URLSearchParams({
    tbm: "map",
    authuser: "0",
    hl: "en",
    gl: "us",
    q: query,
  });
  urls.push(`https://www.google.com/search?${mapSearchParams.toString()}`);

  const encodedQuery = encodeURIComponent(query).replace(/%20/g, "+");
  urls.push(
    `https://www.google.com/maps/search/${encodedQuery}?hl=en&gl=us`
  );

  const placeSearchParams = new URLSearchParams({
    hl: "en",
    gl: "us",
    q: query + " reviews",
  });
  urls.push(
    `https://www.google.com/search?${placeSearchParams.toString()}`
  );

  return urls;
}

async function fetchReviewSignal(
  lookup: ReviewLookup,
  config: WorkerConfig
): Promise<ReviewSignal | null> {
  const scrapedSignal = await scrapeGoogleReviewSignal(lookup);
  if (scrapedSignal) return scrapedSignal;

  if (config.googlePlacesApiKey) {
    const apiSignal = await fetchGooglePlacesReviewFallback(
      lookup,
      config.googlePlacesApiKey
    );
    if (apiSignal) return apiSignal;
  }

  return null;
}

async function scrapeGoogleReviewSignal(
  lookup: ReviewLookup
): Promise<ReviewSignal | null> {
  for (const reviewURL of lookup.reviewURLs) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          await new Promise((r) => setTimeout(r, 300 * attempt));
        }

        const response = await fetch(reviewURL, {
          method: "GET",
          headers: {
            "User-Agent": DESKTOP_USER_AGENT,
            "Accept-Language": "en-US,en;q=0.9",
            Accept:
              "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            Referer: "https://www.google.com/",
            DNT: "1",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-User": "?1",
          },
          signal: AbortSignal.timeout(18000),
        });

        if (!response.ok) continue;

        const html = await response.text();

        if (html.includes("unusual traffic") || html.includes("captcha")) {
          continue;
        }

        if (reviewURL.includes("tbm=map")) {
          const mapSignal = parseGoogleMapSearchSignal(
            html,
            lookup,
            reviewURL
          );
          if (mapSignal) return mapSignal;
        }

        const htmlSignal = parseGoogleHTMLReviewSignal(
          html,
          lookup,
          reviewURL
        );
        if (htmlSignal) return htmlSignal;
      } catch {
        continue;
      }
    }
  }

  return null;
}

function parseGoogleMapSearchSignal(
  response: string,
  lookup: ReviewLookup,
  fallbackURL: string
): ReviewSignal | null {
  const trimmed = response.trimStart();
  const sanitized = trimmed.substring(
    trimmed.search(/[\[{]/) >= 0 ? trimmed.search(/[\[{]/) : 0
  );
  if (!sanitized) return null;

  let jsonObject: unknown;
  try {
    jsonObject = JSON.parse(sanitized);
  } catch {
    return null;
  }

  let bestMatch: {
    rating: number;
    reviewCount: number | null;
    reviewURL: string;
    score: number;
  } | null = null;

  collectGoogleMapSearchCandidate(
    jsonObject,
    lookup,
    fallbackURL,
    (candidate) => {
      if (
        !bestMatch ||
        candidate.score > bestMatch.score ||
        (candidate.score === bestMatch.score &&
          (candidate.reviewCount ?? 0) > (bestMatch.reviewCount ?? 0))
      ) {
        bestMatch = candidate;
      }
    }
  );

  if (!bestMatch) return null;

  return {
    rating: bestMatch.rating,
    reviewCount: bestMatch.reviewCount,
    url: sanitizedUserFacingReviewURL(bestMatch.reviewURL),
    source: "scraped_google_maps",
  };
}

function collectGoogleMapSearchCandidate(
  node: unknown,
  lookup: ReviewLookup,
  fallbackURL: string,
  onCandidate: (candidate: {
    rating: number;
    reviewCount: number | null;
    reviewURL: string;
    score: number;
  }) => void
): void {
  if (Array.isArray(node)) {
    const rating = extractMapSearchRating(node);
    if (rating !== null) {
      const reviewCount = extractMapSearchReviewCount(node);
      const reviewURL = extractMapSearchReviewURL(node, fallbackURL);
      const candidateStrings = extractMapSearchStrings(node, 2);

      const normalizedVenueName = normalizeToken(lookup.venueName);
      let bestScore = 0;

      for (const candidateTitle of candidateStrings) {
        if (candidateTitle.length > 180) continue;
        const score = googleReviewIdentityScore(
          lookup,
          candidateTitle,
          reviewURL
        );
        if (score === 0) continue;

        const normalizedCandidate = normalizeToken(candidateTitle);
        const exactBonus =
          normalizedCandidate === normalizedVenueName ? 4 : 0;
        const partialBonus =
          exactBonus === 0 &&
          normalizedVenueName &&
          (normalizedCandidate.includes(normalizedVenueName) ||
            normalizedVenueName.includes(normalizedCandidate))
            ? 1
            : 0;
        bestScore = Math.max(bestScore, score + exactBonus + partialBonus);
      }

      if (bestScore > 0) {
        onCandidate({ rating, reviewCount, reviewURL, score: bestScore });
      }
    }

    for (const child of node) {
      collectGoogleMapSearchCandidate(child, lookup, fallbackURL, onCandidate);
    }
  } else if (node && typeof node === "object" && !Array.isArray(node)) {
    for (const value of Object.values(node as Record<string, unknown>)) {
      collectGoogleMapSearchCandidate(value, lookup, fallbackURL, onCandidate);
    }
  }
}

function extractMapSearchRating(array: unknown[]): number | null {
  if (
    array.length >= 8 &&
    array.slice(0, 7).every((v) => v === null) &&
    typeof array[7] === "number" &&
    array[7] >= 1.0 &&
    array[7] <= 5.0
  ) {
    return array[7];
  }

  if (
    array.length >= 2 &&
    typeof array[0] === "number" &&
    array[0] >= 1.0 &&
    array[0] <= 5.0 &&
    (Array.isArray(array[1]) ||
      (array.length >= 3 && typeof array[2] === "number"))
  ) {
    return array[0];
  }

  for (const nullPrefixLen of [3, 4, 5, 6]) {
    if (array.length <= nullPrefixLen) continue;
    if (!array.slice(0, nullPrefixLen).every((v) => v === null)) continue;
    const val = array[nullPrefixLen];
    if (typeof val === "number" && val >= 1.0 && val <= 5.0) {
      return val;
    }
  }

  if (
    array.length >= 4 &&
    typeof array[0] === "string" &&
    typeof array[1] === "number" &&
    array[1] >= 1.0 &&
    array[1] <= 5.0
  ) {
    return array[1];
  }

  if (
    array.length >= 3 &&
    array[0] === null &&
    typeof array[1] === "number" &&
    array[1] >= 1.0 &&
    array[1] <= 5.0 &&
    typeof array[2] === "number"
  ) {
    return array[1];
  }

  return null;
}

function extractMapSearchReviewCount(array: unknown[]): number | null {
  if (
    array.length >= 3 &&
    typeof array[0] === "number" &&
    array[0] >= 1.0 &&
    array[0] <= 5.0 &&
    typeof array[2] === "number" &&
    array[2] > 0
  ) {
    return array[2] as number;
  }

  if (
    array.length >= 4 &&
    typeof array[0] === "string" &&
    typeof array[1] === "number" &&
    array[1] >= 1.0 &&
    array[1] <= 5.0 &&
    typeof array[3] === "number" &&
    (array[3] as number) > 0
  ) {
    return array[3] as number;
  }

  if (
    array.length >= 3 &&
    array[0] === null &&
    typeof array[1] === "number" &&
    array[1] >= 1.0 &&
    array[1] <= 5.0 &&
    typeof array[2] === "number" &&
    (array[2] as number) > 0
  ) {
    return array[2] as number;
  }

  for (let i = 0; i < Math.min(array.length, 10); i++) {
    if (
      typeof array[i] === "string" &&
      (array[i] as string).toLowerCase().includes("review") &&
      i > 0 &&
      typeof array[i - 1] === "number" &&
      (array[i - 1] as number) > 0
    ) {
      return array[i - 1] as number;
    }
  }

  return null;
}

function extractMapSearchReviewURL(
  array: unknown[],
  fallbackURL: string
): string {
  const candidates = extractMapSearchStrings(array, 3);
  for (const candidate of candidates) {
    if (
      candidate.includes("/maps/place/") &&
      !candidate.includes("/maps/preview/")
    ) {
      const abs = absoluteGoogleURL(candidate);
      if (abs) return abs;
    }
  }
  for (const candidate of candidates) {
    if (
      candidate.startsWith("https://maps.google.com") ||
      candidate.startsWith("https://www.google.com/maps")
    ) {
      const lower = candidate.toLowerCase();
      if (!lower.includes("tbm=map") && !lower.includes("/preview/")) {
        const abs = absoluteGoogleURL(candidate);
        if (abs) return abs;
      }
    }
  }
  return sanitizedUserFacingReviewURL(fallbackURL);
}

function extractMapSearchStrings(
  node: unknown,
  maxDepth: number,
  depth = 0
): string[] {
  if (depth > maxDepth) return [];
  if (typeof node === "string") return [node];
  if (Array.isArray(node)) {
    return node.flatMap((child) =>
      extractMapSearchStrings(child, maxDepth, depth + 1)
    );
  }
  if (node && typeof node === "object") {
    return Object.values(node as Record<string, unknown>).flatMap((child) =>
      extractMapSearchStrings(child, maxDepth, depth + 1)
    );
  }
  return [];
}

function absoluteGoogleURL(raw: string): string | null {
  try {
    if (raw.startsWith("http")) return raw;
    if (raw.startsWith("/")) return `https://www.google.com${raw}`;
  } catch {}
  return null;
}

function sanitizedUserFacingReviewURL(urlString: string): string {
  const lower = urlString.toLowerCase();
  if (
    lower.includes("tbm=map") ||
    lower.includes("/maps/preview/") ||
    (lower.includes("google.com/search?") && !lower.includes("reviews"))
  ) {
    try {
      const url = new URL(urlString);
      const query = url.searchParams.get("q");
      if (query) {
        const mapURL = new URL("https://www.google.com/maps/search/");
        mapURL.searchParams.set("api", "1");
        mapURL.searchParams.set("query", query);
        return mapURL.toString();
      }
    } catch {}
  }
  return urlString;
}

const RATING_REGEX = new RegExp(
  [
    `aria-label="Rated ([0-9.]+) out of 5[,"]`,
    `<span class="(?:UIHjI|MW4etd|Aq14fc|jANrlb|yi40Hd|e4rVHe|Fam1ne|fzTgPe|Y0A0hc|oqSTJd|KsR1A)[^"]*"[^>]*>([0-9.]+)</span>`,
    `aria-label="([0-9.]+) stars? ?"`,
    `<span aria-hidden="true">([0-9.]+)</span>\\s*<span class="(?:ceNzKf|UY7F9|EBe2gf|F9iS2e|LJEGhe)[^"]*"[^>]*`,
    `class="[^"]*(?:rating|stars|review-score)[^"]*"[^>]*>\\s*([0-9.]+)`,
    `data-rating="([0-9.]+)"`,
    `itemprop="ratingValue"[^>]*content="([0-9.]+)"`,
  ].join("|")
);

const REVIEW_COUNT_PATTERNS = [
  />([0-9][0-9,\.KkMm]*) reviews</,
  /([0-9][0-9,\.KkMm]*) Google reviews/,
  /aria-label="([0-9][0-9,\.KkMm]*) reviews"/,
  /\(([0-9][0-9,\.KkMm]*)\)/,
  /class="(?:EBe2gf|UY7F9|RDApEe|jANrlb|F9iS2e|LJEGhe)[^"]*"[^>]*>([0-9][0-9,\.KkMm]*)</,
  />([0-9][0-9,\.KkMm]*) review/,
  /itemprop="reviewCount"[^>]*content="([0-9][0-9,\.KkMm]*)"/,
  /data-review-count="([0-9][0-9,\.KkMm]*)"/,
];

const TITLE_PATTERNS = [
  /<h1[^>]+class="[^"]*(?:DUwDvf|lfPIob|fontHeadlineLarge|LZF9ie)[^"]*"[^>]*>(.*?)<\/h1>/,
  /<title>(.*?) - Google (?:Maps|Search)<\/title>/,
  /<span class="(?:OSrXXb|SPZz6b|rHQ3hc|yoA8e)">(.*?)<\/span>/,
  /<div class="(?:dbg0pd|rgnuSb|lMbq3e)">(.*?)<\/div>/,
  /<div class="(?:qBF1Pd|NhRr3b)[^"]*"[^>]*>(.*?)<\/div>/,
  /<h2[^>]+class="[^"]*(?:qrShPb|kno-ecr-pt)[^"]*"[^>]*>(.*?)<\/h2>/,
  /data-attrid="title"[^>]*>(.*?)</,
  /<span data-attrid="title"[^>]*>(.*?)<\/span>/,
  /aria-label="[^"]*" data-pid="[^"]*"[^>]*>\s*<span[^>]*>(.*?)<\/span>/,
];

function parseGoogleHTMLReviewSignal(
  html: string,
  lookup: ReviewLookup,
  reviewURL: string
): ReviewSignal | null {
  let bestSignal: {
    signal: ReviewSignal;
    score: number;
    reviewCount: number;
  } | null = null;

  const matches = html.matchAll(new RegExp(RATING_REGEX, "g"));
  for (const match of matches) {
    const ratingText = [1, 2, 3, 4, 5, 6, 7]
      .map((i) => match[i])
      .find((v) => v !== undefined);
    if (!ratingText) continue;

    const rating = parseFloat(ratingText);
    if (isNaN(rating) || rating < 1.0 || rating > 5.0) continue;

    const matchIndex = match.index ?? 0;
    const windowStart = Math.max(0, matchIndex - 900);
    const windowEnd = Math.min(html.length, matchIndex + (match[0]?.length ?? 0) + 900);
    const window = html.substring(windowStart, windowEnd);

    let reviewCount: number | null = null;
    for (const pattern of REVIEW_COUNT_PATTERNS) {
      const countMatch = window.match(pattern);
      if (countMatch?.[1]) {
        reviewCount = parseGoogleReviewCount(countMatch[1]);
        if (reviewCount !== null) break;
      }
    }

    let title: string | null = null;
    for (const pattern of TITLE_PATTERNS) {
      const titleMatch = window.match(pattern) ?? html.match(pattern);
      if (titleMatch?.[1]) {
        title = decodeHTMLEntities(titleMatch[1]);
        break;
      }
    }

    const titleScore = googleReviewIdentityScore(lookup, title, reviewURL);
    if (titleScore === 0) continue;

    const signal: ReviewSignal = {
      rating,
      reviewCount,
      url: sanitizedUserFacingReviewURL(reviewURL),
      source: "scraped_google_maps",
    };

    const reviewCountVal = reviewCount ?? 0;
    if (
      !bestSignal ||
      titleScore > bestSignal.score ||
      (titleScore === bestSignal.score && reviewCountVal > bestSignal.reviewCount)
    ) {
      bestSignal = { signal, score: titleScore, reviewCount: reviewCountVal };
    }
  }

  return bestSignal?.signal ?? null;
}

function parseGoogleReviewCount(raw: string): number | null {
  const normalized = raw
    .replace(/,/g, "")
    .replace(/\(/g, "")
    .replace(/\)/g, "")
    .trim()
    .toUpperCase();

  if (!normalized) return null;

  if (normalized.endsWith("K")) {
    const value = parseFloat(normalized.slice(0, -1));
    if (!isNaN(value)) return Math.round(value * 1000);
  }
  if (normalized.endsWith("M")) {
    const value = parseFloat(normalized.slice(0, -1));
    if (!isNaN(value)) return Math.round(value * 1000000);
  }
  const parsed = parseInt(normalized, 10);
  return isNaN(parsed) || parsed <= 0 ? null : parsed;
}

function decodeHTMLEntities(html: string): string {
  return html
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'")
    .replace(/&#x2F;/g, "/")
    .replace(/<[^>]*>/g, "")
    .trim();
}

const VENUE_DESCRIPTOR_TOKENS = new Set([
  "arena", "amphitheater", "amphitheatre", "auditorium",
  "bar", "bistro", "bowl", "brewery",
  "cafe", "center", "centre", "cinema", "club", "cocktail", "coliseum", "complex", "concert",
  "dome", "entertainment", "events",
  "field", "forum", "gallery", "garden", "gardens", "grill",
  "hall", "hotel", "house", "inn", "kitchen",
  "lanes", "live", "lounge", "museum", "music",
  "night", "nightclub", "opera",
  "palace", "park", "pavilion", "performing", "arts", "place", "plaza", "playhouse", "pub",
  "resort", "restaurant", "room", "rooftop",
  "saloon", "showroom", "space", "sports", "stadium", "stage", "steakhouse", "studio", "supperclub",
  "taproom", "tavern", "theater", "theatre", "tower",
  "venue", "village", "winery",
]);

const ARTICLE_TOKENS = new Set([
  "a", "an", "the", "la", "le", "l", "el", "los", "las", "de", "del", "da", "di", "du",
]);

function googleReviewIdentityScore(
  lookup: ReviewLookup,
  candidateTitle: string | null | undefined,
  reviewURL: string | null | undefined
): number {
  const normalizedAddress = normalizeToken(lookup.addressLine1 ?? "");
  const normalizedCity = normalizeToken(lookup.city ?? "");
  const normalizedState = normalizeStateToken(lookup.state ?? "");
  const normalizedPostalCode = normalizePostalCode(lookup.postalCode);

  const urlContext = googleReviewURLContext(reviewURL);
  const candidateContext = normalizeToken(
    [candidateTitle, urlContext.context].filter(Boolean).join(" ")
  );

  const addressMatch =
    normalizedAddress.length > 0 && candidateContext.includes(normalizedAddress);
  const localityMatch =
    (normalizedPostalCode.length > 0 &&
      candidateContext.includes(normalizedPostalCode)) ||
    (normalizedCity.length > 0 &&
      candidateContext.includes(normalizedCity) &&
      (normalizedState.length === 0 ||
        candidateContext.includes(normalizedState)));

  const hasCandidateAddressDigits = candidateContext
    .split(" ")
    .some((w) => /\d/.test(w));

  const candidateNames = new Set(
    [normalizeToken(candidateTitle ?? ""), urlContext.primaryName].filter(
      (v) => v.length > 0
    )
  );

  if (candidateNames.size === 0) return 0;

  const normalizedVenueName = normalizeToken(lookup.venueName);
  if (!normalizedVenueName) return 0;

  let bestScore = 0;
  for (const candidateName of candidateNames) {
    const score = venueIdentityScore(
      normalizedVenueName,
      candidateName,
      addressMatch,
      localityMatch,
      hasCandidateAddressDigits,
      normalizedAddress.length > 0
    );
    bestScore = Math.max(bestScore, score);
  }

  return bestScore;
}

function venueIdentityScore(
  expectedVenueName: string,
  candidateName: string,
  addressMatch: boolean,
  localityMatch: boolean,
  hasCandidateAddressDigits: boolean,
  hasExpectedAddress: boolean
): number {
  if (!expectedVenueName || !candidateName) return 0;

  const normalizedExpected = stripPunctuation(expectedVenueName);
  const normalizedCandidate = stripPunctuation(candidateName);

  if (
    normalizedExpected === normalizedCandidate ||
    expectedVenueName === candidateName
  ) {
    if (hasExpectedAddress && hasCandidateAddressDigits && !addressMatch)
      return 0;
    if (addressMatch) return 14;
    if (localityMatch) return 11;
    return 8;
  }

  if (
    normalizedExpected.includes(normalizedCandidate) ||
    normalizedCandidate.includes(normalizedExpected)
  ) {
    const shorter = Math.min(
      normalizedExpected.length,
      normalizedCandidate.length
    );
    const longer = Math.max(
      normalizedExpected.length,
      normalizedCandidate.length
    );
    if (shorter > 4 && shorter / longer > 0.6) {
      if (addressMatch) return 12;
      if (localityMatch) return 9;
      return 6;
    }
  }

  const expectedTokens = identityTokens(expectedVenueName);
  const candidateTokens = identityTokens(candidateName);
  if (expectedTokens.size === 0 || candidateTokens.size === 0) return 0;

  const sharedTokens = new Set(
    [...expectedTokens].filter((t) => candidateTokens.has(t))
  );
  if (sharedTokens.size === 0) return 0;

  if (
    hasExpectedAddress &&
    hasCandidateAddressDigits &&
    !addressMatch &&
    expectedTokens.size <= 2
  )
    return 0;

  if (expectedTokens.size === 1) {
    const token = [...expectedTokens][0];
    if (!candidateTokens.has(token)) return 0;
    const extras = new Set(
      [...candidateTokens].filter((t) => t !== token)
    );
    if (extras.size === 0) {
      if (addressMatch) return 13;
      if (localityMatch) return 9;
      return 5;
    }
    if ([...extras].every((t) => VENUE_DESCRIPTOR_TOKENS.has(t))) {
      if (addressMatch) return 11;
      if (localityMatch) return 7;
      return 4;
    }
    return 0;
  }

  const coverage = sharedTokens.size / expectedTokens.size;

  const allExpectedInCandidate = [...expectedTokens].every((t) =>
    candidateTokens.has(t)
  );

  if (!allExpectedInCandidate) {
    if (coverage >= 0.75 && expectedTokens.size >= 2) {
      if (addressMatch) return 8;
      if (localityMatch) return 6;
      return 3;
    }
    if (
      addressMatch &&
      expectedTokens.size >= 3 &&
      sharedTokens.size === expectedTokens.size - 1
    )
      return 7;
    if (
      localityMatch &&
      expectedTokens.size >= 3 &&
      sharedTokens.size === expectedTokens.size - 1
    )
      return 5;
    return 0;
  }

  const extras = new Set(
    [...candidateTokens].filter((t) => !expectedTokens.has(t))
  );
  if (extras.size === 0) {
    if (addressMatch) return 13;
    if (localityMatch) return 10;
    return 6;
  }
  if ([...extras].every((t) => VENUE_DESCRIPTOR_TOKENS.has(t))) {
    if (addressMatch) return 10;
    if (localityMatch) return 7;
    return 5;
  }
  if (extras.size <= 2) {
    if (addressMatch) return 8;
    if (localityMatch) return 5;
  }
  return 0;
}

function stripPunctuation(value: string): string {
  return value
    .replace(/[^a-zA-Z0-9 ]/g, "")
    .split(/\s+/)
    .join(" ");
}

function identityTokens(normalizedValue: string): Set<string> {
  const tokens = new Set(normalizedValue.split(/\s+/).filter((t) => t.length > 0));
  for (const article of ARTICLE_TOKENS) {
    tokens.delete(article);
  }
  return tokens;
}

function normalizePostalCode(value: string | null | undefined): string {
  if (!value) return "";
  const digits = value.replace(/\D/g, "");
  return digits.length >= 5 ? digits.substring(0, 5) : digits;
}

function googleReviewURLContext(
  reviewURL: string | null | undefined
): { primaryName: string; context: string } {
  if (!reviewURL?.trim()) return { primaryName: "", context: "" };

  const fragments: string[] = [];
  try {
    const url = new URL(reviewURL);
    const interestingParams = new Set([
      "query",
      "q",
      "destination",
      "daddr",
      "place",
    ]);
    for (const [key, value] of url.searchParams) {
      if (interestingParams.has(key.toLowerCase()) && value) {
        fragments.push(decodeURIComponent(value.replace(/\+/g, " ")));
      }
    }

    const pathComponents = url.pathname
      .split("/")
      .map((c) => decodeURIComponent(c.replace(/\+/g, " ")));
    for (const marker of ["search", "place"]) {
      const index = pathComponents.findIndex(
        (c) => normalizeToken(c) === marker
      );
      if (index < 0) continue;
      const tail = pathComponents
        .slice(index + 1)
        .filter((c) => {
          const n = normalizeToken(c);
          return n.length > 0 && n !== "data" && !n.startsWith("@");
        })
        .join(" ");
      if (tail) fragments.push(tail);
    }
  } catch {}

  if (fragments.length === 0) {
    try {
      fragments.push(decodeURIComponent(reviewURL));
    } catch {
      fragments.push(reviewURL);
    }
  }

  const normalizedFragments = fragments
    .map(normalizeToken)
    .filter((f) => f.length > 0);

  const primaryName =
    normalizedFragments
      .filter((f) => f.length <= 80)
      .sort((a, b) => a.length - b.length)[0] ?? "";

  return { primaryName, context: normalizedFragments.join(" ") };
}

async function fetchGooglePlacesReviewFallback(
  lookup: ReviewLookup,
  apiKey: string
): Promise<ReviewSignal | null> {
  const query = [lookup.venueName, lookup.city, lookup.state]
    .filter(Boolean)
    .join(", ");

  const body: Record<string, unknown> = {
    textQuery: query,
    maxResultCount: 1,
  };

  if (lookup.city || lookup.state) {
    const lat =
      typeof (lookup as unknown as Record<string, unknown>).latitude ===
      "number"
        ? (lookup as unknown as Record<string, number>).latitude
        : undefined;
    const lng =
      typeof (lookup as unknown as Record<string, unknown>).longitude ===
      "number"
        ? (lookup as unknown as Record<string, number>).longitude
        : undefined;
    if (lat && lng) {
      body.locationBias = {
        circle: { center: { latitude: lat, longitude: lng }, radius: 5000 },
      };
    }
  }

  try {
    const response = await fetch(
      "https://places.googleapis.com/v1/places:searchText",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": apiKey,
          "X-Goog-FieldMask":
            "places.id,places.rating,places.userRatingCount,places.googleMapsUri",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(10000),
      }
    );

    if (!response.ok) return null;

    const data = await response.json();
    const place = data?.places?.[0];
    if (!place) return null;

    const rating = sanitizeReviewRating(place.rating);
    if (!rating) return null;

    return {
      rating,
      reviewCount: sanitizeReviewCount(place.userRatingCount) ?? 0,
      url: place.googleMapsUri ?? "",
      source: "google_places_api",
    };
  } catch {
    return null;
  }
}
