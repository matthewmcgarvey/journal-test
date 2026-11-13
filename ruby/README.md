# Transaction Journal

A Ruby on Rails JSON API for recording transfers between accounts.

## Requirements

- Ruby 4.0.9 and Bundler
- Docker Compose

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

Override `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, or `POSTGRES_PORT` in the environment to customize the local container. The matching Rails settings use `DATABASE_HOST`, `POSTGRES_USER`, and `POSTGRES_PASSWORD`. These defaults are for local development only.

## Set up the application

```sh
bundle install
bin/rails db:create db:migrate
bin/rails server
```

The API is available at `http://localhost:3000`.

## Run tests

```sh
bin/rails test
```
