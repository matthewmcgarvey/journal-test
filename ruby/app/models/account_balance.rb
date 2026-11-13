class AccountBalance < ApplicationRecord
  include ImmutableRecord

  belongs_to :account, inverse_of: :account_balances

  validates :running_balance, numericality: { only_integer: true }
end
