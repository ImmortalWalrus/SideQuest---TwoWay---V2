import { Hono } from "hono";
import { cors } from "hono/cors";

const app = new Hono();

app.use("*", cors());

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

  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseKey) {
    return c.json({ error: "Supabase not configured" }, 500);
  }

  try {
    const metroResponse = await fetch(
      `${supabaseUrl}/rest/v1/ingestion_metros?slug=eq.${metroSlug}&select=id&limit=1`,
      {
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
        },
      }
    );
    const metros = await metroResponse.json();
    if (!Array.isArray(metros) || metros.length === 0) {
      return c.json({ error: "Metro not found" }, 404);
    }

    const metroId = metros[0].id;

    const jobResponse = await fetch(
      `${supabaseUrl}/rest/v1/refresh_jobs`,
      {
        method: "POST",
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify({
          metro_id: metroId,
          intent,
          priority: 1,
        }),
      }
    );

    const job = await jobResponse.json();
    return c.json({ status: "enqueued", job });
  } catch (err) {
    return c.json({ error: String(err) }, 500);
  }
});

app.post("/api/trigger-backfill", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const tier = body.tier ?? 1;

  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseKey) {
    return c.json({ error: "Supabase not configured" }, 500);
  }

  try {
    const metroResponse = await fetch(
      `${supabaseUrl}/rest/v1/ingestion_metros?enabled=eq.true&tier=lte.${tier}&select=id,slug&order=tier.asc`,
      {
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
        },
      }
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

    const jobs = [];
    for (const metro of metros) {
      for (const intent of intents) {
        jobs.push({
          metro_id: metro.id,
          intent,
          priority: 2,
        });
      }
    }

    if (jobs.length > 0) {
      await fetch(`${supabaseUrl}/rest/v1/refresh_jobs`, {
        method: "POST",
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(jobs),
      });
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
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseKey) {
    return c.json({ error: "Supabase not configured" }, 500);
  }

  const headers = {
    apikey: supabaseKey,
    Authorization: `Bearer ${supabaseKey}`,
  };

  try {
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
            recentRuns.reduce((sum: number, r: any) => sum + (r.duration_ms || 0), 0) /
              recentRuns.length
          )
        : 0;
    const totalEvents = recentRuns.reduce(
      (sum: number, r: any) => sum + (r.event_count || 0),
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
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseKey) {
    return c.json({ error: "Supabase not configured" }, 500);
  }

  try {
    const response = await fetch(
      `${supabaseUrl}/rest/v1/source_health?select=source,request_count,success_count,failure_count,timeout_count,event_count,avg_latency_ms&order=window_start.desc&limit=100`,
      {
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
        },
      }
    );
    const data = await response.json();

    const bySource: Record<string, any> = {};
    if (Array.isArray(data)) {
      for (const row of data) {
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
        const s = bySource[row.source];
        s.total_requests += row.request_count || 0;
        s.total_successes += row.success_count || 0;
        s.total_failures += row.failure_count || 0;
        s.total_timeouts += row.timeout_count || 0;
        s.total_events += row.event_count || 0;
        s.avg_latency_ms += row.avg_latency_ms || 0;
        s.windows++;
      }

      for (const source of Object.keys(bySource)) {
        const s = bySource[source];
        s.success_rate =
          s.total_requests > 0
            ? ((s.total_successes / s.total_requests) * 100).toFixed(1) + "%"
            : "N/A";
        s.avg_latency_ms =
          s.windows > 0 ? Math.round(s.avg_latency_ms / s.windows) : 0;
      }
    }

    return c.json({ sources: bySource });
  } catch (err) {
    return c.json({ error: String(err) }, 500);
  }
});

export default app;
