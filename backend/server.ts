import { serve } from "@hono/node-server";
import app from "./hono";
import { startSimpleWorker, stopSimpleWorker } from "./worker/simple-worker";

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
    await startSimpleWorker();
  } catch (error) {
    console.error("[server] Worker exited fatally:", error);
    process.exit(1);
  }
}

void bootWorker();

function shutdown(signal: string): void {
  console.log(`[server] ${signal} received, shutting down...`);
  stopSimpleWorker();
  server.close(() => {
    process.exit(0);
  });
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
