-- Sample benchmark data for fallback/demo purposes.
-- Run against the appdb database to populate the benchmark dashboard
-- with representative data if a live benchmark run is not available.
--
-- Usage: psql -h localhost -U postgres -d appdb -f sample-data-seed.sql

INSERT INTO benchmark_events (approach, source_event_id, source_commit_ts, observed_at, latency_ms, payload_bytes, operation, notes)
VALUES
  -- wal2json samples (typical latency: 8-35ms)
  ('wal2json', '1001', now() - interval '10 minutes', now() - interval '10 minutes' + interval '12 milliseconds',  12.3, 256, 'INSERT', 'sample'),
  ('wal2json', '1002', now() - interval '9 minutes',  now() - interval '9 minutes'  + interval '9 milliseconds',   9.1, 260, 'INSERT', 'sample'),
  ('wal2json', '1003', now() - interval '8 minutes',  now() - interval '8 minutes'  + interval '15 milliseconds', 15.4, 248, 'UPDATE', 'sample'),
  ('wal2json', '1004', now() - interval '7 minutes',  now() - interval '7 minutes'  + interval '11 milliseconds', 11.0, 252, 'INSERT', 'sample'),
  ('wal2json', '1005', now() - interval '6 minutes',  now() - interval '6 minutes'  + interval '18 milliseconds', 18.2, 270, 'INSERT', 'sample'),
  ('wal2json', '1006', now() - interval '5 minutes',  now() - interval '5 minutes'  + interval '14 milliseconds', 14.7, 245, 'UPDATE', 'sample'),
  ('wal2json', '1007', now() - interval '4 minutes',  now() - interval '4 minutes'  + interval '10 milliseconds', 10.5, 255, 'INSERT', 'sample'),
  ('wal2json', '1008', now() - interval '3 minutes',  now() - interval '3 minutes'  + interval '22 milliseconds', 22.1, 280, 'INSERT', 'sample'),
  ('wal2json', '1009', now() - interval '2 minutes',  now() - interval '2 minutes'  + interval '8 milliseconds',   8.3, 240, 'UPDATE', 'sample'),
  ('wal2json', '1010', now() - interval '1 minute',   now() - interval '1 minute'   + interval '35 milliseconds', 35.0, 290, 'INSERT', 'sample'),

  -- debezium samples (typical latency: 25-80ms, higher due to Kafka hop)
  ('debezium', '2001', now() - interval '10 minutes', now() - interval '10 minutes' + interval '42 milliseconds',  42.5, 520, 'INSERT', 'sample'),
  ('debezium', '2002', now() - interval '9 minutes',  now() - interval '9 minutes'  + interval '38 milliseconds',  38.1, 530, 'INSERT', 'sample'),
  ('debezium', '2003', now() - interval '8 minutes',  now() - interval '8 minutes'  + interval '55 milliseconds',  55.3, 510, 'UPDATE', 'sample'),
  ('debezium', '2004', now() - interval '7 minutes',  now() - interval '7 minutes'  + interval '48 milliseconds',  48.0, 525, 'INSERT', 'sample'),
  ('debezium', '2005', now() - interval '6 minutes',  now() - interval '6 minutes'  + interval '62 milliseconds',  62.4, 540, 'INSERT', 'sample'),
  ('debezium', '2006', now() - interval '5 minutes',  now() - interval '5 minutes'  + interval '45 milliseconds',  45.8, 515, 'UPDATE', 'sample'),
  ('debezium', '2007', now() - interval '4 minutes',  now() - interval '4 minutes'  + interval '35 milliseconds',  35.2, 505, 'INSERT', 'sample'),
  ('debezium', '2008', now() - interval '3 minutes',  now() - interval '3 minutes'  + interval '72 milliseconds',  72.0, 560, 'INSERT', 'sample'),
  ('debezium', '2009', now() - interval '2 minutes',  now() - interval '2 minutes'  + interval '28 milliseconds',  28.9, 500, 'UPDATE', 'sample'),
  ('debezium', '2010', now() - interval '1 minute',   now() - interval '1 minute'   + interval '80 milliseconds',  80.1, 580, 'INSERT', 'sample'),

  -- drasi samples (typical latency: 10-40ms)
  ('drasi',    '3001', now() - interval '10 minutes', now() - interval '10 minutes' + interval '18 milliseconds',  18.2, NULL, 'INSERT', 'sample'),
  ('drasi',    '3002', now() - interval '9 minutes',  now() - interval '9 minutes'  + interval '15 milliseconds',  15.0, NULL, 'INSERT', 'sample'),
  ('drasi',    '3003', now() - interval '8 minutes',  now() - interval '8 minutes'  + interval '22 milliseconds',  22.7, NULL, 'UPDATE', 'sample'),
  ('drasi',    '3004', now() - interval '7 minutes',  now() - interval '7 minutes'  + interval '17 milliseconds',  17.4, NULL, 'INSERT', 'sample'),
  ('drasi',    '3005', now() - interval '6 minutes',  now() - interval '6 minutes'  + interval '25 milliseconds',  25.1, NULL, 'INSERT', 'sample'),
  ('drasi',    '3006', now() - interval '5 minutes',  now() - interval '5 minutes'  + interval '20 milliseconds',  20.6, NULL, 'UPDATE', 'sample'),
  ('drasi',    '3007', now() - interval '4 minutes',  now() - interval '4 minutes'  + interval '13 milliseconds',  13.8, NULL, 'INSERT', 'sample'),
  ('drasi',    '3008', now() - interval '3 minutes',  now() - interval '3 minutes'  + interval '30 milliseconds',  30.3, NULL, 'INSERT', 'sample'),
  ('drasi',    '3009', now() - interval '2 minutes',  now() - interval '2 minutes'  + interval '11 milliseconds',  11.5, NULL, 'UPDATE', 'sample'),
  ('drasi',    '3010', now() - interval '1 minute',   now() - interval '1 minute'   + interval '40 milliseconds',  40.2, NULL, 'INSERT', 'sample');
