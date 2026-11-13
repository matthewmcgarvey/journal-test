-- name: ListAccountBalances :many
SELECT id, account_id, running_balance, created_at
FROM account_balances
ORDER BY account_id ASC, id ASC;

-- name: InsertAccountBalance :exec
INSERT INTO account_balances (account_id, running_balance)
VALUES (sqlc.arg(account_id), sqlc.arg(running_balance));
