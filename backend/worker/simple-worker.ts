import { loadConfig, type WorkerConfig } from "./lib/config";
import {
  getSupabase,
  upsertSnapshot,
  recordSourceHealth,
  recordCoverageMetrics,
  type Metro,
} from "./lib/supabase";
import {
  fetchTicketmaster,
  fetchEventbrite,
  enrichEventsWithReviews,
  enrichEventsWithNightlife,
  type AdapterResult,
  type EventResult,
} from "./adapters";
import { buildSnapshot } from "./lib/snapshot-builder";
import {
  cacheKey,
  isHighDensityMetro,
  sanitizeReviewRating,
} from "./lib/normalize";

type Intent =
  | "nearby_and_worth_it"
  | "biggest_tonight"
  | "exclusive_hot"
  | "last_minute_plans";

interface SimpleMetro extends Metro {}

interface RefreshSummary {
  metroSlug: string;
  metroDisplayName: string;
  intent: Intent;
  startedAt: string;
  completedAt?: string;
  status: "running" | "completed" | "failed";
  eventCount?: number;
  nightlifeVenueCount?: number;
  reviewCoveragePct?: number;
  error?: string;
}

const INTENTS: Intent[] = [
  "nearby_and_worth_it",
  "biggest_tonight",
  "exclusive_hot",
  "last_minute_plans",
];

const METROS: SimpleMetro[] = [
  metro("los-angeles", "Los Angeles, CA", "Los Angeles", "CA", 34.0522, -118.2437, "90012", 1, 60),
  metro("west-hollywood", "West Hollywood, CA", "West Hollywood", "CA", 34.0901, -118.3852, "90069", 1, 60),
  metro("new-york", "New York, NY", "New York", "NY", 40.7128, -74.0060, "10001", 1, 60),
  metro("miami-beach", "Miami Beach, FL", "Miami Beach", "FL", 25.7826, -80.1341, "33139", 1, 60),
  metro("chicago", "Chicago, IL", "Chicago", "IL", 41.8781, -87.6298, "60601", 1, 90),
  metro("las-vegas", "Las Vegas, NV", "Las Vegas", "NV", 36.1699, -115.1398, "89101", 1, 90),
  metro("austin", "Austin, TX", "Austin", "TX", 30.2672, -97.7431, "78701", 1, 90),
  metro("nashville", "Nashville, TN", "Nashville", "TN", 36.1627, -86.7816, "37203", 1, 90),
  metro("dallas", "Dallas, TX", "Dallas", "TX", 32.7767, -96.7970, "75201", 2, 120),
  metro("houston", "Houston, TX", "Houston", "TX", 29.7604, -95.3698, "77002", 2, 120),
  metro("atlanta", "Atlanta, GA", "Atlanta", "GA", 33.7490, -84.3880, "30303", 2, 120),
  metro("san-francisco", "San Francisco, CA", "San Francisco", "CA", 37.7749, -122.4194, "94102", 2, 120),
  metro("seattle", "Seattle, WA", "Seattle", "WA", 47.6062, -122.3321, "98101", 2, 120),
  metro("denver", "Denver, CO", "Denver", "CO", 39.7392, -104.9903, "80202", 2, 120),
  metro("phoenix", "Phoenix, AZ", "Phoenix", "AZ", 33.4484, -112.074, "85004", 2, 120),
  metro("boston", "Boston, MA", "Boston", "MA", 42.3601, -71.0589, "02101", 2, 120),
  metro("philadelphia", "Philadelphia, PA", "Philadelphia", "PA", 39.9526, -75.1652, "19102", 2, 180),
  metro("san-diego", "San Diego, CA", "San Diego", "CA", 32.7157, -117.1611, "92101", 2, 180),
  metro("portland", "Portland, OR", "Portland", "OR", 45.5152, -122.6784, "97201", 2, 180),
  metro("washington-dc", "Washington, DC", "Washington", "DC", 38.9072, -77.0369, "20001", 2, 120),
  metro("new-orleans", "New Orleans, LA", "New Orleans", "LA", 29.9511, -90.0715, "70112", 2, 180),
  metro("orlando", "Orlando, FL", "Orlando", "FL", 28.5383, -81.3792, "32801", 3, 240),
  metro("tampa", "Tampa, FL", "Tampa", "FL", 27.9506, -82.4572, "33602", 3, 240),
  metro("minneapolis", "Minneapolis, MN", "Minneapolis", "MN", 44.9778, -93.265, "55401", 3, 240),
  metro("charlotte", "Charlotte, NC", "Charlotte", "NC", 35.2271, -80.8431, "28202", 3, 240),
  metro("raleigh", "Raleigh, NC", "Raleigh", "NC", 35.7796, -78.6382, "27601", 3, 240),
  metro("detroit", "Detroit, MI", "Detroit", "MI", 42.3314, -83.0458, "48201", 3, 240),
  metro("salt-lake-city", "Salt Lake City, UT", "Salt Lake City", "UT", 40.7608, -111.891, "84101", 3, 240),
  metro("kansas-city", "Kansas City, MO", "Kansas City", "MO", 39.0997, -94.5786, "64105", 3, 240),
  metro("sacramento", "Sacramento, CA", "Sacramento", "CA", 38.5816, -121.4944, "95814", 3, 240),
  metro("columbus", "Columbus, OH", "Columbus", "OH", 39.9612, -82.9988, "43215", 3, 360),
  metro("pittsburgh", "Pittsburgh, PA", "Pittsburgh", "PA", 40.4406, -79.9959, "15222", 3, 360),
  metro("cleveland", "Cleveland, OH", "Cleveland", "OH", 41.4993, -81.6944, "44113", 3, 360),
  metro("cincinnati", "Cincinnati, OH", "Cincinnati", "OH", 39.1031, -84.512, "45202", 3, 360),
  metro("indianapolis", "Indianapolis, IN", "Indianapolis", "IN", 39.7684, -86.1581, "46204", 3, 360),
  metro("milwaukee", "Milwaukee, WI", "Milwaukee", "WI", 43.0389, -87.9065, "53202", 3, 360),
  metro("st-louis", "St. Louis, MO", "St. Louis", "MO", 38.627, -90.1994, "63101", 3, 360),
  metro("baltimore", "Baltimore, MD", "Baltimore", "MD", 39.2904, -76.6122, "21201", 3, 360),
];

