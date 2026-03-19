import { createClient, SupabaseClient } from "@supabase/supabase-js";
import type { WorkerConfig } from "./config";

let client: SupabaseClient | null = null;

export function getSupabase(config: WorkerConfig): SupabaseClient {
  if (!client) {
    client = createClient(config.supabaseUrl, config.supabaseServiceKey, {
      auth: { persistSession: false },
    });
  }
  return client;
}

export interface Metro {
  id: string;
  slug: string;
  display_name: string;
  city: string;
  state: string;
  country_code: string;
  latitude: number;
  longitude: number;
  postal_code: string | null;
  tier: number;
  refresh_interval_minutes: number;
}

export interface RefreshJob {
  id: string;
  metro_id: string;
  intent: string;
  priority: number;
  status: string;
  claimed_by: string | null;
  retry_count: number;
  max_retries: number;
}

export async function claimJob(
  supabase: SupabaseClient,
  workerId: string
): Promise<RefreshJob | null> {
  const { data, error } = await supabase.rpc("claim_refresh_job", {
    p_worker_id: workerId,
    p_max_claims: 1,
  });
  if (error) {
    console.error("[job-queue] claim error:", error.message);
    return null;
  }
  return data?.[0] ?? null;
}

export async function heartbeatJob(
  supabase: SupabaseClient,
  jobId: string,
  workerId: string
): Promise<boolean> {
  const { data, error } = await supabase.rpc("heartbeat_refresh_job", {
    p_job_id: jobId,
    p_worker_id: workerId,
  });
  if (error) {
    console.error("[job-queue] heartbeat error:", error.message);
    return false;
  }
  return data === true;
}

export async function completeJob(
  supabase: SupabaseClient,
  jobId: string,
  workerId: string
): Promise<boolean> {
  const { data, error } = await supabase.rpc("complete_refresh_job", {
    p_job_id: jobId,
    p_worker_id: workerId,
  });
  if (error) {
    console.error("[job-queue] complete error:", error.message);
    return false;
  }
  return data === true;
}

export async function failJob(
  supabase: SupabaseClient,
  jobId: string,
  workerId: string,
  errorMessage?: string
): Promise<boolean> {
  const { data, error } = await supabase.rpc("fail_refresh_job", {
    p_job_id: jobId,
    p_worker_id: workerId,
    p_error: errorMessage || null,
  });
  if (error) {
    console.error("[job-queue] fail error:", error.message);
    return false;
  }
  return data === true;
}

export async function reclaimStaleJobs(
  supabase: SupabaseClient,
  timeoutMinutes: number
): Promise<number> {
  const { data, error } = await supabase.rpc("reclaim_stale_jobs", {
    p_heartbeat_timeout_minutes: timeoutMinutes,
  });
  if (error) {
    console.error("[job-queue] reclaim error:", error.message);
    return 0;
  }
  return data ?? 0;
}

export async function enqueueScheduledRefreshes(
  supabase: SupabaseClient
): Promise<number> {
  const { data, error } = await supabase.rpc("enqueue_scheduled_refreshes");
  if (error) {
    console.error("[scheduler] enqueue error:", error.message);
    return 0;
  }
  return data ?? 0;
}

export async function getMetro(
  supabase: SupabaseClient,
  metroId: string
): Promise<Metro | null> {
  const { data, error } = await supabase
    .from("ingestion_metros")
    .select("*")
    .eq("id", metroId)
    .single();
  if (error) return null;
  return data;
}

export async function insertRefreshRun(
  supabase: SupabaseClient,
  run: {
    job_id: string;
    metro_id: string;
    worker_id: string;
    intent: string;
  }
): Promise<string | null> {
  const { data, error } = await supabase
    .from("refresh_runs")
    .insert(run)
    .select("id")
    .single();
  if (error) {
    console.error("[run] insert error:", error.message);
    return null;
  }
  return data?.id ?? null;
}

export async function updateRefreshRun(
  supabase: SupabaseClient,
  runId: string,
  updates: Record<string, unknown>
): Promise<void> {
  await supabase.from("refresh_runs").update(updates).eq("id", runId);
}

