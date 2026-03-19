import { loadConfig, type WorkerConfig } from "./lib/config";
import {
  getSupabase,
  claimJob,
  heartbeatJob,
  completeJob,
  failJob,
  reclaimStaleJobs,
  enqueueScheduledRefreshes,
  getMetro,
  insertRefreshRun,
  updateRefreshRun,
  upsertSnapshot,
  recordSourceHealth,
  recordCoverageMetrics,
} from "./lib/supabase";
import {
  fetchTicketmaster,
  fetchEventbrite,
  enrichEventsWithReviews,
  type AdapterResult,
  type EventResult,
} from "./adapters";
import { buildSnapshot } from "./lib/snapshot-builder";
import {
  cacheKey,
  isHighDensityMetro,
  sanitizeReviewRating,
} from "./lib/normalize";

let running = false;

export async function startWorker(): Promise<void> {
  const config = loadConfig();
  const supabase = getSupabase(config);

  console.log(`[worker] Starting ${config.workerId}`);
  console.log(`[worker] Poll interval: ${config.pollIntervalMs}ms`);
  console.log(`[worker] Max concurrent: ${config.maxConcurrentJobs}`);

  running = true;
  let schedulerTickCount = 0;

  const schedulerLoop = setInterval(async () => {
    schedulerTickCount++;

    const reclaimed = await reclaimStaleJobs(
      supabase,
      config.heartbeatTimeoutMinutes
    );
    if (reclaimed > 0) {
      console.log(`[scheduler] Reclaimed ${reclaimed} stale jobs`);
    }

    if (schedulerTickCount % 6 === 0) {
      const enqueued = await enqueueScheduledRefreshes(supabase);
      if (enqueued > 0) {
        console.log(`[scheduler] Enqueued ${enqueued} scheduled refreshes`);
      }
    }
  }, 60_000);

  const enqueued = await enqueueScheduledRefreshes(supabase);
  console.log(`[scheduler] Initial enqueue: ${enqueued} jobs`);

  while (running) {
    try {
      const job = await claimJob(supabase, config.workerId);

      if (!job) {
        await sleep(config.pollIntervalMs);
        continue;
      }

      console.log(
        `[worker] Claimed job ${job.id} (metro=${job.metro_id}, intent=${job.intent})`
      );

      const metro = await getMetro(supabase, job.metro_id);
      if (!metro) {
        console.error(`[worker] Metro ${job.metro_id} not found`);
        await failJob(supabase, job.id, config.workerId, "Metro not found");
        continue;
      }

      const heartbeatInterval = setInterval(async () => {
        await heartbeatJob(supabase, job.id, config.workerId);
      }, config.heartbeatIntervalMs);

      try {
        await processJob(config, supabase, job, metro);
        await completeJob(supabase, job.id, config.workerId);
        console.log(
          `[worker] Completed job ${job.id} (${metro.display_name} / ${job.intent})`
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`[worker] Job ${job.id} failed: ${msg}`);
        await failJob(supabase, job.id, config.workerId, msg);
      } finally {
        clearInterval(heartbeatInterval);
      }
    } catch (err) {
      console.error("[worker] Loop error:", err);
      await sleep(5000);
    }
  }

  clearInterval(schedulerLoop);
  console.log("[worker] Stopped");
}

export function stopWorker(): void {
  running = false;
}