const lastRunByKey = new Map<string, number>();
const recentRuns: RefreshSummary[] = [];
let running = false;
let loopPromise: Promise<void> | null = null;
let activeRefresh: RefreshSummary | null = null;

function metro(
  slug: string,
  display_name: string,
  city: string,
  state: string,
  latitude: number,
  longitude: number,
  postal_code: string,
  tier: number,
  refresh_interval_minutes: number
): SimpleMetro {
  return {
    id: slug,
    slug,
    display_name,
    city,
    state,
    country_code: "US",
    latitude,
    longitude,
    postal_code,
    tier,
    refresh_interval_minutes,
  };
}

export function getSimpleWorkerStatus(): {
  running: boolean;
  activeRefresh: RefreshSummary | null;
  recentRuns: RefreshSummary[];
  configuredMetros: number;
} {
  return {
    running,
    activeRefresh,
    recentRuns: recentRuns.slice(0, 20),
    configuredMetros: METROS.length,
  };
}

export async function startSimpleWorker(): Promise<void> {
  if (loopPromise) {
    await loopPromise;
    return;
  }

  running = true;
  loopPromise = runLoop();
  await loopPromise;
}

export function stopSimpleWorker(): void {
  running = false;
}

export async function triggerMetroRefresh(
  metroSlug: string,
  intent: Intent
): Promise<RefreshSummary> {
  const metro = METROS.find((item) => item.slug === metroSlug);
  if (!metro) {
    throw new Error(`Unknown metro slug: ${metroSlug}`);
  }

  const config = loadConfig();
  const supabase = getSupabase(config);
  return refreshMetroIntent(config, supabase, metro, intent, "manual");
}

