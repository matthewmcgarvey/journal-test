# Outline

## Service

Build a API service in Elixir backed by PostgreSQL. The PostgreSQL instance must be initiated through a docker compose file, have configurable credentials, and a configurable host port (default `5432`). Local defaults are for development only. This is only a proof-of-concept so do not consider production usage or needs.

The service journals financial transfers. Its API returns JSON. Monetary values are integer cents (for example, `$10.99` is `1099`).

Use `/api/v1` as the API prefix:
- Accounts: `/api/v1/accounts`
- Transfers: `/api/v1/transfers`
- Account balances: `/api/v1/account_balances`

Create requests wrap fields in an `account` or `transfer` JSON object, respectively.

## Account

An account is a party that can send or receive funds. Accounts do not have a fixed debit or credit role; their role depends on each transfer.

Fields:
- `id`: integer primary key
- `external_id`: string, unique
- `track_balance`: bool
- `created_at`: timestamp

API actions: `index`, `show`, `create`

`track_balance` defaults to `true`. Accounts created with `track_balance=true` start with a $0 balance. Account index and show responses include `track_balance` and `current_balance` in integer cents for tracked accounts; `current_balance` is `null` for untracked accounts. Account records are immutable.

## Transfer

A transfer records the movement of funds between two accounts. Its amount must be a positive integer number of cents. The `debit_account_id` and `credit_account_id` determine the accounts' roles for this transfer only.

The debit and credit account IDs must be different.

Fields:
- `id`: integer primary key
- `external_id`: string, unique
- `debit_account_id`: integer, references the account debited by this transfer
- `credit_account_id`: integer, references the account credited by this transfer
- `amount`: positive integer cents
- `created_at`: timestamp

API actions: `index`, `show`, `create`

Creating a transfer stores the Transfer and creates two immutable Entries: a debit entry for the debit account and a credit entry for the credit account. It also creates a new Account Balance snapshot for each affected account with `track_balance=true`. No balance snapshot is created for untracked accounts. All writes must succeed or fail together.

Transfer responses include the transfer's fields but do not expose its Entries.

## Entry

An Entry is an internal, immutable record of a transfer's effect on one account. Entries are not exposed through the API.

Fields:
- `id`: integer primary key
- `account_id`: integer, references the affected account
- `transfer_id`: integer, references the transfer
- `amount`: positive integer cents
- `debit`: boolean

`debit: true` subtracts the amount from the account balance. `debit: false` adds it. Every transfer creates a debit and a credit entry; accounts can receive either kind of entry on different transfers.

## Account Balance

An Account Balance is an immutable snapshot of a tracked account's balance at a point in time. A new snapshot is created when a tracked account is created and whenever a transfer affects it. Untracked accounts have no Account Balance records.

Fields:
- `id`: integer primary key
- `account_id`: integer, references the account
- `running_balance`: integer cents
- `created_at`: timestamp

API actions: `index`

The current balance is the snapshot with the highest ID for the account. The Account Balance index returns the recorded snapshots.

## Balance and transfer rules

- Account creation creates a zero-balance snapshot only when `track_balance=true`; there is no opening-balance API action.
- Accounts are funded through transfers. A root/source account can fund another account without a balance check by setting `track_balance=false`.
- Sufficient funds are checked only for a debit account with `track_balance=true`; the transfer fails if its current balance is less than the transfer amount.
- `track_balance=false` accounts have no balance snapshots and are not subject to the sufficient-funds check. Their entries are still recorded.
- Each transfer's entries are the source of its balance changes: subtract debit entries and add credit entries.
- Creating a transfer must immediately make its entries and applicable balance snapshots visible with the transfer.
- Concurrent transfers involving tracked accounts must not use stale balances or allow those accounts to overspend. Lock affected account records in a deterministic order, check the latest snapshots while holding the locks, and write the transfer, entries, and applicable snapshots in one database transaction.
- All records are immutable. Do not provide update or delete API actions, and prevent record mutation.
- Enforce required fields, unique external IDs, valid account and transfer references, and positive transfer and entry amounts.

## Request errors

- Invalid input and insufficient balance on a tracked debit account return a JSON `422` response.
- A request missing its required `account` or `transfer` object returns JSON `400`.
- Lookups for missing account or transfer records return JSON `404`.
- A unique-ID conflict detected during a concurrent create returns JSON `409`.
