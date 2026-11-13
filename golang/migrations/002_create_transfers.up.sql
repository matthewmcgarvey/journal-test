CREATE TABLE IF NOT EXISTS transfers (
    id SERIAL PRIMARY KEY,
    external_id VARCHAR(255) NOT NULL UNIQUE,
    debit_account_id INTEGER NOT NULL REFERENCES accounts(id),
    credit_account_id INTEGER NOT NULL REFERENCES accounts(id),
    amount BIGINT NOT NULL CHECK (amount > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (debit_account_id <> credit_account_id)
);