async function processJob(
  config: WorkerConfig,
  supabase: ReturnType<typeof getSupabase>,
  job: { id: string; metro_id: string; intent: string },
  metro: NonNullable<Awaited<ReturnType<typeof getMetro>>>
): Promise<void> {
  const startTime = Date.now();

  const runId = await insertRefreshRun(supabase, {
    job_id: job.id,
    metro_id: job.metro_id,
    worker_id: config.workerId,
    intent: job.intent,
  });

  const adapterResults: AdapterResult[] = [];
  const notes: string[] = [];

  const [tmResult, ebResult] = await Promise.allSettled([
    config.ticketmasterApiKey
      ? fetchTicketmaster(metro, job.intent, config.ticketmasterApiKey)
      : Promise.resolve(emptyAdapterResult("ticketmaster", "No API key")),
    config.eventbriteToken
      ? fetchEventbrite(metro, job.intent, config.eventbriteToken)
      : Promise.resolve(emptyAdapterResult("eventbrite", "No token")),
  ]);

  if (tmResult.status === "fulfilled") {
    adapterResults.push(tmResult.value);
    notes.push(...tmResult.value.notes);
  } else {
    notes.push(`Ticketmaster adapter error: ${tmResult.reason}`);
  }

  if (ebResult.status === "fulfilled") {
    adapterResults.push(ebResult.value);
    notes.push(...ebResult.value.notes);
  } else {
    notes.push(`Eventbrite adapter error: ${ebResult.reason}`);
  }

  let allEvents: EventResult[] = [];
  const eventsBySource = new Map<string, EventResult[]>();

  for (const result of adapterResults) {
    allEvents.push(...result.events);
    const existing = eventsBySource.get(result.source) || [];
    existing.push(...result.events);
    eventsBySource.set(result.source, existing);

    await recordSourceHealth(supabase, {
      source: result.source,
      metro_id: job.metro_id,
      request_count: result.requestCount,
      success_count: result.successCount,
      failure_count: result.failureCount,
      timeout_count: result.timeoutCount,
      event_count: result.events.length,
      avg_latency_ms: result.avgLatencyMs,
    });
  }

  console.log(
    `[worker] ${metro.display_name}: ${allEvents.length} raw events from ${adapterResults.length} sources`
  );

  const reviewResult = await enrichEventsWithReviews(
    allEvents,
    config,
    supabase
  );
  allEvents = reviewResult.events;

  for (const [source, events] of eventsBySource) {
    const enrichedForSource = allEvents.filter((e) => e.source === source);
    eventsBySource.set(source, enrichedForSource);
  }

  const snapshot = buildSnapshot(metro, job.intent, eventsBySource, notes);

  const isHighDensity = isHighDensityMetro(metro.city);
  const key = cacheKey(
    job.intent,
    metro.country_code,
    metro.latitude,
    metro.longitude,
    isHighDensity
  );

  const ttlHours = ttlForIntent(job.intent);
  const fetchedAt = new Date().toISOString();
  const expiresAt = new Date(
    Date.now() + ttlHours * 60 * 60 * 1000
  ).toISOString();

  const nightlifeCount = snapshot.mergedEvents.filter(
    (e) => e.eventType === "party / nightlife"
  ).length;
  const exclusiveCount = snapshot.mergedEvents.filter((e) => {
    const payload = JSON.parse(e.rawSourcePayload || "{}");
    return (
      e.eventType === "party / nightlife" &&
      (payload.discotech_url || payload.clubbable_url)
    );
  }).length;

  const reviewEligible = snapshot.mergedEvents.filter(
    (e) => e.eventType !== "party / nightlife"
  );
  const reviewCovered = reviewEligible.filter(
    (e) => sanitizeReviewRating(e.venueRating) !== null
  );
  const reviewCoveragePct =
    reviewEligible.length > 0
      ? reviewCovered.length / reviewEligible.length
      : 0;

  const bucket = {
    latitude:
      Math.round(metro.latitude / (isHighDensity ? 0.12 : 0.08)) *
      (isHighDensity ? 0.12 : 0.08),
    longitude:
      Math.round(metro.longitude / (isHighDensity ? 0.12 : 0.08)) *
      (isHighDensity ? 0.12 : 0.08),
  };

  await upsertSnapshot(supabase, {
    cache_key: key,
    intent: job.intent,
    quality: "full",
    country_code: metro.country_code,
    display_name: metro.display_name,
    city: metro.city,
    state: metro.state,
    postal_code: metro.postal_code ?? undefined,
    latitude: metro.latitude,
    longitude: metro.longitude,
    bucket_latitude: bucket.latitude,
    bucket_longitude: bucket.longitude,
    event_count: snapshot.mergedEvents.length,
    exclusive_count: exclusiveCount,
    nightlife_count: nightlifeCount,
    snapshot,
    fetched_at: fetchedAt,
    expires_at: expiresAt,
    worker_id: config.workerId,
    run_id: runId ?? undefined,
    review_coverage_pct: reviewCoveragePct,
    is_server_generated: true,
  });

  const uniqueVenues = new Set(
    snapshot.mergedEvents
      .map((e) => e.venueName)
      .filter(Boolean)
  ).size;

  const sportsCount = snapshot.mergedEvents.filter(
    (e) => e.eventType === "sports event"
  ).length;
  const concertCount = snapshot.mergedEvents.filter(
    (e) => e.eventType === "concert"
  ).length;
  const communityCount = snapshot.mergedEvents.filter(
    (e) =>
      e.eventType === "social / community event" ||
      e.eventType === "weekend activity"
  ).length;

  await recordCoverageMetrics(supabase, {
    metro_id: job.metro_id,
    intent: job.intent,
    total_events: snapshot.mergedEvents.length,
    unique_venues: uniqueVenues,
    review_eligible_count: reviewEligible.length,
    review_covered_count: reviewCovered.length,
    review_coverage_pct: reviewCoveragePct,
    nightlife_count: nightlifeCount,
    sports_count: sportsCount,
    concert_count: concertCount,
    community_count: communityCount,
    poisoned_review_count: 0,
    stale_reason:
      snapshot.mergedEvents.length === 0 ? "No events returned" : undefined,
    degraded_reason:
      reviewCoveragePct < 0.3 && reviewEligible.length >= 8
        ? `Low review coverage: ${(reviewCoveragePct * 100).toFixed(1)}%`
        : undefined,
    notes,
  });

  const durationMs = Date.now() - startTime;

  if (runId) {
    await updateRefreshRun(supabase, runId, {
      status: "completed",
      completed_at: new Date().toISOString(),
      duration_ms: durationMs,
      event_count: snapshot.mergedEvents.length,
      venue_count: uniqueVenues,
      review_hit_count: reviewResult.hitCount,
      review_miss_count: reviewResult.missCount,
      review_error_count: reviewResult.errorCount,
      source_results: adapterResults.map((r) => ({
        source: r.source,
        event_count: r.events.length,
        request_count: r.requestCount,
        success_count: r.successCount,
        failure_count: r.failureCount,
      })),
      notes,
    });
  }

  console.log(
    `[worker] ${metro.display_name}/${job.intent}: ` +
      `${snapshot.mergedEvents.length} events, ` +
      `${uniqueVenues} venues, ` +
      `review coverage ${(reviewCoveragePct * 100).toFixed(1)}%, ` +
      `${durationMs}ms`
  );
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

function ttlForIntent(intent: string): number {
  switch (intent) {
    case "biggest_tonight":
      return 48;
    case "last_minute_plans":
      return 24;
    case "exclusive_hot":
      return 72;
    case "nearby_and_worth_it":
      return 96;
    default:
      return 48;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

if (require.main === module) {
  startWorker().catch((err) => {
    console.error("[worker] Fatal error:", err);
    process.exit(1);
  });

  process.on("SIGINT", () => {
    console.log("[worker] SIGINT received, shutting down...");
    stopWorker();
  });

  process.on("SIGTERM", () => {
    console.log("[worker] SIGTERM received, shutting down...");
    stopWorker();
  });
}
