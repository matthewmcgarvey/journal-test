import accounting_domain/model.{
  type Account, type AccountBalance, type NewAccount, type NewTransfer,
  type Transfer, NewAccount, NewTransfer,
}
import gleam/dynamic/decode
import gleam/json

pub fn new_account_decoder() -> decode.Decoder(NewAccount) {
  use external_id <- decode.field("external_id", decode.string)
  use track_balance <- decode.optional_field("track_balance", True, decode.bool)
  decode.success(NewAccount(external_id:, track_balance:))
}

pub fn new_transfer_decoder() -> decode.Decoder(NewTransfer) {
  use external_id <- decode.field("external_id", decode.string)
  use debit_account_id <- decode.field("debit_account_id", decode.int)
  use credit_account_id <- decode.field("credit_account_id", decode.int)
  use amount <- decode.field("amount", decode.int)
  decode.success(NewTransfer(
    external_id:,
    debit_account_id:,
    credit_account_id:,
    amount:,
  ))
}

pub fn account_json(account: Account) -> json.Json {
  json.object([
    #("id", json.int(account.id)),
    #("external_id", json.string(account.external_id)),
    #("track_balance", json.bool(account.track_balance)),
    #("current_balance", json.nullable(account.current_balance, of: json.int)),
    #("created_at", json.string(account.created_at)),
  ])
}

pub fn transfer_json(transfer: Transfer) -> json.Json {
  json.object([
    #("id", json.int(transfer.id)),
    #("external_id", json.string(transfer.external_id)),
    #("debit_account_id", json.int(transfer.debit_account_id)),
    #("credit_account_id", json.int(transfer.credit_account_id)),
    #("amount", json.int(transfer.amount)),
    #("created_at", json.string(transfer.created_at)),
  ])
}

pub fn account_balance_json(balance: AccountBalance) -> json.Json {
  json.object([
    #("id", json.int(balance.id)),
    #("account_id", json.int(balance.account_id)),
    #("running_balance", json.int(balance.running_balance)),
    #("created_at", json.string(balance.created_at)),
  ])
}
