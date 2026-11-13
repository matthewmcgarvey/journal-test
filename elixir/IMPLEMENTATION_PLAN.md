# Implementation Plan

## Agreed decisions and scope

- Build an API-only Elixir service with Phoenix, Ecto, and PostgreSQL.
- Use bare JSON objects for single-resource responses and JSON arrays for index responses. Create requests remain wrapped in `account` or `transfer`.
- `GET /api/v1/account_balances` returns all snapshots and may be filtered by `account_id`.
- Keep this as a proof of concept; do not add production deployment or operational requirements.
- Do not add update or delete API actions.

## Work plan

### 1. Scaffold the application

- Create a Phoenix application configured for JSON APIs and Ecto/PostgreSQL.
- Add the router, endpoint, application supervision, and test configuration.
- Configure the database connection from environment variables, using local development defaults consistent with `docker-compose.yml`.
- Retain the existing Compose service and its configurable credentials and host port; document the variables and the local-only defaults.

**Done when:** the application starts, connects to the Compose PostgreSQL service, and its test database can be created and migrated.

### 2. Define persistence and constraints

- Add Ecto schemas and migrations for `accounts`, `transfers`, `entries`, and `account_balances`, with the fields and references in `OUTLINE.md`.
- Add database constraints and indexes for required fields, unique `external_id` values, foreign keys, positive transfer/entry amounts, and distinct debit/credit account IDs.
- Create the initial zero-balance snapshot in the same transaction as a tracked account. Do not create snapshots for untracked accounts.
- Treat all four record types as immutable: expose no mutation operations and prevent updates/deletes at the persistence boundary (including database enforcement).

**Done when:** migrations enforce the listed invariants, and tracked/untracked account creation produces the specified snapshot state.

### 3. Implement account and balance reads

- Add account index, show, and create actions under `/api/v1/accounts`.
- Return `track_balance` and `current_balance` for accounts; derive current balance from the snapshot with the highest ID, returning `null` for untracked accounts.
- Add account-balance index under `/api/v1/account_balances`, returning snapshots in a documented deterministic order and supporting an optional `account_id` filter.
- Ensure missing account lookups return `404`.

**Done when:** request tests cover account creation, tracked and untracked balances, account index/show, snapshot listing/filtering, and missing records.

### 4. Implement atomic transfer creation and reads

- Add transfer index, show, and create actions under `/api/v1/transfers`.
- Validate positive integer-cent amounts, distinct existing accounts, and required fields.
- In one database transaction, lock both affected account rows in ascending ID order, check the latest debit-account snapshot when that account tracks balance, insert the transfer and its debit/credit entries, and insert a new snapshot for each affected tracked account.
- Calculate each new snapshot from its latest balance plus the transfer's signed effect. Do not create snapshots for untracked accounts; do not apply a sufficient-funds check to them.
- Ensure transfer responses contain transfer fields only, not entries.
- Translate concurrent unique external-ID conflicts to `409` and insufficient tracked debit balance to `422`.

**Done when:** request and context tests prove entries/snapshots commit together, failures leave no partial writes, and debit/credit effects and insufficient-funds behavior match the outline.

### 5. Standardize request errors and verify concurrency

- Return JSON `400` when a required `account` or `transfer` object is absent.
- Return JSON `422` for invalid fields and insufficient tracked debit balance, `404` for missing account/transfer records, and `409` for a unique-ID conflict detected during create.
- Use one consistent JSON error shape and cover it with request tests.
- Add a concurrency test for overlapping transfers against a tracked debit account, verifying that locking and checking snapshots prevent overspending.

**Done when:** all specified error cases have the expected status and JSON response, and the concurrency test demonstrates no stale-balance overspend.

### 6. Run project checks

- Run formatting checks and the targeted/full `mix test` suite.
- Verify Compose configuration with `docker compose config` and exercise migrations against the Compose database.
- Review the resulting API routes and constraints against `OUTLINE.md`.

## Assumptions to keep explicit

- Index endpoints are unpaginated for this proof of concept unless implementation reveals a practical need to cap results.
- Index ordering is deterministic; balances use ascending snapshot ID unless a different order is needed for API consistency.
- Success statuses and the exact error JSON shape are not prescribed in the outline; choose and document consistent REST conventions during implementation.
