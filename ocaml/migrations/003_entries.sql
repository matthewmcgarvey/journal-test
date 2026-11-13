CREATE TABLE entries (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id integer NOT NULL REFERENCES accounts(id),
  transfer_id integer NOT NULL REFERENCES transfers(id),
  amount integer NOT NULL CHECK (amount > 0),
  debit boolean NOT NULL,
  CONSTRAINT one_entry_per_transfer_role UNIQUE (transfer_id, debit)
);
