# Implementation Plan

## Goal

Build a Ruby on Rails JSON API for accounts, transfers, and immutable account-balance snapshots for accounts that opt into balance tracking, backed by PostgreSQL. Creating a transfer must atomically record the transfer, its debit/credit entries, and any applicable balance snapshots, safely under concurrent requests.

## Implementation sequence

1. **Create the Rails service**
   - Initialize a Rails API-only application with PostgreSQL as its database.
   - Add the required Ruby/Rails dependencies and environment configuration.
   - Add a PostgreSQL `Dockerfile` and a Compose configuration to build and run the database locally, with persistent data and configurable credentials.
   - Document the commands to start the database, prepare the schema, and run the API and tests.

2. **Define the data model and constraints**
   - Create `accounts` with an integer primary key, unique non-null `external_id`, non-null boolean `track_balance` (default `true`), and `created_at`; do not store a mutable balance on the account.
   - Create `transfers` with an integer primary key, unique non-null `external_id`, debit and credit account references, `amount` in cents, and `created_at`.
   - Create `entries` with an integer primary key, account and transfer references, integer `amount` in cents, and boolean `debit`. Entries are internal and are not exposed through the API.
   - Create `account_balances` with an integer primary key, an account reference, `running_balance` in cents, and `created_at`. Each row is an immutable balance snapshot for that account.
   - Add database constraints for required fields, unique external IDs, valid account/transfer references, positive transfer amounts, and valid entry amounts.
   - Index external IDs, transfer account references, entry account/transfer references, and account-balance account/ID lookups.

3. **Implement account endpoints**
   - Add JSON endpoints for account index, show, and create.
   - Include `track_balance` in account responses. For tracked accounts, include the current balance; for untracked accounts, return a clearly defined no-balance value (for example, `null`).
   - For accounts with `track_balance: true`, create an initial zero-balance snapshot in the same transaction as account creation. Do not create balance snapshots for untracked accounts.
   - Add the account-balance index endpoint to return the recorded balance snapshots.
   - Return consistent JSON and error responses.

4. **Implement transfer endpoints**
   - Add JSON endpoints for transfer index, show, and create.
   - On create, validate the request and perform the transfer in a database transaction:
     1. Lock both account rows in a deterministic order to serialize transfers involving either account and reduce deadlock risk.
     2. Reject a transfer whose debit and credit account IDs are the same.
     3. Read the debit account's latest balance snapshot and enforce sufficient funds only when its `track_balance` is true. Untracked debit accounts have no balance to check.
     4. Insert the immutable transfer and entries based on its account IDs: a debit entry (`debit: true`) for `debit_account_id` and a credit entry (`debit: false`) for `credit_account_id`. Accounts have no permanent debit/credit classification and may have either role on different transfers.
     5. Apply entry effects and insert a new immutable balance snapshot for each affected account whose `track_balance` is true. Untracked accounts still receive entries but have no balance snapshots.
     6. Roll back the transfer, entries, and snapshots if any step fails.
   - Use entries as the source of each transfer's balance changes: `debit: true` subtracts the amount; `debit: false` adds it.
   - Use `track_balance: false` for root/source accounts that should fund transfers without a balance check. This per-account setting replaces a separate root-account allowlist. Return a clear client error for invalid requests or insufficient funds on tracked debit accounts; do not create a partial transfer.

5. **Enforce immutability**
   - Treat accounts, transfers, entries, and account-balance snapshots as append-only records; do not expose update or delete API actions.
   - Prevent updates and deletes through the model layer and database, including direct database writes.
   - Always insert entries for transfer effects. For tracked accounts, represent each balance change by inserting a snapshot and determine the current balance from the highest-ID snapshot. Untracked accounts have no balance snapshot. Account-row locking serializes writes per account.

6. **Verify behavior**
   - Add request/model tests for account and transfer actions, account-balance index, response balance fields, validations, not-found cases, insufficient funds, tracked/untracked behavior, and atomic rollback.
   - Verify tracked accounts start with a zero-balance snapshot, untracked accounts have none, and transfers always create the correct entries while creating snapshots only for tracked accounts.
   - Verify an untracked root/source account can fund a transfer without a balance check, while a tracked account cannot overdraw.
   - Verify entries are not exposed through API routes and that entry amounts and debit flags produce the expected balance effects.
   - Add a concurrency test that creates transfers sharing an account in parallel and verifies entries, snapshots, available balance, and persisted transfers are consistent.
   - Run the focused test suite, then the full suite, and document how to run both.

## Assumptions to confirm

- Accounts default to `track_balance: true`; clients may set it to `false` for accounts that should not maintain a balance, including root/source accounts.
- Only tracked accounts have balance snapshots and sufficient-funds checks. Entries are recorded for tracked and untracked accounts.
- Transfer amounts must be positive integer cents.
- Transfers using the same account for both account IDs are rejected.
- API pagination, authentication, and idempotency behavior are not specified and are outside the initial implementation unless requested.
