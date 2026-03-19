# SideQuest Backend Ingestion Architecture

## Overview

Backend-first event ingestion system. The iOS app is a **consumer** of prewarmed server snapshots. Local on-device scraping is retained only as a fallback when server data is missing or stale.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Supabase                        │
│  ┌──────────────┐  ┌───────────────────────┐    │
│  │ ingestion_   │  │ external_event_       │    │
│  │ metros       │  │ snapshots             │    │
│  ├──────────────┤  ├───────────────────────┤    │
│  │ refresh_jobs │  │ venue_review_cache    │    │
│  ├──────────────┤  ├───────────────────────┤    │
│  │ refresh_runs │  │ source_health         │    │
│  └──────────────┘  ├───────────────────────┤    │
│                    │ coverage_metrics      │    │
│                    └───────────────────────┘    │
└──────────┬──────────────────────┬───────────────┘
           │                      │
     ┌─────▼─────┐         ┌─────▼─────┐
     │  Worker    │         │  iOS App  │
     │  Service   │         │ (consumer)│
     │            │         │           │
     │ Ticketmaster        │ Read snapshots
     │ Eventbrite │         │ Fallback: local
     │ Google Reviews      │ scraping   │
     └───────────┘         └───────────┘
```

## Components

### 1. SQL Migrations (`backend/migrations/`)

Run `001_ingestion_tables.sql` against your Supabase project:

```bash
psql $DATABASE_URL < backend/migrations/001_ingestion_tables.sql
```

Tables created:
- `ingestion_metros` — Which metros to scrape, with tier and refresh intervals
- `refresh_jobs` — Job queue with claiming, heartbeats, retries, backoff
- `refresh_runs` — Execution history for observability
- `venue_review_cache` — Server-side Google review storage with poison protection
- `source_health` — Per-source success/failure/latency metrics
- `coverage_metrics` — Metro-level event and review coverage tracking

RPC functions:
- `claim_refresh_job()` — Atomic job claiming with `FOR UPDATE SKIP LOCKED`
- `heartbeat_refresh_job()` — Keep-alive for running jobs
- `complete_refresh_job()` / `fail_refresh_job()` — Job lifecycle
- `reclaim_stale_jobs()` — Recover jobs from dead workers
- `enqueue_scheduled_refreshes()` — Auto-enqueue based on metro intervals

### 2. Worker Service (`backend/worker/`)

Node/TypeScript process that:
1. Polls for pending jobs from `refresh_jobs`
2. Fetches events from Ticketmaster, Eventbrite (extensible)
3. Enriches with Google Maps HTML review scraping
4. Deduplicates and normalizes
5. Writes snapshot to `external_event_snapshots`
6. Records source health and coverage metrics

```bash
cd backend/worker
cp .env.example .env   # Fill in real values
npm install
npm run dev            # Development with hot reload
npm start              # Production
```

### 3. API Endpoints (`backend/hono.ts`)

- `GET /api/health` — Health check
- `POST /api/trigger-refresh` — Manually trigger refresh for a metro
- `POST /api/trigger-backfill` — Backfill all metros up to a tier
- `GET /api/ingestion/status` — Job queue and run statistics
- `GET /api/ingestion/source-health` — Per-source success rates and latency

### 4. iOS Changes

**What moved to backend:**
- Event fetching from Ticketmaster, Eventbrite, Google Events
- Google Maps HTML review scraping/enrichment
- Deduplication and normalization
- Snapshot assembly and storage
- Scheduling and refresh orchestration

**What stays in iOS:**
- `SupabaseEventFeedCacheService` — Reads server-generated snapshots (primary path)
- `ExternalLiveLocationDiscoveryService` — Local scraping (fallback only)
- `ExternalEventIngestionService` — Local adapter orchestration (fallback only)
- All feed display, filtering, sorting logic
- All UX behavior unchanged

**Flow change:**
```
BEFORE: iOS scrapes → dedupes → enriches → saves to Supabase → displays
AFTER:  iOS reads Supabase snapshot → displays (server already scraped/enriched)
        If no server data → fallback to local scraping (same as before)
```

## Environment Variables

### Worker (`backend/worker/.env`)

| Variable | Required | Description |
|----------|----------|-------------|
| `SUPABASE_URL` | Yes | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes | Service role key (not anon) |
| `WORKER_ID` | No | Worker identity for job claiming |
| `TICKETMASTER_API_KEY` | Yes | Ticketmaster Discovery API key |
| `EVENTBRITE_PRIVATE_TOKEN` | No | Eventbrite OAuth token |
| _(no API key needed)_ | — | Reviews use Google Maps HTML scraping |
| `APIFY_API_TOKEN` | No | Apify token for Google Events |
| `YELP_API_KEY` | No | Yelp Fusion API key |
| `POLL_INTERVAL_MS` | No | Job poll interval (default: 10000) |
| `MAX_CONCURRENT_JOBS` | No | Max parallel jobs (default: 2) |

### iOS (unchanged)

iOS continues to use `SUPABASE_URL` and `SUPABASE_ANON_KEY` for reading snapshots via `SupabaseEventFeedCacheService`.

## Metro Tiers & Scheduling

| Tier | Refresh Interval | Examples |
|------|-----------------|----------|
| 1 (top) | 60-90 min | LA, NYC, Miami, Chicago, Las Vegas, Austin, Nashville |
| 2 (mid) | 120-180 min | Dallas, Houston, Atlanta, SF, Seattle, Denver, Boston |
| 3 (long-tail) | 240-360 min | Orlando, Tampa, Minneapolis, Charlotte, Detroit |

## Reliability Features

- **Job queue with retries**: 3 retries with exponential backoff
- **Heartbeat monitoring**: Stale jobs reclaimed after 5 min no heartbeat
- **Poison data protection**: Boolean `true` ≠ 1.0 star rating
- **Review validation**: Ratings must be 1.0–5.0, counts must be positive integers
- **Per-source metrics**: Track success/failure/timeout/latency per source per metro
- **Coverage tracking**: Review hit rate, event counts by type, degradation reasons

## Adding New Event Sources

1. Create adapter in `backend/worker/adapters/new-source.ts`
2. Implement the same `AdapterResult` interface
3. Call it in `processJob()` in `ingestion-worker.ts`
4. Source health is recorded automatically

## Manual Operations

```bash
# Trigger refresh for a specific metro
curl -X POST http://localhost:3000/api/trigger-refresh \
  -H "Content-Type: application/json" \
  -d '{"metro_slug": "los-angeles", "intent": "nearby_and_worth_it"}'

# Backfill all tier 1+2 metros
curl -X POST http://localhost:3000/api/trigger-backfill \
  -H "Content-Type: application/json" \
  -d '{"tier": 2}'

# Check ingestion status
curl http://localhost:3000/api/ingestion/status

# Check source health
curl http://localhost:3000/api/ingestion/source-health
```
