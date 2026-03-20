import { Hono } from "hono";
import { cors } from "hono/cors";

const app = new Hono();

app.use("*", cors());

function supabaseEnv() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey =
    process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseKey) {
    throw new Error("Supabase not configured");
  }

  return {
    supabaseUrl,
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      "Content-Type": "application/json",
    },
  };
}

app.get("/", (c) => {
  return c.json({ status: "ok", message: "SideQuest Ingestion API" });
});

app.get("/health", (c) => {
  return c.json({ status: "ok", timestamp: new Date().toISOString() });
});

app.post("/api/trigger-refresh", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const metroSlug = body.metro_slug;
  const intent = body.intent || "nearby_and_worth_it";

  if (!metroSlug) {
    return c.json({ error: "metro_slug is required" }, 400);
  }

  try {
    const { supabaseUrl, headers } = supabaseEnv();
    const metroResponse = await fetch(
      `${supabaseUrl}/rest/v1/ingestion_metros?slug=eq.${encodeURIComponent(
        metroSlug
      )}&enabled=eq.true&select=id,slug,display_name&limit=1`,
      { headers }
    );

    const metros = await metroResponse.json();
    if (!Array.isArray(metros) || metros.length === 0) {
      return c.json({ error: "Metro not found" }, 404);
    }

    const metro = metros[0];
    const jobResponse = await fetch(`${supabaseUrl}/rest/v1/refresh_jobs`, {
      method: "POST",
      headers: {
        ...headers,
        Prefer: "return=representation",
      },
      body: JSON.stringify({
        metro_id: metro.id,
        intent,
        priority: 1,
      }),
    });

    if (!jobResponse.ok) {
      return c.json(
        { error: `Failed to enqueue refresh (${jobResponse.status})` },
        500
      );
    }

    const job = await jobResponse.json();
    return c.json({ status: "enqueued", metro, job });
  } catch (err) {
    return c.json({ error: String(err) }, 500);
  }
});

app.post("/api/trigger-backfill", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const tier = Number(body.tier ?? 1);

  try {
    const { supabaseUrl, headers } = supabaseEnv();
    const metroResponse = await fetch(
      `${supabaseUrl}/rest/v1/ingestion_metros?enabled=eq.true&tier=lte.${tier}&select=id,slug&order=tier.asc`,
      { headers }
    );
    const metros = await metroResponse.json();
    if (!Array.isArray(metros)) {
      return c.json({ error: "Failed to fetch metros" }, 500);
    }

    const intents = [
      "nearby_and_worth_it",
      "biggest_tonight",
      "exclusive_hot",
      "last_minute_plans",
    ];

    const jobs = metros.flatMap((metro: { id: string }) =>
      intents.map((intent) => ({
        metro_id: metro.id,
        intent,
        priority: 2,
      }))
    );

    if (jobs.length > 0) {
      const response = await fetch(`${supabaseUrl}/rest/v1/refresh_jobs`, {
        method: "POST",
        headers,
        body: JSON.stringify(jobs),
      });
      if (!response.ok) {
        return c.json(
          { error: `Failed to enqueue backfill (${response.status})` },
          500
        );
      }
    }

    return c.json({
      status: "backfill_enqueued",
      metro_count: metros.length,
      job_count: jobs.length,
    });
  } catch (err) {
    return c.json({ error: String(err) }, 500);
  }
});

app.get("/api/ingestion/status", async (c) => {
  try {
    const { supabaseUrl, headers } = supabaseEnv();

    const [jobsRes, runsRes, metrosRes] = await Promise.all([
      fetch(
        `${supabaseUrl}/rest/v1/refresh_jobs?select=status&order=created_at.desc&limit=200`,
        { headers }
      ),
      fetch(
        `${supabaseUrl}/rest/v1/refresh_runs?select=status,duration_ms,event_count,review_hit_count,review_miss_count&order=started_at.desc&limit=50`,
        { headers }
      ),
      fetch(
        `${supabaseUrl}/rest/v1/ingestion_metros?select=slug,tier,last_refresh_at,enabled&enabled=eq.true&order=tier.asc`,
        { headers }
      ),
    ]);

    const jobs = await jobsRes.json();
    const runs = await runsRes.json();
    const metros = await metrosRes.json();

    const jobsByStatus: Record<string, number> = {};
    if (Array.isArray(jobs)) {
      for (const job of jobs) {
        jobsByStatus[job.status] = (jobsByStatus[job.status] || 0) + 1;
      }
    }

    const recentRuns = Array.isArray(runs) ? runs.slice(0, 20) : [];
    const avgDuration =
      recentRuns.length > 0
        ? Math.round(
            recentRuns.reduce(
              (sum: number, run: any) => sum + (run.duration_ms || 0),
              0
            ) / recentRuns.length
          )
        : 0;
    const totalEvents = recentRuns.reduce(
      (sum: number, run: any) => sum + (run.event_count || 0),
      0
    );

    return c.json({
      jobs: jobsByStatus,
      recent_runs: {
        count: recentRuns.length,
        avg_duration_ms: avgDuration,
        total_events: totalEvents,
      },
      metros: Array.isArray(metros) ? metros.length : 0,
    });
  } catch (err) {
    return c.json({ error: String(err) }, 500);
  }
});

app.get("/api/ingestion/source-health", async (c) => {
  try {
    const { supabaseUrl, headers } = supabaseEnv();
    const response = await fetch(
      `${supabaseUrl}/rest/v1/source_health?select=source,request_count,success_count,failure_count,timeout_count,event_count,avg_latency_ms&order=window_start.desc&limit=100`,
      { headers }
    );

    if (!response.ok) {
      return c.json(
        { error: `Failed to load source health (${response.status})` },
        500
      );
    }

    const rows = await response.json();
    const bySource: Record<string, any> = {};

    if (Array.isArray(rows)) {
      for (const row of rows) {
        if (!bySource[row.source]) {
          bySource[row.source] = {
            total_requests: 0,
            total_successes: 0,
            total_failures: 0,
            total_timeouts: 0,
            total_events: 0,
            avg_latency_ms: 0,
            windows: 0,
          };
        }

        const source = bySource[row.source];
        source.total_requests += row.request_count || 0;
        source.total_successes += row.success_count || 0;
        source.total_failures += row.failure_count || 0;
        source.total_timeouts += row.timeout_count || 0;
        source.total_events += row.event_count || 0;
        source.avg_latency_ms += row.avg_latency_ms || 0;
        source.windows++;
      }

      for (const sourceName of Object.keys(bySource)) {
        const source = bySource[sourceName];
        source.success_rate =
          source.total_requests > 0
            ? ((source.total_successes / source.total_requests) * 100).toFixed(
                1
              ) + "%"
            : "N/A";
        source.avg_latency_ms =
          source.windows > 0
            ? Math.round(source.avg_latency_ms / source.windows)
            : 0;
      }
    }

    return c.json({ sources: bySource });
  } catch (err) {
    return c.json({ error: String(err) }, 500);
  }
});

export default app;
