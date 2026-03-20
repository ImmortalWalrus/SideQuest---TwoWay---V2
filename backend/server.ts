import { serve } from "@hono/node-server";
import app from "./hono";
import { startWorker, stopWorker } from "./worker/ingestion-worker";

const port = parseInt(process.env.PORT || "8080", 10);
const apiOnly = process.argv.includes("--api-only");

const server = serve({
  fetch: app.fetch,
  port,
});

console.log(`[server] Listening on 0.0.0.0:${port}`);

let workerStarted = false;

async function bootWorker(): Promise<void> {
  if (apiOnly || workerStarted) return;
  workerStarted = true;
  try {
    await startWorker();
  } catch (error) {
    console.error("[server] Worker exited fatally:", error);
    process.exit(1);
  }
}

void bootWorker();

function shutdown(signal: string): void {
  console.log(`[server] ${signal} received, shutting down...`);
  stopWorker();
  server.close(() => {
    process.exit(0);
  });
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
