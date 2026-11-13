-- name: ListTransfers :many
SELECT id, external_id, debit_account_id, credit_account_id, amount, created_at
FROM transfers
ORDER BY id ASC;

-- name: GetTransfer :one
SELECT id, external_id, debit_account_id, credit_account_id, amount, created_at
FROM transfers
WHERE id = sqlc.arg(id)::BIGINT;

-- name: LockTransferAccounts :many
SELECT id, track_balance
FROM accounts
WHERE id IN (
    sqlc.arg(debit_account_id)::BIGINT,
    sqlc.arg(credit_account_id)::BIGINT
)
ORDER BY id
FOR UPDATE;

-- name: LatestAccountBalance :one
SELECT running_balance
FROM account_balances
WHERE account_id = sqlc.arg(account_id)::BIGINT
ORDER BY id DESC
LIMIT 1;

-- name: InsertTransfer :one
INSERT INTO transfers (external_id, debit_account_id, credit_account_id, amount)
VALUES (
    sqlc.arg(external_id),
    sqlc.arg(debit_account_id),
    sqlc.arg(credit_account_id),
    sqlc.arg(amount)
)
RETURNING id, external_id, debit_account_id, credit_account_id, amount, created_at;

-- name: InsertEntry :exec
INSERT INTO entries (account_id, transfer_id, amount, debit)
VALUES (
    sqlc.arg(account_id),
    sqlc.arg(transfer_id),
    sqlc.arg(amount),
    sqlc.arg(debit)
);
