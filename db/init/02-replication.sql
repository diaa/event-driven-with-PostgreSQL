-- Publication for table-level CDC demo.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'app_cdc_pub') THEN
    CREATE PUBLICATION app_cdc_pub FOR TABLE orders;
  END IF;
END
$$;

-- Optional advanced publication when demonstrating multi-table capture.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'app_cdc_pub_advanced') THEN
    CREATE PUBLICATION app_cdc_pub_advanced FOR TABLE orders, customers;
  END IF;
END
$$;

-- Helpful role for read-only observation if needed by external consumers.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cdc_reader') THEN
    CREATE ROLE cdc_reader LOGIN PASSWORD 'cdc_reader';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE appdb TO cdc_reader;
GRANT USAGE ON SCHEMA public TO cdc_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO cdc_reader;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO cdc_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO cdc_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO cdc_reader;
