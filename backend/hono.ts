import { Hono } from "hono";
import { cors } from "hono/cors";
import { triggerMetroRefresh, getSimpleWorkerStatus } from "./worker/simple-worker";

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

  try {
    const result = await triggerMetroRefresh(metroSlug, intent);
    return c.json({ status: "completed", result });
  } catch (err) {
    return c.json({ error: String(err) }, 500);
  }
});

app.post("/api/trigger-backfill", async (c) => {
  return c.json({
    status: "disabled",
    message: "Backfill endpoint is not implemented in simple-worker mode. Use /api/trigger-refresh per metro.",
  });
});

app.get("/api/ingestion/status", async (c) => {
  return c.json(getSimpleWorkerStatus());
});

app.get("/api/ingestion/source-health", async (c) => {
  return c.json({
    status: "disabled",
    message: "Per-source health metrics require the optional ingestion tables migration.",
  });
});

export default app;
