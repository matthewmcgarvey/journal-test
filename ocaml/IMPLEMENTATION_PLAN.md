# OCaml Implementation Plan

## Goal and scope

Build the PostgreSQL-backed financial journal API described in [OUTLINE.md](./OUTLINE.md). Keep all application code, tests, migrations, and documentation in `ocaml/`. The existing [docker-compose.yml](./docker-compose.yml) provides the local PostgreSQL instance; do not replace or duplicate it.

## Technology choices

- **Dune** for the project and executable/test build.
- **Dream** for the HTTP server and routing.
- **Caqti with Lwt** (`caqti-lwt` and `caqti-driver-postgresql`) for typed PostgreSQL access and transactions.
- **Yojson.Basic** for JSON request/response encoding.
- **SQL migration files** run by a small OCaml migration executable, so schema constraints and immutability are explicit and versioned.
- **Alcotest** for unit and PostgreSQL-backed integration tests.

These are established OCaml ecosystem components and keep the proof of concept small without inventing a framework or ORM layer.

## Implementation sequence

1. **Bootstrap the project**
   - Add the Dune project, opam package manifest, library, server executable, migration executable, and test targets.
   - Read database configuration from `DATABASE_URL`, with local development defaults consistent with Compose.
   - Keep build products and local environment files out of source control.

2. **Create schema and migrations**
   - Add ordered SQL migrations for `accounts`, `transfers`, `entries`, and `account_balances`.
   - Enforce non-null and unique fields, foreign keys, positive amounts, and distinct transfer accounts in PostgreSQL.
   - Enforce append-only behavior for all four record types in the database, and expose no update/delete routes.
   - Add an initial zero snapshot in the account-creation transaction only for tracked accounts.

3. **Implement database and domain operations**
   - Use typed Caqti request definitions and explicit result/error types.
   - Implement account creation and reads, current balance lookup by greatest snapshot ID, and snapshot listing (optionally filtered by `account_id`).
   - Implement transfer creation in a single transaction: lock both account rows in ascending ID order, inspect current snapshots while locked, enforce tracked-debit funds, insert the transfer and two entries, then insert snapshots for affected tracked accounts.
   - Preserve entries for untracked accounts while skipping their snapshots and debit balance checks.

4. **Implement the HTTP API**
   - Add `GET`/`POST /api/v1/accounts`, `GET /api/v1/accounts/:id`, `GET`/`POST /api/v1/transfers`, `GET /api/v1/transfers/:id`, and `GET /api/v1/account_balances`.
   - Require the `account` and `transfer` wrappers on create requests.
   - Use JSON objects for individual records, arrays for indexes, and never expose entries.
   - Return a consistent JSON error body: `400` for a missing wrapper, `404` for missing records, `409` for duplicate external IDs, and `422` for invalid input or insufficient funds.

5. **Test and document**
   - Add focused unit tests for decoding, validation, mapping, and error responses.
   - Add PostgreSQL integration tests for tracked/untracked account creation, snapshots, transfer entries and balances, rollback, duplicate IDs, and concurrent transfers that must not overspend.
   - Document local setup, environment variables, migration commands, server startup, and test commands in `README.md`.
   - Run formatting, build, and tests, then review the routes and constraints against `OUTLINE.md`.

## API decisions

- Account and transfer index results are deterministic and ordered by ID ascending.
- `GET /api/v1/account_balances` returns all snapshots in ascending ID order and accepts an optional `account_id` filter.
- Account JSON always includes `track_balance`; `current_balance` is integer cents for tracked accounts and `null` for untracked accounts.
- Successful creates return `201`; successful reads return `200`.
- Error bodies use `{"error":"..."}`. Pagination, authentication, and production deployment are outside this proof of concept.

## Completion criteria

- The service builds and starts against the PostgreSQL service configured by the existing Compose file.
- Migrations enforce the schema and immutability requirements.
- Every specified route and status code is covered by tests.
- Transfer writes are atomic, and concurrent transfers cannot overspend a tracked debit account.
- No files outside `ocaml/` are changed.
