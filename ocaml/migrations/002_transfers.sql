CREATE TABLE transfers (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  external_id text NOT NULL UNIQUE CHECK (length(btrim(external_id)) > 0),
  debit_account_id integer NOT NULL REFERENCES accounts(id),
  credit_account_id integer NOT NULL REFERENCES accounts(id),
  amount integer NOT NULL CHECK (amount > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT transfer_accounts_must_differ
    CHECK (debit_account_id <> credit_account_id)
);
