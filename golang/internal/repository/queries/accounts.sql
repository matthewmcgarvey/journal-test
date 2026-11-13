-- name: ListAccounts :many
SELECT
    a.id,
    a.external_id,
    a.track_balance,
    a.created_at,
    COALESCE(b.running_balance, 0) AS current_balance,
    (b.account_id IS NOT NULL)::BOOLEAN AS has_balance_snapshot
FROM accounts AS a
LEFT JOIN LATERAL (
    SELECT account_id, running_balance
    FROM account_balances
    WHERE account_id = a.id
    ORDER BY id DESC
    LIMIT 1
) AS b ON TRUE
ORDER BY a.id ASC;

-- name: GetAccount :one
SELECT
    a.id,
    a.external_id,
    a.track_balance,
    a.created_at,
    COALESCE(b.running_balance, 0) AS current_balance,
    (b.account_id IS NOT NULL)::BOOLEAN AS has_balance_snapshot
FROM accounts AS a
LEFT JOIN LATERAL (
    SELECT account_id, running_balance
    FROM account_balances
    WHERE account_id = a.id
    ORDER BY id DESC
    LIMIT 1
) AS b ON TRUE
WHERE a.id = sqlc.arg(id)::BIGINT;

-- name: InsertAccount :one
INSERT INTO accounts (external_id, track_balance)
VALUES (sqlc.arg(external_id), sqlc.arg(track_balance))
RETURNING id, external_id, track_balance, created_at;

-- name: InsertInitialBalance :exec
INSERT INTO account_balances (account_id, running_balance)
VALUES (sqlc.arg(account_id), 0);
