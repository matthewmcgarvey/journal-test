import accounting_api/model.{type AccountBalance, type ApiError, AccountBalance}
import accounting_api/repository
import gleam/dynamic/decode
import gleam/result
import pog

pub fn account_balances(
  connection: pog.Connection,
) -> Result(List(AccountBalance), ApiError) {
  repository.run(
    connection,
    "SELECT id, account_id, running_balance, created_at::text
    FROM account_balances
    ORDER BY id",
    [],
    account_balance_decoder(),
  )
  |> result.map(fn(returned) { returned.rows })
}

fn account_balance_decoder() -> decode.Decoder(AccountBalance) {
  use id <- decode.field(0, decode.int)
  use account_id <- decode.field(1, decode.int)
  use running_balance <- decode.field(2, decode.int)
  use created_at <- decode.field(3, decode.string)
  decode.success(AccountBalance(id:, account_id:, running_balance:, created_at:))
}
