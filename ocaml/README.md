# OCaml journal API

This proof-of-concept service implements the JSON API in [OUTLINE.md](./OUTLINE.md) with Dream, Caqti/Lwt, and PostgreSQL.

## Requirements

- OCaml 5.3 or later and opam
- Dune 3.17 or later
- Docker Compose, for the PostgreSQL service

The project has a local opam switch. From this directory, initialize opam if needed and install the project dependencies:

```sh
opam switch create . ocaml-base-compiler.5.3.0
eval "$(opam env)"
opam install . --deps-only --with-test --with-dev-setup
```

Start the existing PostgreSQL service with `docker compose up -d postgres`. Its Compose environment variables are `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, and `POSTGRES_PORT`; defaults are intended only for local development.

The application accepts `DATABASE_URL`. If it is unset, it builds a local connection URL from `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST` (default `127.0.0.1`), `POSTGRES_PORT`, and `POSTGRES_DB`. The server listens on `PORT` (default `4000`).

## Build, migrate, and run

```sh
dune build
dune exec journal-migrate
dune exec journal-server
```

Migrations are ordered SQL files under [migrations/](./migrations/), recorded in `schema_migrations`, and applied one transaction at a time. Set `MIGRATIONS_DIR` only when running from a different working directory.

## Tests

```sh
dune runtest
```

Request-validation tests run without PostgreSQL. Set `TEST_DATABASE_URL` to a dedicated PostgreSQL test database to run the integration test; it creates uniquely named immutable test records and does not truncate or delete existing data:

```sh
docker compose exec postgres sh -c 'createdb -U "$POSTGRES_USER" accounting_ocaml_test'
TEST_DATABASE_URL=postgresql://app:app@127.0.0.1:5432/accounting_ocaml_test dune runtest
```

The integration test verifies append-only unique IDs, tracked and untracked snapshots, debit/credit entries, and that concurrent transfers cannot overdraw a tracked account.

## API

All routes are under `/api/v1`. Indexes return arrays ordered by ID; show and create actions return a JSON object. Creates return `201`. Accounts always include `track_balance` and `current_balance` (`null` for untracked accounts). The account-balance index supports `?account_id=<id>`. Errors use `{"error":"..."}` with the status codes in the outline. Records are append-only and entries are not exposed.
