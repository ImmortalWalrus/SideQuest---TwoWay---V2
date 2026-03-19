import type { Metro } from "../lib/supabase";
import type { AdapterResult, EventResult } from "./ticketmaster";

interface EbEvent {
  id: string;
  name?: { text?: string };
  description?: { text?: string };
  url?: string;
  start?: { utc?: string; local?: string; timezone?: string };
  end?: { utc?: string; local?: string; timezone?: string };
  venue_id?: string;
  category_id?: string;
  is_free?: boolean;
  online_event?: boolean;
  status?: string;
  logo?: { url?: string; original?: { url?: string } };
}

interface EbVenue {
  id?: string;
  name?: string;
  address?: {
    address_1?: string;
    city?: string;
    region?: string;
    postal_code?: string;
    country?: string;
    latitude?: string;
    longitude?: string;
  };
}

const CATEGORY_MAP: Record<string, string> = {
  "103": "concert",
  "101": "other live event",
  "105": "concert",
  "110": "social / community event",
  "108": "sports event",
  "107": "weekend activity",
};

export async function fetchEventbrite(
  metro: Metro,
  intent: string,
  token: string
): Promise<AdapterResult> {
  const result: AdapterResult = {
    source: "eventbrite",
    events: [],
    requestCount: 0,
    successCount: 0,
    failureCount: 0,
    timeoutCount: 0,
    avgLatencyMs: 0,
    notes: [],
  };

  if (!token) {
    result.notes.push("Missing Eventbrite token");
    return result;
  }

  const url = new URL("https://www.eventbriteapi.com/v3/events/search/");
  url.searchParams.set("location.latitude", String(metro.latitude));
  url.searchParams.set("location.longitude", String(metro.longitude));
  url.searchParams.set("location.within", "15mi");
  url.searchParams.set("start_date.keyword", "this_week");
  url.searchParams.set("sort_by", "date");
  url.searchParams.set("expand", "venue");
  url.searchParams.set("page_size", "50");

  result.requestCount++;
  const start = Date.now();

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);

    const response = await fetch(url.toString(), {
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    });
    clearTimeout(timeout);
    result.avgLatencyMs = Date.now() - start;

    if (!response.ok) {
      result.failureCount++;
      result.notes.push(`Eventbrite: HTTP ${response.status}`);
      return result;
    }

    result.successCount++;
    const body = await response.json();
    const events = body?.events as Array<EbEvent & { venue?: EbVenue }> | undefined;

    if (!events) return result;

    for (const raw of events) {
      if (raw.online_event) continue;
      const event = normalizeEbEvent(raw);
      if (event) result.events.push(event);
    }
  } catch (err: unknown) {
    result.avgLatencyMs = Date.now() - start;
    if (err instanceof DOMException && err.name === "AbortError") {
      result.timeoutCount++;
      result.notes.push("Eventbrite: timeout");
    } else {
      result.failureCount++;
      result.notes.push(`Eventbrite: ${String(err)}`);
    }
  }

  return result;
}

function normalizeEbEvent(
  raw: EbEvent & { venue?: EbVenue }
): EventResult | null {
  const title = raw.name?.text;
  if (!raw.id || !title) return null;

  const venue = raw.venue;
  const addr = venue?.address;
  const eventType = CATEGORY_MAP[raw.category_id ?? ""] || "other live event";

  return {
    id: `eventbrite:${raw.id}`,
    source: "eventbrite",
    sourceEventId: raw.id,
    sourceUrl: raw.url,
    title,
    shortDescription: raw.description?.text?.substring(0, 200),
    fullDescription: raw.description?.text,
    eventType,
    startAtUTC: raw.start?.utc,
    endAtUTC: raw.end?.utc,
    startLocal: raw.start?.local,
    endLocal: raw.end?.local,
    timezone: raw.start?.timezone,
    venueName: venue?.name,
    venueId: venue?.id,
    addressLine1: addr?.address_1,
    city: addr?.city,
    state: addr?.region,
    postalCode: addr?.postal_code,
    country: addr?.country,
    latitude: addr?.latitude ? parseFloat(addr.latitude) : undefined,
    longitude: addr?.longitude ? parseFloat(addr.longitude) : undefined,
    imageUrl: raw.logo?.original?.url || raw.logo?.url,
    status: mapEbStatus(raw.status),
    priceMin: raw.is_free ? 0 : undefined,
    priceMax: raw.is_free ? 0 : undefined,
    currency: raw.is_free ? "USD" : undefined,
    ticketUrl: raw.url,
    rawSourcePayload: {
      eventbrite_id: raw.id,
      eventbrite_url: raw.url,
      eventbrite_category_id: raw.category_id,
    },
  };
}

function mapEbStatus(status?: string): string {
  switch (status) {
    case "live": return "onsale";
    case "completed": return "ended";
    case "canceled": return "cancelled";
    default: return "scheduled";
  }
}
