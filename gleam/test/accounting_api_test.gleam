import accounting_api/model
import gleam/json
import gleam/option.{None}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn account_creation_defaults_to_tracked_test() {
  let assert Ok(account) =
    json.parse("{\"external_id\":\"savings\"}", model.new_account_decoder())

  assert account.track_balance == True
}

pub fn untracked_account_serializes_null_balance_test() {
  let account =
    model.Account(
      id: 1,
      external_id: "source",
      track_balance: False,
      created_at: "2026-01-01 00:00:00+00",
      current_balance: None,
    )

  assert json.to_string(model.account_json(account))
    == "{\"id\":1,\"external_id\":\"source\",\"track_balance\":false,\"current_balance\":null,\"created_at\":\"2026-01-01 00:00:00+00\"}"
}

pub fn transfer_response_contains_no_entries_test() {
  let transfer =
    model.Transfer(
      id: 1,
      external_id: "payment-1",
      debit_account_id: 2,
      credit_account_id: 3,
      amount: 1099,
      created_at: "2026-01-01 00:00:00+00",
    )

  assert json.to_string(model.transfer_json(transfer))
    == "{\"id\":1,\"external_id\":\"payment-1\",\"debit_account_id\":2,\"credit_account_id\":3,\"amount\":1099,\"created_at\":\"2026-01-01 00:00:00+00\"}"
}
