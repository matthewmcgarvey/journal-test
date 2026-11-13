import accounting_domain/model.{
  type Account, type DomainError, type NewAccount, Account, Database,
  InvalidInput,
}
import accounting_domain/repository
import gleam/dynamic/decode
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pog

pub fn accounts(
  connection: pog.Connection,
) -> Result(List(Account), DomainError) {
  repository.run(
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
) -> Result(Account, DomainError) {
  case
    repository.run(
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
    Ok(returned) -> repository.first_or_not_found(returned)
  }
}

pub fn create_account(
  connection: pog.Connection,
  new_account: NewAccount,
) -> Result(Account, DomainError) {
  case string.trim(new_account.external_id) {
    "" -> Error(InvalidInput("external_id must not be empty"))
    _ ->
      repository.with_transaction(connection, fn(transaction) {
        case
          repository.run(
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
                  repository.run(
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
