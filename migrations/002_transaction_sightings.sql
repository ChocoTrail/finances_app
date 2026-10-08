CREATE TABLE transaction_sightings (
  transaction_id VARCHAR NOT NULL REFERENCES transactions(transaction_id),
  import_id VARCHAR NOT NULL REFERENCES imports(import_id),
  seen_at TIMESTAMP NOT NULL,
  PRIMARY KEY (transaction_id, import_id)
);

INSERT INTO transaction_sightings (
  transaction_id,
  import_id,
  seen_at
)
SELECT
  transaction_id,
  first_seen_import_id,
  created_at
FROM transactions
ON CONFLICT DO NOTHING;

CREATE INDEX transaction_sightings_import_idx
  ON transaction_sightings (import_id, seen_at);
