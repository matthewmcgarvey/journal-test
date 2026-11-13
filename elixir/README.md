# Journal

An API-only Phoenix service for recording financial transfers in integer cents.
This proof of concept uses PostgreSQL for storage and Docker Compose for a local
development database.

## Run locally

1. Start PostgreSQL with `docker compose up -d`.
2. Install dependencies and create/migrate the database with `mix setup`.
3. Start the API with `mix phx.server`.
4. Run tests with `mix test`.

The Compose service and development/test database connection use these
environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `POSTGRES_USER` | `app` | Local PostgreSQL user |
| `POSTGRES_PASSWORD` | `app` | Local PostgreSQL password |
| `POSTGRES_DB` | `accounting` | Development database name |
| `POSTGRES_PORT` | `5432` | Host port mapped to PostgreSQL |
| `POSTGRES_HOST` | `localhost` | PostgreSQL host used by the app |
| `POSTGRES_TEST_DB` | `accounting_test` | Test database name |

These defaults are for local development only. Set the same `POSTGRES_*`
variables in the shell before `docker compose up -d` and `mix setup` when using
custom credentials or ports. Tests use the `_test` database by default.

## API

All routes are prefixed with `/api/v1`. Successful single-resource responses
are bare JSON objects; index responses are arrays. Amounts and balances are
integer cents.

- `GET /accounts`
- `GET /accounts/:id`
- `POST /accounts` with `{"account":{"external_id":"...","track_balance":true}}`
- `GET /transfers`
- `GET /transfers/:id`
- `POST /transfers` with `{"transfer":{"external_id":"...","debit_account_id":1,"credit_account_id":2,"amount":250}}`
- `GET /account_balances` (optional `account_id` query parameter)

Accounts and ledger records are immutable. Fund tracked accounts by transferring
from an untracked source account. Insufficient tracked debit balances are
rejected.
