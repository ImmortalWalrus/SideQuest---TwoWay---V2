import type { Metro } from "../lib/supabase";

export interface EventResult {
  id: string;
  source: string;
  sourceEventId: string;
  sourceParentId?: string;
  sourceUrl?: string;
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
  venueName?: string;
  venueId?: string;
  addressLine1?: string;
  city?: string;
  state?: string;
  postalCode?: string;
  country?: string;
  latitude?: number;
  longitude?: number;
  imageUrl?: string;
  status?: string;
  priceMin?: number;
  priceMax?: number;
  currency?: string;
  ticketUrl?: string;
  tags?: string[];
  rawSourcePayload?: Record<string, unknown>;
}

export interface AdapterResult {
  source: string;
  events: EventResult[];
  requestCount: number;
  successCount: number;
  failureCount: number;
  timeoutCount: number;
  avgLatencyMs: number;
  notes: string[];
}

interface TmEvent {
  id: string;
  name: string;
  type?: string;
  url?: string;
  dates?: {
    start?: { localDate?: string; localTime?: string; dateTime?: string };
    end?: { localDate?: string; localTime?: string; dateTime?: string };
    timezone?: string;
    status?: { code?: string };
  };
  classifications?: Array<{
    segment?: { name?: string };
    genre?: { name?: string };
    subGenre?: { name?: string };
  }>;
  _embedded?: {
    venues?: Array<{
      id?: string;
      name?: string;
      address?: { line1?: string };
      city?: { name?: string };
      state?: { stateCode?: string };
      postalCode?: string;
      country?: { countryCode?: string };
      location?: { latitude?: string; longitude?: string };
      timezone?: string;
    }>;
  };
  images?: Array<{ url?: string; width?: number; ratio?: string }>;
  priceRanges?: Array<{ min?: number; max?: number; currency?: string }>;
  info?: string;
  pleaseNote?: string;
}

const CLASSIFICATION_CHANNELS = [
  { classificationName: "Music", eventType: "concert" },
  { classificationName: "Sports", eventType: "sports event" },
  { classificationName: "Arts & Theatre", eventType: "other live event" },
  { classificationName: "Comedy", eventType: "other live event" },
];

export async function fetchTicketmaster(
  metro: Metro,
  intent: string,
  apiKey: string
): Promise<AdapterResult> {
  const result: AdapterResult = {
    source: "ticketmaster",
    events: [],
    requestCount: 0,
    successCount: 0,
    failureCount: 0,
    timeoutCount: 0,
    avgLatencyMs: 0,
    notes: [],
  };

  if (!apiKey) {
    result.notes.push("Missing Ticketmaster API key");
    return result;
  }

  const radiusMiles = intent === "biggest_tonight" ? 25 : 15;
  const pageSize = intent === "biggest_tonight" ? 50 : 30;
  const latencies: number[] = [];

  for (const channel of CLASSIFICATION_CHANNELS) {
    const url = new URL("https://app.ticketmaster.com/discovery/v2/events.json");
    url.searchParams.set("apikey", apiKey);
    url.searchParams.set("countryCode", metro.country_code);
    url.searchParams.set("classificationName", channel.classificationName);
    url.searchParams.set("latlong", `${metro.latitude},${metro.longitude}`);
    url.searchParams.set("radius", String(radiusMiles));
    url.searchParams.set("unit", "miles");
    url.searchParams.set("size", String(pageSize));
    url.searchParams.set("sort", "date,asc");
    url.searchParams.set("startDateTime", upcomingStartDateTime());

    if (metro.state) {
      url.searchParams.set("stateCode", metro.state);
    }

    result.requestCount++;
    const start = Date.now();

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 15000);

      const response = await fetch(url.toString(), {
        signal: controller.signal,
        headers: { Accept: "application/json" },
      });
      clearTimeout(timeout);

      const latency = Date.now() - start;
      latencies.push(latency);

      if (!response.ok) {
        result.failureCount++;
        result.notes.push(
          `Ticketmaster ${channel.classificationName}: HTTP ${response.status}`
        );
        continue;
      }

      result.successCount++;
      const body = await response.json();
      const embedded = body?._embedded?.events as TmEvent[] | undefined;

      if (!embedded || embedded.length === 0) continue;

      for (const raw of embedded) {
        const event = normalizeTmEvent(raw, channel.eventType);
        if (event) result.events.push(event);
      }
    } catch (err: unknown) {
      const latency = Date.now() - start;
      latencies.push(latency);
      if (err instanceof DOMException && err.name === "AbortError") {
        result.timeoutCount++;
        result.notes.push(`Ticketmaster ${channel.classificationName}: timeout`);
      } else {
        result.failureCount++;
        result.notes.push(
          `Ticketmaster ${channel.classificationName}: ${String(err)}`
        );
      }
    }
  }

  result.avgLatencyMs =
    latencies.length > 0
      ? Math.round(latencies.reduce((a, b) => a + b, 0) / latencies.length)
      : 0;

  return result;
}

