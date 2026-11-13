# Implementation Plan

Implement the proof-of-concept accounting API described in [OUTLINE.md](./OUTLINE.md), following idiomatic Gleam project structure, types, and ecosystem conventions. Use the existing [docker-compose.yml](./docker-compose.yml) for local PostgreSQL.

## 1. Set up the Gleam application

- Initialize a standard Gleam application with conventional `src/` and `test/` directories.
- Use established Gleam ecosystem packages for HTTP serving, JSON, PostgreSQL access, and environment configuration.
- Keep HTTP handlers, domain logic, and persistence code in focused Gleam modules with typed inputs and results.
- Add configuration for the existing PostgreSQL environment variables and a simple health check.

## 2. Add database migrations and persistence

- Create migrations for accounts, transfers, entries, and account-balance snapshots.
- Enforce required fields, unique external IDs, foreign keys, positive amounts, and distinct debit and credit accounts in the database.
- Prevent mutation of immutable records.
- Implement typed persistence functions for account and transfer operations.

## 3. Implement account behavior

- Add account create, index, and show operations under `/api/v1/accounts`.
- Default `track_balance` to `true`; create a zero-balance snapshot only for tracked accounts.
- Return the latest snapshot as `current_balance` for tracked accounts and `null` for untracked accounts.
- Keep account records immutable.

## 4. Implement transfer behavior

- Add transfer create, index, and show operations under `/api/v1/transfers`.
- Create transfers in a single database transaction: lock affected accounts in deterministic order, check the latest balance of a tracked debit account, then write the transfer, both entries, and any tracked-account snapshots.
- Skip balance checks and snapshots for untracked accounts while still recording their entries.
- Ensure failures roll back every write and concurrent transfers cannot overspend tracked accounts.

## 5. Implement account-balance API and request errors

- Add the account-balance index at `/api/v1/account_balances`.
- Accept create fields inside the required `account` or `transfer` JSON object.
- Return JSON errors with the specified status codes: `400` for a missing wrapper, `404` for missing records, `409` for concurrent unique-ID conflicts, and `422` for invalid input or insufficient funds.
- Do not expose entries or add update/delete API actions.

## 6. Test and document

- Add Gleam tests for validations, account and transfer responses, balances, untracked accounts, and expected error statuses.
- Add PostgreSQL-backed tests for atomic rollback and concurrent debits.
- Run formatting, tests, and the application against the Docker Compose PostgreSQL service.
- Document local setup, environment variables, migrations, and test commands.
