CREATE TABLE accounts (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  external_id text NOT NULL UNIQUE CHECK (length(btrim(external_id)) > 0),
  track_balance boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
