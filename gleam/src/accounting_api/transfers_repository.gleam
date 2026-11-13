import accounting_api/model.{
  type ApiError, type NewTransfer, type Transfer, InsufficientFunds,
  InvalidInput, Transfer,
}
import accounting_api/repository
import gleam/dynamic/decode
import gleam/result
import gleam/string
import pog

type AccountLock {
  AccountLock(id: Int, track_balance: Bool)
}

pub fn transfers(
  connection: pog.Connection,
) -> Result(List(Transfer), ApiError) {
  repository.run(
    connection,
    "SELECT id, external_id, debit_account_id, credit_account_id, amount,
      created_at::text
    FROM transfers
    ORDER BY id",
    [],
    transfer_decoder(),
  )
  |> result.map(fn(returned) { returned.rows })
}

pub fn transfer(
  connection: pog.Connection,
  id: Int,
) -> Result(Transfer, ApiError) {
  case
    repository.run(
      connection,
      "SELECT id, external_id, debit_account_id, credit_account_id, amount,
      created_at::text
    FROM transfers
    WHERE id = $1",
      [pog.int(id)],
      transfer_decoder(),
    )
  {
    Error(error) -> Error(error)
    Ok(returned) -> repository.first_or_not_found(returned)
  }
}

pub fn create_transfer(
  connection: pog.Connection,
  new_transfer: NewTransfer,
) -> Result(Transfer, ApiError) {
  case validate_transfer(new_transfer) {
    Error(error) -> Error(error)
    Ok(Nil) ->
      repository.with_transaction(connection, fn(transaction) {
        create_transfer_transaction(transaction, new_transfer)
      })
  }
}

fn create_transfer_transaction(
  connection: pog.Connection,
  new_transfer: NewTransfer,
) -> Result(Transfer, ApiError) {
  use locked_accounts <- result.try(repository.run(
    connection,
    "SELECT id, track_balance
    FROM accounts
    WHERE id IN ($1, $2)
    ORDER BY id
    FOR UPDATE",
    [
      pog.int(new_transfer.debit_account_id),
      pog.int(new_transfer.credit_account_id),
    ],
    account_lock_decoder(),
  ))
  let pog.Returned(_, accounts) = locked_accounts
  use debit_account <- result.try(find_locked_account(
    accounts,
    new_transfer.debit_account_id,
  ))
  use credit_account <- result.try(find_locked_account(
    accounts,
    new_transfer.credit_account_id,
  ))
  use debit_balance <- result.try(balance_for(connection, debit_account))
  use credit_balance <- result.try(balance_for(connection, credit_account))
  case debit_account.track_balance && debit_balance < new_transfer.amount {
    True -> Error(InsufficientFunds)
    False -> {
      use transfer <- result.try(insert_transfer(connection, new_transfer))
      use _ <- result.try(insert_entry(
        connection,
        transfer.id,
        new_transfer.debit_account_id,
        new_transfer.amount,
        True,
      ))
      use _ <- result.try(insert_entry(
        connection,
        transfer.id,
        new_transfer.credit_account_id,
        new_transfer.amount,
        False,
      ))
      use _ <- result.try(write_balance(
        connection,
        debit_account,
        debit_balance - new_transfer.amount,
      ))
      use _ <- result.try(write_balance(
        connection,
        credit_account,
        credit_balance + new_transfer.amount,
      ))
      Ok(transfer)
    }
  }
}

fn validate_transfer(transfer: NewTransfer) -> Result(Nil, ApiError) {
  let external_id = string.trim(transfer.external_id)
  case True {
    _ if external_id == "" ->
      Error(InvalidInput("external_id must not be empty"))
    _ if transfer.debit_account_id <= 0 || transfer.credit_account_id <= 0 ->
      Error(InvalidInput("account IDs must be positive"))
    _ if transfer.debit_account_id == transfer.credit_account_id ->
      Error(InvalidInput("debit and credit accounts must differ"))
    _ if transfer.amount <= 0 ->
      Error(InvalidInput("amount must be a positive integer number of cents"))
    _ -> Ok(Nil)
  }
}