export async function upsertVenueReview(
  supabase: SupabaseClient,
  review: {
    venue_key: string;
    venue_name: string;
    city?: string;
    state?: string;
    postal_code?: string;
    latitude?: number;
    longitude?: number;
    google_rating?: number;
    google_review_count?: number;
    google_maps_url?: string;
    google_place_id?: string;
    review_source: string;
    is_poisoned: boolean;
    poison_reason?: string;
  }
): Promise<void> {
  await supabase.from("venue_review_cache").upsert(
    {
      ...review,
      fetched_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "venue_key" }
  );
}

export async function getCachedVenueReviews(
  supabase: SupabaseClient,
  venueKeys: string[]
): Promise<Map<string, { rating: number; reviewCount: number; url?: string }>> {
  if (venueKeys.length === 0) return new Map();

  const { data, error } = await supabase
    .from("venue_review_cache")
    .select("venue_key, google_rating, google_review_count, google_maps_url, is_poisoned, expires_at")
    .in("venue_key", venueKeys)
    .eq("is_poisoned", false)
    .gte("expires_at", new Date().toISOString());

  if (error || !data) return new Map();

  const map = new Map<string, { rating: number; reviewCount: number; url?: string }>();
  for (const row of data) {
    if (row.google_rating && row.google_rating >= 1 && row.google_rating <= 5) {
      map.set(row.venue_key, {
        rating: row.google_rating,
        reviewCount: row.google_review_count ?? 0,
        url: row.google_maps_url ?? undefined,
      });
    }
  }
  return map;
}

export async function recordSourceHealth(
  supabase: SupabaseClient,
  entry: {
    source: string;
    metro_id: string;
    request_count: number;
    success_count: number;
    failure_count: number;
    timeout_count: number;
    event_count: number;
    avg_latency_ms: number;
  }
): Promise<void> {
  const now = new Date();
  const windowStart = new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate(),
    now.getHours()
  );
  const windowEnd = new Date(windowStart.getTime() + 60 * 60 * 1000);

  await supabase.from("source_health").upsert(
    {
      ...entry,
      window_start: windowStart.toISOString(),
      window_end: windowEnd.toISOString(),
    },
    { onConflict: "source,metro_id,window_start" }
  );
}

export async function recordCoverageMetrics(
  supabase: SupabaseClient,
  metrics: {
    metro_id: string;
    intent: string;
    total_events: number;
    unique_venues: number;
    review_eligible_count: number;
    review_covered_count: number;
    review_coverage_pct: number;
    nightlife_count: number;
    sports_count: number;
    concert_count: number;
    community_count: number;
    poisoned_review_count: number;
    stale_reason?: string;
    degraded_reason?: string;
    notes?: string[];
  }
): Promise<void> {
  await supabase.from("coverage_metrics").insert({
    ...metrics,
    measured_at: new Date().toISOString(),
  });
}

export async function upsertSnapshot(
  supabase: SupabaseClient,
  params: {
    cache_key: string;
    intent: string;
    quality: string;
    country_code: string;
    display_name: string;
    city?: string;
    state?: string;
    postal_code?: string;
    latitude?: number;
    longitude?: number;
    bucket_latitude?: number;
    bucket_longitude?: number;
    event_count: number;
    exclusive_count: number;
    nightlife_count: number;
    snapshot: unknown;
    fetched_at: string;
    expires_at: string;
    worker_id?: string;
    run_id?: string;
    review_coverage_pct?: number;
    is_server_generated: boolean;
  }
): Promise<void> {
  const { error } = await supabase.rpc("upsert_external_event_snapshot", {
    p_cache_key: params.cache_key,
    p_intent: params.intent,
    p_quality: params.quality,
    p_country_code: params.country_code,
    p_display_name: params.display_name,
    p_city: params.city,
    p_state: params.state,
    p_postal_code: params.postal_code,
    p_latitude: params.latitude,
    p_longitude: params.longitude,
    p_bucket_latitude: params.bucket_latitude,
    p_bucket_longitude: params.bucket_longitude,
    p_event_count: params.event_count,
    p_exclusive_count: params.exclusive_count,
    p_nightlife_count: params.nightlife_count,
    p_snapshot: params.snapshot,
    p_fetched_at: params.fetched_at,
    p_expires_at: params.expires_at,
  });

  if (error) {
    console.error("[snapshot] upsert error:", error.message);
  }
}
