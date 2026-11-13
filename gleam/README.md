# Accounting API

A proof-of-concept Gleam JSON API backed by PostgreSQL. Monetary amounts are
integer cents.

## Run locally

Start PostgreSQL with Docker Compose:

```sh
docker compose up -d
```

The local development defaults are `app` / `app` and database `accounting` on
host port `5432`. Override them with `POSTGRES_USER`, `POSTGRES_PASSWORD`,
`POSTGRES_DB`, and `POSTGRES_PORT`. The service reads the same database
credentials and port, plus `POSTGRES_HOST` (default `localhost`). Set `PORT` to
change the HTTP port (default `8000`).

Run the service:

```sh
gleam run
```

The application creates its schema on startup and binds to `0.0.0.0`.

## API

All routes use the `/api/v1` prefix:

- `GET /api/v1/accounts`, `POST /api/v1/accounts`, `GET /api/v1/accounts/:id`
- `GET /api/v1/transfers`, `POST /api/v1/transfers`, `GET /api/v1/transfers/:id`
- `GET /api/v1/account_balances`

Create requests use an `account` or `transfer` JSON wrapper. For example:

```json
{
  "account": {
    "external_id": "cash-source",
    "track_balance": false
  }
}
```

Success responses wrap the resource or collection under its resource name.
Request errors return JSON: `400` for a missing wrapper, `404` for a missing
account or transfer, `409` for a duplicate external ID, and `422` for invalid
input or insufficient tracked balance.

## Structure

- `src/accounting_api/` contains routing, resource handlers, and JSON codecs.
- `src/accounting_domain/` contains domain types, database setup, and
  resource-specific repositories.

## Development

```sh
gleam format
gleam test
```