function normalizeTmEvent(raw: TmEvent, defaultEventType: string): EventResult | null {
  if (!raw.id || !raw.name) return null;

  const venue = raw._embedded?.venues?.[0];
  const classification = raw.classifications?.[0];
  const segment = classification?.segment?.name?.toLowerCase() ?? "";
  const genre = classification?.genre?.name?.toLowerCase() ?? "";

  let eventType = defaultEventType;
  if (segment === "music" || genre.includes("music") || genre.includes("rock") || genre.includes("pop")) {
    eventType = "concert";
  } else if (segment === "sports") {
    eventType = "sports event";
  }

  const bestImage = pickBestImage(raw.images);
  const priceRange = raw.priceRanges?.[0];

  return {
    id: `ticketmaster:${raw.id}`,
    source: "ticketmaster",
    sourceEventId: raw.id,
    sourceParentId: venue?.id,
    sourceUrl: raw.url,
    title: raw.name,
    shortDescription: raw.info?.substring(0, 200),
    fullDescription: raw.info,
    category: classification?.segment?.name,
    subcategory: classification?.genre?.name,
    eventType,
    startAtUTC: raw.dates?.start?.dateTime,
    startLocal: raw.dates?.start?.localDate
      ? `${raw.dates.start.localDate}T${raw.dates.start.localTime || "00:00:00"}`
      : undefined,
    endAtUTC: raw.dates?.end?.dateTime,
    timezone: venue?.timezone || raw.dates?.timezone,
    venueName: venue?.name,
    venueId: venue?.id,
    addressLine1: venue?.address?.line1,
    city: venue?.city?.name,
    state: venue?.state?.stateCode,
    postalCode: venue?.postalCode,
    country: venue?.country?.countryCode,
    latitude: venue?.location?.latitude ? parseFloat(venue.location.latitude) : undefined,
    longitude: venue?.location?.longitude ? parseFloat(venue.location.longitude) : undefined,
    imageUrl: bestImage,
    status: mapTmStatus(raw.dates?.status?.code),
    priceMin: priceRange?.min,
    priceMax: priceRange?.max,
    currency: priceRange?.currency,
    ticketUrl: raw.url,
    tags: [
      classification?.segment?.name,
      classification?.genre?.name,
      classification?.subGenre?.name,
    ].filter(Boolean) as string[],
    rawSourcePayload: {
      ticketmaster_id: raw.id,
      ticketmaster_url: raw.url,
      classification_segment: classification?.segment?.name,
      classification_genre: classification?.genre?.name,
    },
  };
}

function pickBestImage(
  images?: Array<{ url?: string; width?: number; ratio?: string }>
): string | undefined {
  if (!images || images.length === 0) return undefined;
  const preferred = images
    .filter((img) => img.url && img.ratio === "16_9" && (img.width ?? 0) >= 640)
    .sort((a, b) => (b.width ?? 0) - (a.width ?? 0));
  return preferred[0]?.url || images[0]?.url;
}

function mapTmStatus(code?: string): string {
  switch (code) {
    case "onsale": return "onsale";
    case "offsale": return "scheduled";
    case "cancelled": return "cancelled";
    case "postponed": return "postponed";
    case "rescheduled": return "rescheduled";
    default: return "scheduled";
  }
}

function upcomingStartDateTime(): string {
  const now = new Date();
  return now.toISOString().replace(/\.\d{3}Z$/, "Z");
}
