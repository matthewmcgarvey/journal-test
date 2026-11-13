import gleam/option.{type Option}

pub type Account {
  Account(
    id: Int,
    external_id: String,
    track_balance: Bool,
    created_at: String,
    current_balance: Option(Int),
  )
}

pub type Transfer {
  Transfer(
    id: Int,
    external_id: String,
    debit_account_id: Int,
    credit_account_id: Int,
    amount: Int,
    created_at: String,
  )
}

pub type AccountBalance {
  AccountBalance(
    id: Int,
    account_id: Int,
    running_balance: Int,
    created_at: String,
  )
}

pub type NewAccount {
  NewAccount(external_id: String, track_balance: Bool)
}

pub type NewTransfer {
  NewTransfer(
    external_id: String,
    debit_account_id: Int,
    credit_account_id: Int,
    amount: Int,
  )
}

pub type DomainError {
  InvalidInput(String)
  NotFound
  Conflict
  InsufficientFunds
  Database(String)
}
