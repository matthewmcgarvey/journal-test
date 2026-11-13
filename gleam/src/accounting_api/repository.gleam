import accounting_api/model.{
  type Account, type AccountBalance, type ApiError, type NewAccount,
  type NewTransfer, type Transfer, Account, AccountBalance, Conflict, Database,
  InsufficientFunds, InvalidInput, NotFound, Transfer,
}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pog

type AccountLock {
  AccountLock(id: Int, track_balance: Bool)
}

pub fn accounts(connection: pog.Connection) -> Result(List(Account), ApiError) {
  run(
    connection,
    "SELECT a.id, a.external_id, a.track_balance, a.created_at::text,
      latest.running_balance
    FROM accounts AS a
    LEFT JOIN LATERAL (
      SELECT running_balance
      FROM account_balances
      WHERE account_id = a.id
      ORDER BY id DESC
      LIMIT 1
    ) AS latest ON TRUE
    ORDER BY a.id",
    [],
    account_decoder(),
  )
  |> result.map(fn(returned) { returned.rows })
}

pub fn account(
  connection: pog.Connection,
  id: Int,
) -> Result(Account, ApiError) {
  case
    run(
      connection,
      "SELECT a.id, a.external_id, a.track_balance, a.created_at::text,
      latest.running_balance
    FROM accounts AS a
    LEFT JOIN LATERAL (
      SELECT running_balance
      FROM account_balances
      WHERE account_id = a.id
      ORDER BY id DESC
      LIMIT 1
    ) AS latest ON TRUE
    WHERE a.id = $1",
      [pog.int(id)],
      account_decoder(),
    )
  {
    Error(error) -> Error(error)
    Ok(returned) -> first_or_not_found(returned)
  }
}

pub fn create_account(
  connection: pog.Connection,
  new_account: NewAccount,
) -> Result(Account, ApiError) {
  case string.trim(new_account.external_id) {
    "" -> Error(InvalidInput("external_id must not be empty"))
    _ ->
      with_transaction(connection, fn(transaction) {
        case
          run(
            transaction,
            "INSERT INTO accounts (external_id, track_balance)
          VALUES ($1, $2)
          RETURNING id, external_id, track_balance, created_at::text",
            [
              pog.text(new_account.external_id),
              pog.bool(new_account.track_balance),
            ],
            account_record_decoder(),
          )
        {
          Error(error) -> Error(error)
          Ok(pog.Returned(_, [created])) ->
            case new_account.track_balance {
              False -> Ok(created)
              True ->
                case
                  run(
                    transaction,
                    "INSERT INTO account_balances (account_id, running_balance)
                  VALUES ($1, 0)",
                    [pog.int(created.id)],
                    decode.success(Nil),
                  )
                {
                  Error(error) -> Error(error)
                  Ok(_) -> Ok(Account(..created, current_balance: Some(0)))
                }
            }
          Ok(_) -> Error(Database("Account insert returned no row"))
        }
      })
  }
}

