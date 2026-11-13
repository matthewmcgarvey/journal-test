# Transaction Journal

A Ruby on Rails JSON API for recording transfers between accounts.

## Requirements

- Ruby 4.0.9 and Bundler
- Docker Compose
- PostgreSQL client tools, including `pg_dump`, for schema dumps

## Start PostgreSQL

Build and start the PostgreSQL service:

```sh
docker compose up -d postgres
```

The database image is built from `docker/postgres/Dockerfile`. The service persists data in the `postgres_data` volume and publishes port `5432` by default.

The local defaults are:

- Database: `transaction_journal_development`
- Username: `transaction_journal`
- Password: `local_dev_password`

Override `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, or `POSTGRES_PORT` in the environment to customize the local container. Rails uses `DATABASE_HOST`, `DATABASE_PORT` (or `POSTGRES_PORT`), `POSTGRES_USER`, and `POSTGRES_PASSWORD`. These defaults are for local development only.

## Set up the application

```sh
bundle install
bin/rails db:create db:migrate
bin/rails server
```

The API is available at `http://localhost:3000`.

## API

All endpoints return JSON.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/accounts` | List accounts and current balances |
| `GET` | `/api/v1/accounts/:id` | Fetch an account and current balance |
| `POST` | `/api/v1/accounts` | Create an account |
| `GET` | `/api/v1/transfers` | List transfers |
| `GET` | `/api/v1/transfers/:id` | Fetch a transfer |
| `POST` | `/api/v1/transfers` | Create a transfer |
| `GET` | `/api/v1/account_balances` | List tracked-account balance snapshots |

Create a tracked account (the default):

```json
{ "account": { "external_id": "customer-1" } }
```

Create an untracked source account:

```json
{ "account": { "external_id": "root", "track_balance": false } }
```

Create a transfer:

```json
{
  "transfer": {
    "external_id": "funding-1",
    "debit_account_id": 1,
    "credit_account_id": 2,
    "amount": 1099
  }
}
```

Transfers must use different accounts and always create debit and credit entries. Balance snapshots and insufficient-funds checks apply only to accounts with `track_balance: true`. Accounts, transfers, entries, and balance snapshots are immutable.

## Run tests

```sh
bin/rails test
```
