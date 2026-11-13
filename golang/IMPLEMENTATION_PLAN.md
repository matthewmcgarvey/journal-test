# Accounting service implementation plan

## Goal
Build a small Go API service in a PostgreSQL-backed proof-of-concept that journals financial transfers, exposes JSON at `/api/v1`, and enforces the rules described in the project outline.

## Technology choices
- HTTP framework: Gin
- Database driver: pgx via `database/sql`
- Migrations: `golang-migrate/migrate` with SQL migration files
- Local database runtime: Docker Compose for PostgreSQL

## High-level architecture
- `cmd/server`: application entrypoints
- `cmd/migrate`: migration runner entrypoint
- `internal/config`: environment configuration
- `internal/db`: connection and migration logic
- `internal/api`: HTTP handlers and routing
- `internal/domain`: domain structs and validation helpers
- `migrations`: SQL migration files

## Step 1: Bootstrap the service
- Create the Go module and dependency set
- Add a simple `docker-compose.yml` for PostgreSQL with default local values
- Add `.env.example` for local configuration
- Add a `.gitignore` for local env files and build artifacts

## Step 2: Database and migration setup
- Create a PostgreSQL service in Docker Compose using configurable credentials and host port
- Use `golang-migrate/migrate` with SQL files under `migrations/`
- Add app startup logic that runs pending migrations before serving traffic

Recommended migration sequence:
1. `accounts`
2. `transfers`
3. `entries`
4. `account_balances`

## Step 3: Schema design
Define immutable accounting tables:

- `accounts`
  - `id`
  - `external_id` unique
  - `track_balance`
  - `created_at`
- `transfers`
  - `id`
  - `external_id` unique
  - `debit_account_id`
  - `credit_account_id`
  - `amount`
  - `created_at`
- `entries`
  - `id`
  - `account_id`
  - `transfer_id`
  - `amount`
  - `debit`
- `account_balances`
  - `id`
  - `account_id`
  - `running_balance`
  - `created_at`

Include constraints:
- positive amount values
- unique external IDs
- `debit_account_id != credit_account_id`
- tracked accounts start with a zero-balance snapshot
- all records immutable in behavior and API surface

## Step 4: Account API implementation
Endpoints:
- `GET /api/v1/accounts`
- `GET /api/v1/accounts/:id`
- `POST /api/v1/accounts`

Rules:
- `track_balance` defaults to `true`
- create a zero snapshot when tracked
- include `current_balance` for tracked accounts and `null` for untracked accounts
- no account update or delete endpoints

## Step 5: Transfer API implementation
Endpoints:
- `GET /api/v1/transfers`
- `GET /api/v1/transfers/:id`
- `POST /api/v1/transfers`

Rules:
- `amount` must be a positive integer number of cents
- debit and credit account IDs must differ
- transfer must create two immutable entries and apply the corresponding balance snapshot updates
- transfer responses do not expose entries
- the transfer and all related writes must be committed atomically

## Step 6: Balance logic and transaction semantics
The key correctness requirement is the transfer transaction.

Inside one DB transaction:
1. Lock affected tracked accounts in deterministic order
2. Read the latest account balances while locks are held
3. Validate insufficient-funds rules
4. Insert transfer row
5. Insert debit and credit entry rows
6. Insert new `account_balances` rows for tracked accounts affected by the transfer
7. Commit together

This prevents stale balances and overspending when multiple transfers run concurrently.

## Step 7: Error handling
Map domain and validation failures to the correct HTTP status codes:
- `400`: missing required `account`/`transfer` object
- `404`: account or transfer not found
- `409`: duplicate `external_id` conflict
- `422`: invalid payload or insufficient balance

Use a consistent JSON error body shape such as:
`{"error":"message"}`

## Step 8: Validation and testing
Deliver focused integration tests for:
- account creation
- account balance snapshot creation
- transfer success cases
- insufficient funds on tracked debit account
- invalid transfer payloads
- missing IDs and invalid wrapper objects
- duplicate external IDs

We are intentionally not adding a concurrency stress test for this proof-of-concept.

## Main concerns
1. Deterministic lock ordering must be implemented carefully to avoid deadlocks.
2. The transfer validation and new snapshot creation must happen within the same transaction.
3. Balance values should come from immutable snapshots, not mutable account rows.
4. The service must not allow update/delete semantics on immutable accounting records.

## Questions / decisions
- Framework choice is fixed to Gin.
- Migration style is fixed to SQL migrations via `golang-migrate/migrate`.
- Concurrency stress testing is intentionally omitted.

## Immediate next steps
- Create the Go project skeleton
- Add Docker Compose for Postgres
- Add migration runner and initial schema files
- Implement the account and transfer route scaffolding
- Start the transactional transfer logic and validation layer