fn insert_transfer(
  connection: pog.Connection,
  transfer: NewTransfer,
) -> Result(Transfer, ApiError) {
  case
    repository.run(
      connection,
      "INSERT INTO transfers (
      external_id, debit_account_id, credit_account_id, amount
    )
    VALUES ($1, $2, $3, $4)
    RETURNING id, external_id, debit_account_id, credit_account_id, amount,
      created_at::text",
      [
        pog.text(transfer.external_id),
        pog.int(transfer.debit_account_id),
        pog.int(transfer.credit_account_id),
        pog.int(transfer.amount),
      ],
      transfer_decoder(),
    )
  {
    Error(error) -> Error(error)
    Ok(returned) ->
      repository.first_or_database_error(
        returned,
        "Transfer insert returned no row",
      )
  }
}

fn insert_entry(
  connection: pog.Connection,
  transfer_id: Int,
  account_id: Int,
  amount: Int,
  debit: Bool,
) -> Result(Nil, ApiError) {
  repository.run(
    connection,
    "INSERT INTO entries (account_id, transfer_id, amount, debit)
    VALUES ($1, $2, $3, $4)",
    [
      pog.int(account_id),
      pog.int(transfer_id),
      pog.int(amount),
      pog.bool(debit),
    ],
    decode.success(Nil),
  )
  |> result.map(fn(_) { Nil })
}

fn write_balance(
  connection: pog.Connection,
  account: AccountLock,
  running_balance: Int,
) -> Result(Nil, ApiError) {
  case account.track_balance {
    False -> Ok(Nil)
    True ->
      repository.run(
        connection,
        "INSERT INTO account_balances (account_id, running_balance)
        VALUES ($1, $2)",
        [pog.int(account.id), pog.int(running_balance)],
        decode.success(Nil),
      )
      |> result.map(fn(_) { Nil })
  }
}

fn balance_for(
  connection: pog.Connection,
  account: AccountLock,
) -> Result(Int, ApiError) {
  case account.track_balance {
    False -> Ok(0)
    True ->
      case
        repository.run(
          connection,
          "SELECT running_balance
        FROM account_balances
        WHERE account_id = $1
        ORDER BY id DESC
        LIMIT 1",
          [pog.int(account.id)],
          int_row_decoder(),
        )
      {
        Error(error) -> Error(error)
        Ok(returned) ->
          repository.first_or_database_error(
            returned,
            "Tracked account has no balance snapshot",
          )
      }
  }
}

fn find_locked_account(
  accounts: List(AccountLock),
  id: Int,
) -> Result(AccountLock, ApiError) {
  case accounts {
    [account, ..remaining] ->
      case account.id == id {
        True -> Ok(account)
        False -> find_locked_account(remaining, id)
      }
    [] -> Error(InvalidInput("debit or credit account does not exist"))
  }
}

fn transfer_decoder() -> decode.Decoder(Transfer) {
  use id <- decode.field(0, decode.int)
  use external_id <- decode.field(1, decode.string)
  use debit_account_id <- decode.field(2, decode.int)
  use credit_account_id <- decode.field(3, decode.int)
  use amount <- decode.field(4, decode.int)
  use created_at <- decode.field(5, decode.string)
  decode.success(Transfer(
    id:,
    external_id:,
    debit_account_id:,
    credit_account_id:,
    amount:,
    created_at:,
  ))
}

fn account_lock_decoder() -> decode.Decoder(AccountLock) {
  use id <- decode.field(0, decode.int)
  use track_balance <- decode.field(1, decode.bool)
  decode.success(AccountLock(id:, track_balance:))
}

fn int_row_decoder() -> decode.Decoder(Int) {
  use value <- decode.field(0, decode.int)
  decode.success(value)
}
