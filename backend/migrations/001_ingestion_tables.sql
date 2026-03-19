-- ============================================================================
-- SideQuest Backend Ingestion Schema
-- Migration 001: Core ingestion tables for backend-first event discovery
-- ============================================================================

-- 1. Metro definitions: which metros we actively scrape
CREATE TABLE IF NOT EXISTS ingestion_metros (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug            TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    city            TEXT NOT NULL,
    state           TEXT NOT NULL,
    country_code    TEXT NOT NULL DEFAULT 'US',
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    postal_code     TEXT,
    tier            SMALLINT NOT NULL DEFAULT 2,  -- 1=top, 2=mid, 3=long-tail
    enabled         BOOLEAN NOT NULL DEFAULT TRUE,
    refresh_interval_minutes INTEGER NOT NULL DEFAULT 120,
    last_refresh_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ingestion_metros_tier ON ingestion_metros(tier) WHERE enabled = TRUE;
CREATE INDEX IF NOT EXISTS idx_ingestion_metros_slug ON ingestion_metros(slug);

-- 2. Refresh jobs: the queue that workers pull from
CREATE TABLE IF NOT EXISTS refresh_jobs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metro_id        UUID REFERENCES ingestion_metros(id) ON DELETE CASCADE,
    intent          TEXT NOT NULL DEFAULT 'nearby_and_worth_it',
    priority        SMALLINT NOT NULL DEFAULT 5,  -- 1=highest, 10=lowest
    status          TEXT NOT NULL DEFAULT 'pending',
    -- pending | claimed | running | completed | failed | dead
    claimed_by      TEXT,           -- worker ID
    claimed_at      TIMESTAMPTZ,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    failed_at       TIMESTAMPTZ,
    error_message   TEXT,
    retry_count     SMALLINT NOT NULL DEFAULT 0,
    max_retries     SMALLINT NOT NULL DEFAULT 3,
    heartbeat_at    TIMESTAMPTZ,
    locked_until    TIMESTAMPTZ,    -- exponential backoff lock
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_jobs_status ON refresh_jobs(status, priority, created_at);
CREATE INDEX IF NOT EXISTS idx_refresh_jobs_metro ON refresh_jobs(metro_id, status);
CREATE INDEX IF NOT EXISTS idx_refresh_jobs_claimed ON refresh_jobs(claimed_by, status) WHERE status = 'claimed' OR status = 'running';

-- 3. Refresh runs: execution history for observability
CREATE TABLE IF NOT EXISTS refresh_runs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id              UUID REFERENCES refresh_jobs(id) ON DELETE SET NULL,
    metro_id            UUID REFERENCES ingestion_metros(id) ON DELETE SET NULL,
    worker_id           TEXT NOT NULL,
    intent              TEXT NOT NULL,
    status              TEXT NOT NULL DEFAULT 'running',
    -- running | completed | failed | partial
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    duration_ms         INTEGER,
    event_count         INTEGER DEFAULT 0,
    venue_count         INTEGER DEFAULT 0,
    review_hit_count    INTEGER DEFAULT 0,
    review_miss_count   INTEGER DEFAULT 0,
    review_error_count  INTEGER DEFAULT 0,
    source_results      JSONB DEFAULT '[]'::jsonb,
    notes               TEXT[],
    error_message       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_runs_metro ON refresh_runs(metro_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_refresh_runs_worker ON refresh_runs(worker_id, started_at DESC);

-- 4. Venue review cache: server-side Google review storage
CREATE TABLE IF NOT EXISTS venue_review_cache (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_key           TEXT NOT NULL,  -- normalized venue name + location
    venue_name          TEXT NOT NULL,
    address_line1       TEXT,
    city                TEXT,
    state               TEXT,
    postal_code         TEXT,
    latitude            DOUBLE PRECISION,
    longitude           DOUBLE PRECISION,
    google_rating       DOUBLE PRECISION,
    google_review_count INTEGER,
    google_maps_url     TEXT,
    google_place_id     TEXT,
    yelp_rating         DOUBLE PRECISION,
    yelp_review_count   INTEGER,
    yelp_url            TEXT,
    review_source       TEXT NOT NULL DEFAULT 'google_places_api',
    is_poisoned         BOOLEAN NOT NULL DEFAULT FALSE,
    poison_reason       TEXT,
    fetched_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(venue_key)
);

CREATE INDEX IF NOT EXISTS idx_venue_review_cache_key ON venue_review_cache(venue_key);
CREATE INDEX IF NOT EXISTS idx_venue_review_cache_location ON venue_review_cache(city, state);
CREATE INDEX IF NOT EXISTS idx_venue_review_cache_expires ON venue_review_cache(expires_at);

-- 5. Source health: per-source success/failure metrics
CREATE TABLE IF NOT EXISTS source_health (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source          TEXT NOT NULL,
    metro_id        UUID REFERENCES ingestion_metros(id) ON DELETE CASCADE,
    window_start    TIMESTAMPTZ NOT NULL,
    window_end      TIMESTAMPTZ NOT NULL,
    request_count   INTEGER NOT NULL DEFAULT 0,
    success_count   INTEGER NOT NULL DEFAULT 0,
    failure_count   INTEGER NOT NULL DEFAULT 0,
    timeout_count   INTEGER NOT NULL DEFAULT 0,
    event_count     INTEGER NOT NULL DEFAULT 0,
    avg_latency_ms  INTEGER,
    p95_latency_ms  INTEGER,
    error_codes     JSONB DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(source, metro_id, window_start)
);

CREATE INDEX IF NOT EXISTS idx_source_health_source ON source_health(source, window_start DESC);
CREATE INDEX IF NOT EXISTS idx_source_health_metro ON source_health(metro_id, window_start DESC);

-- 6. Coverage metrics: metro-level coverage tracking
CREATE TABLE IF NOT EXISTS coverage_metrics (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metro_id                UUID REFERENCES ingestion_metros(id) ON DELETE CASCADE,
    intent                  TEXT NOT NULL,
    measured_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    total_events            INTEGER NOT NULL DEFAULT 0,
    unique_venues           INTEGER NOT NULL DEFAULT 0,
    review_eligible_count   INTEGER NOT NULL DEFAULT 0,
    review_covered_count    INTEGER NOT NULL DEFAULT 0,
    review_coverage_pct     DOUBLE PRECISION NOT NULL DEFAULT 0,
    nightlife_count         INTEGER NOT NULL DEFAULT 0,
    sports_count            INTEGER NOT NULL DEFAULT 0,
    concert_count           INTEGER NOT NULL DEFAULT 0,
    community_count         INTEGER NOT NULL DEFAULT 0,
    poisoned_review_count   INTEGER NOT NULL DEFAULT 0,
    stale_reason            TEXT,
    degraded_reason         TEXT,
    notes                   TEXT[],
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coverage_metrics_metro ON coverage_metrics(metro_id, measured_at DESC);

-- 7. Enhanced external_event_snapshots (add columns if not exist)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'external_event_snapshots' AND column_name = 'worker_id'
    ) THEN
        ALTER TABLE external_event_snapshots ADD COLUMN worker_id TEXT;
        ALTER TABLE external_event_snapshots ADD COLUMN run_id UUID;
        ALTER TABLE external_event_snapshots ADD COLUMN review_coverage_pct DOUBLE PRECISION;
        ALTER TABLE external_event_snapshots ADD COLUMN source_breakdown JSONB;
        ALTER TABLE external_event_snapshots ADD COLUMN is_server_generated BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- ============================================================================
-- RPC Functions
-- ============================================================================

-- Claim next available job (atomic, prevents double-claim)
CREATE OR REPLACE FUNCTION claim_refresh_job(
    p_worker_id TEXT,
    p_max_claims INTEGER DEFAULT 1
)
RETURNS SETOF refresh_jobs
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH claimable AS (
        SELECT id
        FROM refresh_jobs
        WHERE status = 'pending'
          AND (locked_until IS NULL OR locked_until < NOW())
        ORDER BY priority ASC, created_at ASC
        LIMIT p_max_claims
        FOR UPDATE SKIP LOCKED
    )
    UPDATE refresh_jobs j
    SET status = 'claimed',
        claimed_by = p_worker_id,
        claimed_at = NOW(),
        heartbeat_at = NOW(),
        updated_at = NOW()
    FROM claimable c
    WHERE j.id = c.id
    RETURNING j.*;
END;
$$;

-- Heartbeat: keep job alive
CREATE OR REPLACE FUNCTION heartbeat_refresh_job(
    p_job_id UUID,
    p_worker_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE refresh_jobs
    SET heartbeat_at = NOW(),
        updated_at = NOW()
    WHERE id = p_job_id
      AND claimed_by = p_worker_id
      AND status IN ('claimed', 'running');
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count > 0;
END;
$$;

-- Complete job
CREATE OR REPLACE FUNCTION complete_refresh_job(
    p_job_id UUID,
    p_worker_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE refresh_jobs
    SET status = 'completed',
        completed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_job_id
      AND claimed_by = p_worker_id
      AND status IN ('claimed', 'running');
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count > 0;
END;
$$;

-- Fail job with backoff
CREATE OR REPLACE FUNCTION fail_refresh_job(
    p_job_id UUID,
    p_worker_id TEXT,
    p_error TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    current_retry SMALLINT;
    current_max SMALLINT;
    updated_count INTEGER;
BEGIN
    SELECT retry_count, max_retries INTO current_retry, current_max
    FROM refresh_jobs WHERE id = p_job_id;

    IF current_retry + 1 >= current_max THEN
        UPDATE refresh_jobs
        SET status = 'dead',
            failed_at = NOW(),
            error_message = p_error,
            retry_count = current_retry + 1,
            updated_at = NOW()
        WHERE id = p_job_id AND claimed_by = p_worker_id;
    ELSE
        UPDATE refresh_jobs
        SET status = 'pending',
            failed_at = NOW(),
            error_message = p_error,
            retry_count = current_retry + 1,
            claimed_by = NULL,
            claimed_at = NULL,
            locked_until = NOW() + (POWER(2, current_retry + 1) || ' minutes')::INTERVAL,
            updated_at = NOW()
        WHERE id = p_job_id AND claimed_by = p_worker_id;
    END IF;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count > 0;
END;
$$;

-- Reclaim stale jobs (heartbeat timeout)
CREATE OR REPLACE FUNCTION reclaim_stale_jobs(
    p_heartbeat_timeout_minutes INTEGER DEFAULT 5
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    reclaimed_count INTEGER;
BEGIN
    UPDATE refresh_jobs
    SET status = 'pending',
        claimed_by = NULL,
        claimed_at = NULL,
        heartbeat_at = NULL,
        updated_at = NOW()
    WHERE status IN ('claimed', 'running')
      AND heartbeat_at < NOW() - (p_heartbeat_timeout_minutes || ' minutes')::INTERVAL;
    GET DIAGNOSTICS reclaimed_count = ROW_COUNT;
    RETURN reclaimed_count;
END;
$$;

-- Enqueue scheduled refreshes for all enabled metros
CREATE OR REPLACE FUNCTION enqueue_scheduled_refreshes()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    enqueued_count INTEGER := 0;
    metro RECORD;
BEGIN
    FOR metro IN
        SELECT m.id, m.slug, m.refresh_interval_minutes, m.last_refresh_at, m.tier
        FROM ingestion_metros m
        WHERE m.enabled = TRUE
          AND (
              m.last_refresh_at IS NULL
              OR m.last_refresh_at < NOW() - (m.refresh_interval_minutes || ' minutes')::INTERVAL
          )
          AND NOT EXISTS (
              SELECT 1 FROM refresh_jobs j
              WHERE j.metro_id = m.id
                AND j.status IN ('pending', 'claimed', 'running')
          )
        ORDER BY m.tier ASC, m.last_refresh_at ASC NULLS FIRST
    LOOP
        INSERT INTO refresh_jobs (metro_id, intent, priority)
        VALUES
            (metro.id, 'nearby_and_worth_it', metro.tier),
            (metro.id, 'biggest_tonight', metro.tier + 1),
            (metro.id, 'exclusive_hot', metro.tier + 1),
            (metro.id, 'last_minute_plans', metro.tier + 2);

        UPDATE ingestion_metros SET last_refresh_at = NOW(), updated_at = NOW()
        WHERE id = metro.id;

        enqueued_count := enqueued_count + 4;
    END LOOP;

    RETURN enqueued_count;
END;
$$;

-- ============================================================================
-- Seed data: top US metros
-- ============================================================================
INSERT INTO ingestion_metros (slug, display_name, city, state, latitude, longitude, postal_code, tier, refresh_interval_minutes)
VALUES
    ('los-angeles',     'Los Angeles, CA',      'Los Angeles',      'CA', 34.0522, -118.2437, '90012', 1, 60),
    ('west-hollywood',  'West Hollywood, CA',   'West Hollywood',   'CA', 34.0901, -118.3852, '90069', 1, 60),
    ('new-york',        'New York, NY',         'New York',         'NY', 40.7128, -74.0060,  '10001', 1, 60),
    ('miami-beach',     'Miami Beach, FL',      'Miami Beach',      'FL', 25.7826, -80.1341,  '33139', 1, 60),
    ('chicago',         'Chicago, IL',          'Chicago',          'IL', 41.8781, -87.6298,  '60601', 1, 90),
    ('las-vegas',       'Las Vegas, NV',        'Las Vegas',        'NV', 36.1699, -115.1398, '89101', 1, 90),
    ('austin',          'Austin, TX',           'Austin',           'TX', 30.2672, -97.7431,  '78701', 1, 90),
    ('nashville',       'Nashville, TN',        'Nashville',        'TN', 36.1627, -86.7816,  '37203', 1, 90),
    ('dallas',          'Dallas, TX',           'Dallas',           'TX', 32.7767, -96.7970,  '75201', 2, 120),
    ('houston',         'Houston, TX',          'Houston',          'TX', 29.7604, -95.3698,  '77002', 2, 120),
    ('atlanta',         'Atlanta, GA',          'Atlanta',          'GA', 33.7490, -84.3880,  '30303', 2, 120),
    ('san-francisco',   'San Francisco, CA',    'San Francisco',    'CA', 37.7749, -122.4194, '94102', 2, 120),
    ('seattle',         'Seattle, WA',          'Seattle',          'WA', 47.6062, -122.3321, '98101', 2, 120),
    ('denver',          'Denver, CO',           'Denver',           'CO', 39.7392, -104.9903, '80202', 2, 120),
    ('phoenix',         'Phoenix, AZ',          'Phoenix',          'AZ', 33.4484, -112.0740, '85004', 2, 120),
    ('boston',           'Boston, MA',           'Boston',           'MA', 42.3601, -71.0589,  '02101', 2, 120),
    ('philadelphia',    'Philadelphia, PA',     'Philadelphia',     'PA', 39.9526, -75.1652,  '19102', 2, 180),
    ('san-diego',       'San Diego, CA',        'San Diego',        'CA', 32.7157, -117.1611, '92101', 2, 180),
    ('portland',        'Portland, OR',         'Portland',         'OR', 45.5152, -122.6784, '97201', 2, 180),
    ('washington-dc',   'Washington, DC',       'Washington',       'DC', 38.9072, -77.0369,  '20001', 2, 120),
    ('new-orleans',     'New Orleans, LA',      'New Orleans',      'LA', 29.9511, -90.0715,  '70112', 2, 180),
    ('orlando',         'Orlando, FL',          'Orlando',          'FL', 28.5383, -81.3792,  '32801', 3, 240),
    ('tampa',           'Tampa, FL',            'Tampa',            'FL', 27.9506, -82.4572,  '33602', 3, 240),
    ('minneapolis',     'Minneapolis, MN',      'Minneapolis',      'MN', 44.9778, -93.2650,  '55401', 3, 240),
    ('charlotte',       'Charlotte, NC',        'Charlotte',        'NC', 35.2271, -80.8431,  '28202', 3, 240),
    ('raleigh',         'Raleigh, NC',          'Raleigh',          'NC', 35.7796, -78.6382,  '27601', 3, 240),
    ('detroit',         'Detroit, MI',          'Detroit',          'MI', 42.3314, -83.0458,  '48201', 3, 240),
    ('salt-lake-city',  'Salt Lake City, UT',   'Salt Lake City',   'UT', 40.7608, -111.8910, '84101', 3, 240),
    ('kansas-city',     'Kansas City, MO',      'Kansas City',      'MO', 39.0997, -94.5786,  '64105', 3, 240),
    ('sacramento',      'Sacramento, CA',       'Sacramento',       'CA', 38.5816, -121.4944, '95814', 3, 240),
    ('columbus',        'Columbus, OH',         'Columbus',         'OH', 39.9612, -82.9988,  '43215', 3, 360),
    ('pittsburgh',      'Pittsburgh, PA',       'Pittsburgh',       'PA', 40.4406, -79.9959,  '15222', 3, 360),
    ('cleveland',       'Cleveland, OH',        'Cleveland',        'OH', 41.4993, -81.6944,  '44113', 3, 360),
    ('cincinnati',      'Cincinnati, OH',       'Cincinnati',       'OH', 39.1031, -84.5120,  '45202', 3, 360),
    ('indianapolis',    'Indianapolis, IN',     'Indianapolis',     'IN', 39.7684, -86.1581,  '46204', 3, 360),
    ('milwaukee',       'Milwaukee, WI',        'Milwaukee',        'WI', 43.0389, -87.9065,  '53202', 3, 360),
    ('st-louis',        'St. Louis, MO',        'St. Louis',        'MO', 38.6270, -90.1994,  '63101', 3, 360),
    ('baltimore',       'Baltimore, MD',        'Baltimore',        'MD', 39.2904, -76.6122,  '21201', 3, 360)
ON CONFLICT (slug) DO NOTHING;
