CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS customers (
  id BIGSERIAL PRIMARY KEY,
  external_customer_id TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  full_name TEXT NOT NULL,
  tier TEXT NOT NULL DEFAULT 'STANDARD' CHECK (tier IN ('STANDARD', 'PREMIUM', 'VIP')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
  id BIGSERIAL PRIMARY KEY,
  customer_id TEXT NOT NULL,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  status TEXT NOT NULL CHECK (status IN ('NEW', 'PAID', 'SHIPPED', 'CANCELLED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS benchmark_runs (
  run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  approach TEXT NOT NULL CHECK (approach IN ('wal2json', 'debezium', 'drasi')),
  stage TEXT NOT NULL CHECK (stage IN ('warm-up', 'baseline', 'stress', 'max')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at TIMESTAMPTZ,
  target_events INTEGER,
  locust_users INTEGER,
  locust_spawn_rate NUMERIC(10, 2),
  notes TEXT
);

CREATE TABLE IF NOT EXISTS benchmark_events (
  id BIGSERIAL PRIMARY KEY,
  run_id UUID,
  approach TEXT NOT NULL,
  source_event_id TEXT NOT NULL,
  source_commit_ts TIMESTAMPTZ,
  observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  latency_ms DOUBLE PRECISION,
  payload_bytes INTEGER,
  operation TEXT,
  notes TEXT,
  CONSTRAINT fk_benchmark_events_run
    FOREIGN KEY (run_id) REFERENCES benchmark_runs(run_id)
      ON DELETE SET NULL
);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_customers_set_updated_at ON customers;
CREATE TRIGGER trg_customers_set_updated_at
BEFORE UPDATE ON customers
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_orders_set_updated_at ON orders;
CREATE TRIGGER trg_orders_set_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_orders_status_created_at
  ON orders (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id
  ON orders (customer_id);

CREATE INDEX IF NOT EXISTS idx_benchmark_events_approach_observed
  ON benchmark_events (approach, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_benchmark_events_run
  ON benchmark_events (run_id);

CREATE INDEX IF NOT EXISTS idx_benchmark_events_latency
  ON benchmark_events (approach, latency_ms);