pub fn transfers(
  connection: pog.Connection,
) -> Result(List(Transfer), ApiError) {
  run(
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
    run(
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
    Ok(returned) -> first_or_not_found(returned)
  }
}

pub fn create_transfer(
  connection: pog.Connection,
  new_transfer: NewTransfer,
) -> Result(Transfer, ApiError) {
  case validate_transfer(new_transfer) {
    Error(error) -> Error(error)
    Ok(Nil) ->
      with_transaction(connection, fn(transaction) {
        create_transfer_transaction(transaction, new_transfer)
      })
  }
}

pub fn account_balances(
  connection: pog.Connection,
) -> Result(List(AccountBalance), ApiError) {
  run(
    connection,
    "SELECT id, account_id, running_balance, created_at::text
    FROM account_balances
    ORDER BY id",
    [],
    account_balance_decoder(),
  )
  |> result.map(fn(returned) { returned.rows })
}

fn create_transfer_transaction(
  connection: pog.Connection,
  new_transfer: NewTransfer,
) -> Result(Transfer, ApiError) {
  use locked_accounts <- result.try(run(
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
    run(
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
      first_or_database_error(returned, "Transfer insert returned no row")
  }
}

fn insert_entry(
  connection: pog.Connection,
  transfer_id: Int,
  account_id: Int,
  amount: Int,
  debit: Bool,
) -> Result(Nil, ApiError) {
  run(
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
      run(
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
        run(
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
          first_or_database_error(
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

fn account_record_decoder() -> decode.Decoder(Account) {
  use id <- decode.field(0, decode.int)
  use external_id <- decode.field(1, decode.string)
  use track_balance <- decode.field(2, decode.bool)
  use created_at <- decode.field(3, decode.string)
  decode.success(Account(
    id:,
    external_id:,
    track_balance:,
    created_at:,
    current_balance: None,
  ))
}

fn account_decoder() -> decode.Decoder(Account) {
  use id <- decode.field(0, decode.int)
  use external_id <- decode.field(1, decode.string)
  use track_balance <- decode.field(2, decode.bool)
  use created_at <- decode.field(3, decode.string)
  use current_balance <- decode.field(4, decode.optional(decode.int))
  decode.success(Account(
    id:,
    external_id:,
    track_balance:,
    created_at:,
    current_balance:,
  ))
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

fn account_balance_decoder() -> decode.Decoder(AccountBalance) {
  use id <- decode.field(0, decode.int)
  use account_id <- decode.field(1, decode.int)
  use running_balance <- decode.field(2, decode.int)
  use created_at <- decode.field(3, decode.string)
  decode.success(AccountBalance(id:, account_id:, running_balance:, created_at:))
}

fn int_row_decoder() -> decode.Decoder(Int) {
  use value <- decode.field(0, decode.int)
  decode.success(value)
}

fn first_or_not_found(returned: pog.Returned(a)) -> Result(a, ApiError) {
  case returned.rows {
    [row, ..] -> Ok(row)
    [] -> Error(NotFound)
  }
}

fn first_or_database_error(
  returned: pog.Returned(a),
  message: String,
) -> Result(a, ApiError) {
  case returned.rows {
    [row, ..] -> Ok(row)
    [] -> Error(Database(message))
  }
}

fn with_transaction(
  connection: pog.Connection,
  callback: fn(pog.Connection) -> Result(a, ApiError),
) -> Result(a, ApiError) {
  case pog.transaction(connection, callback) {
    Ok(value) -> Ok(value)
    Error(pog.TransactionRolledBack(error)) -> Error(error)
    Error(pog.TransactionQueryError(error)) -> Error(query_error(error))
  }
}

fn run(
  connection: pog.Connection,
  sql: String,
  parameters: List(pog.Value),
  decoder: decode.Decoder(a),
) -> Result(pog.Returned(a), ApiError) {
  let query =
    list.fold(parameters, pog.query(sql), fn(query, parameter) {
      pog.parameter(query, parameter)
    })
    |> pog.returning(decoder)
  pog.execute(query, on: connection)
  |> result.map_error(query_error)
}

fn query_error(error: pog.QueryError) -> ApiError {
  case error {
    pog.ConstraintViolated(_, "accounts_external_id_key", _) -> Conflict
    pog.ConstraintViolated(_, "transfers_external_id_key", _) -> Conflict
    pog.ConstraintViolated(_, _, _) ->
      InvalidInput("a database constraint was violated")
    pog.PostgresqlError("23505", _, _) -> Conflict
    pog.PostgresqlError("23503", _, _) ->
      InvalidInput("an account reference does not exist")
    pog.PostgresqlError("23514", _, _) ->
      InvalidInput("a database constraint was violated")
    pog.PostgresqlError("23502", _, _) ->
      InvalidInput("a required field is missing")
    _ -> Database(string.inspect(error))
  }
}
