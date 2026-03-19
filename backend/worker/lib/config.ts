export interface WorkerConfig {
  supabaseUrl: string;
  supabaseServiceKey: string;
  workerId: string;
  ticketmasterApiKey?: string;
  eventbriteToken?: string;
  googlePlacesApiKey?: string;
  apifyApiToken?: string;
  yelpApiKey?: string;
  pollIntervalMs: number;
  heartbeatIntervalMs: number;
  maxConcurrentJobs: number;
  heartbeatTimeoutMinutes: number;
}

export function loadConfig(): WorkerConfig {
  const env = process.env;
  const supabaseUrl = env.SUPABASE_URL;
  const supabaseServiceKey = env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
  }

  return {
    supabaseUrl,
    supabaseServiceKey,
    workerId: env.WORKER_ID || `worker-${process.pid}-${Date.now()}`,
    ticketmasterApiKey: env.TICKETMASTER_API_KEY,
    eventbriteToken: env.EVENTBRITE_PRIVATE_TOKEN,
    googlePlacesApiKey: env.GOOGLE_PLACES_API_KEY,
    apifyApiToken: env.APIFY_API_TOKEN,
    yelpApiKey: env.YELP_API_KEY,
    pollIntervalMs: parseInt(env.POLL_INTERVAL_MS || "10000", 10),
    heartbeatIntervalMs: parseInt(env.HEARTBEAT_INTERVAL_MS || "30000", 10),
    maxConcurrentJobs: parseInt(env.MAX_CONCURRENT_JOBS || "2", 10),
    heartbeatTimeoutMinutes: parseInt(env.HEARTBEAT_TIMEOUT_MINUTES || "5", 10),
  };
}
