CREATE TABLE account_balances (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id integer NOT NULL REFERENCES accounts(id),
  running_balance integer NOT NULL CHECK (running_balance >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
