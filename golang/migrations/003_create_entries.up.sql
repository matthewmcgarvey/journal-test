CREATE TABLE IF NOT EXISTS entries (
    id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id),
    transfer_id INTEGER NOT NULL REFERENCES transfers(id),
    amount BIGINT NOT NULL CHECK (amount > 0),
    debit BOOLEAN NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entries_account_id ON entries(account_id);
CREATE INDEX IF NOT EXISTS idx_entries_transfer_id ON entries(transfer_id);