async function runLoop(): Promise<void> {
  const config = loadConfig();
  const supabase = getSupabase(config);

  while (running) {
    const dueMetro = nextDueMetro();
    if (!dueMetro) {
      await sleep(30_000);
      continue;
    }

    for (const intent of INTENTS) {
      if (!running) break;
      try {
        await refreshMetroIntent(config, supabase, dueMetro, intent, "scheduled");
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`[simple-worker] ${dueMetro.slug}/${intent} failed: ${message}`);
      }
      await sleep(1_500);
    }
  }
}

function nextDueMetro(): SimpleMetro | null {
  const now = Date.now();
  const sorted = [...METROS].sort((lhs, rhs) => lhs.tier - rhs.tier);
  for (const metro of sorted) {
    const key = `${metro.slug}::all`;
    const lastRun = lastRunByKey.get(key) ?? 0;
    if (now - lastRun >= metro.refresh_interval_minutes * 60_000) {
      return metro;
    }
  }
  return null;
}

async function refreshMetroIntent(
  config: WorkerConfig,
  supabase: ReturnType<typeof getSupabase>,
  metro: SimpleMetro,
  intent: Intent,
  reason: "scheduled" | "manual"
): Promise<RefreshSummary> {
  const startedAt = new Date().toISOString();
  const summary: RefreshSummary = {
    metroSlug: metro.slug,
    metroDisplayName: metro.display_name,
    intent,
    startedAt,
    status: "running",
  };
  activeRefresh = summary;

  const adapterResults: AdapterResult[] = [];
  const notes: string[] = [`refresh_reason:${reason}`];

  const [tmResult, ebResult] = await Promise.allSettled([
    config.ticketmasterApiKey
      ? fetchTicketmaster(metro, intent, config.ticketmasterApiKey)
      : Promise.resolve(emptyAdapterResult("ticketmaster", "No API key")),
    config.eventbriteToken
      ? fetchEventbrite(metro, intent, config.eventbriteToken)
      : Promise.resolve(emptyAdapterResult("eventbrite", "No token")),
  ]);

  if (tmResult.status === "fulfilled") {
    adapterResults.push(tmResult.value);
  } else {
    notes.push(`Ticketmaster adapter error: ${String(tmResult.reason)}`);
  }

  if (ebResult.status === "fulfilled") {
    adapterResults.push(ebResult.value);
  } else {
    notes.push(`Eventbrite adapter error: ${String(ebResult.reason)}`);
  }

  let allEvents: EventResult[] = [];
  const eventsBySource = new Map<string, EventResult[]>();

  for (const result of adapterResults) {
    allEvents.push(...result.events);
    eventsBySource.set(result.source, [...result.events]);
    await recordSourceHealth(supabase, {
      source: result.source,
      metro_id: metro.id,
      request_count: result.requestCount,
      success_count: result.successCount,
      failure_count: result.failureCount,
      timeout_count: result.timeoutCount,
      event_count: result.events.length,
      avg_latency_ms: result.avgLatencyMs,
    });
  }

  const nightlifeResult = await enrichEventsWithNightlife(allEvents, metro, config);
  allEvents = nightlifeResult.events;
  notes.push(...nightlifeResult.notes);

  const reviewResult = await enrichEventsWithReviews(allEvents, config, supabase);
  allEvents = reviewResult.events;

  for (const [source] of eventsBySource) {
    eventsBySource.set(
      source,
      allEvents.filter((event) => event.source === source)
    );
  }

  const nightlifeEvents = allEvents.filter((event) =>
    event.source === "discotech" || event.source === "clubbable" || event.source === "hwood"
  );
  if (nightlifeEvents.length > 0) {
    for (const event of nightlifeEvents) {
      const existing = eventsBySource.get(event.source) || [];
      existing.push(event);
      eventsBySource.set(event.source, existing);
    }
  }

  const snapshot = buildSnapshot(metro, intent, eventsBySource, notes);
  const isHighDensity = isHighDensityMetro(metro.city);
  const key = cacheKey(
    intent,
    metro.country_code,
    metro.latitude,
    metro.longitude,
    isHighDensity
  );

  const fetchedAt = new Date().toISOString();
  const expiresAt = new Date(
    Date.now() + ttlForIntent(intent) * 60 * 60 * 1000
  ).toISOString();

  const nightlifeCount = snapshot.mergedEvents.filter(
    (event) => event.eventType === "party / nightlife"
  ).length;
  const exclusiveCount = snapshot.mergedEvents.filter((event) => {
    const payload = JSON.parse(event.rawSourcePayload || "{}");
    return (
      event.eventType === "party / nightlife" &&
      (payload.discotech_url || payload.clubbable_url)
    );
  }).length;
  const reviewEligible = snapshot.mergedEvents.filter(
    (event) => event.eventType !== "party / nightlife"
  );
  const reviewCovered = reviewEligible.filter(
    (event) => sanitizeReviewRating(event.venueRating) !== null
  );
  const reviewCoveragePct =
    reviewEligible.length > 0 ? reviewCovered.length / reviewEligible.length : 0;

  await upsertSnapshot(supabase, {
    cache_key: key,
    intent,
    quality: "full",
    country_code: metro.country_code,
    display_name: metro.display_name,
    city: metro.city,
    state: metro.state,
    postal_code: metro.postal_code ?? undefined,
    latitude: metro.latitude,
    longitude: metro.longitude,
    bucket_latitude: Math.round(metro.latitude / (isHighDensity ? 0.12 : 0.08)) * (isHighDensity ? 0.12 : 0.08),
    bucket_longitude: Math.round(metro.longitude / (isHighDensity ? 0.12 : 0.08)) * (isHighDensity ? 0.12 : 0.08),
    event_count: snapshot.mergedEvents.length,
    exclusive_count: exclusiveCount,
    nightlife_count: nightlifeCount,
    snapshot,
    fetched_at: fetchedAt,
    expires_at: expiresAt,
    worker_id: config.workerId,
    review_coverage_pct: reviewCoveragePct,
    is_server_generated: true,
  });

  await recordCoverageMetrics(supabase, {
    metro_id: metro.id,
    intent,
    total_events: snapshot.mergedEvents.length,
    unique_venues: new Set(snapshot.mergedEvents.map((event) => event.venueName).filter(Boolean)).size,
    review_eligible_count: reviewEligible.length,
    review_covered_count: reviewCovered.length,
    review_coverage_pct: reviewCoveragePct,
    nightlife_count: nightlifeCount,
    sports_count: snapshot.mergedEvents.filter((event) => event.eventType === "sports event").length,
    concert_count: snapshot.mergedEvents.filter((event) => event.eventType === "concert").length,
    community_count: snapshot.mergedEvents.filter((event) => event.eventType === "social / community event" || event.eventType === "weekend activity").length,
    poisoned_review_count: reviewResult.poisonedCount ?? 0,
    notes,
  });

  const finishedSummary: RefreshSummary = {
    ...summary,
    completedAt: new Date().toISOString(),
    status: "completed",
    eventCount: snapshot.mergedEvents.length,
    nightlifeVenueCount: nightlifeResult.venueCount,
    reviewCoveragePct,
  };
  rememberRun(finishedSummary);
  lastRunByKey.set(`${metro.slug}::all`, Date.now());
  activeRefresh = null;

  console.log(
    `[simple-worker] ${metro.display_name}/${intent}: ${snapshot.mergedEvents.length} events, ` +
      `${nightlifeResult.venueCount} nightlife venues, review coverage ${(reviewCoveragePct * 100).toFixed(1)}%`
  );

  return finishedSummary;
}

function rememberRun(summary: RefreshSummary): void {
  recentRuns.unshift(summary);
  if (recentRuns.length > 50) {
    recentRuns.length = 50;
  }
}

function ttlForIntent(intent: Intent): number {
  switch (intent) {
    case "biggest_tonight":
      return 48;
    case "last_minute_plans":
      return 24;
    case "exclusive_hot":
      return 72;
    case "nearby_and_worth_it":
      return 96;
  }
}

function emptyAdapterResult(source: string, note: string): AdapterResult {
  return {
    source,
    events: [],
    requestCount: 0,
    successCount: 0,
    failureCount: 0,
    timeoutCount: 0,
    avgLatencyMs: 0,
    notes: [note],
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
