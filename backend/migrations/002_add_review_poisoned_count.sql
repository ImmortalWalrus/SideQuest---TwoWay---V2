-- Migration 002: Add missing columns to refresh_runs and improve venue_review_cache

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'refresh_runs' AND column_name = 'review_poisoned_count'
    ) THEN
        ALTER TABLE refresh_runs ADD COLUMN review_poisoned_count INTEGER DEFAULT 0;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'refresh_runs' AND column_name = 'nightlife_venue_count'
    ) THEN
        ALTER TABLE refresh_runs ADD COLUMN nightlife_venue_count INTEGER DEFAULT 0;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_venue_review_cache_poisoned
    ON venue_review_cache(is_poisoned) WHERE is_poisoned = TRUE;

CREATE INDEX IF NOT EXISTS idx_refresh_runs_status
    ON refresh_runs(status, started_at DESC);
