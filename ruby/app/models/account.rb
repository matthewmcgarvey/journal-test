class Account < ApplicationRecord
  include ImmutableRecord

  has_many :account_balances, inverse_of: :account
  has_one :current_balance_snapshot, -> { order(id: :desc) },
    class_name: "AccountBalance", inverse_of: :account
  has_many :entries, inverse_of: :account
  has_many :debit_transfers, class_name: "Transfer", foreign_key: :debit_account_id,
    inverse_of: :debit_account
  has_many :credit_transfers, class_name: "Transfer", foreign_key: :credit_account_id,
    inverse_of: :credit_account

  validates :external_id, presence: true, uniqueness: true
  validates :track_balance, inclusion: { in: [ true, false ] }

  after_create :create_initial_balance_snapshot, if: :track_balance?

  def current_balance
    return unless track_balance?

    current_balance_snapshot&.running_balance ||
      raise("Tracked account #{id} has no balance snapshot")
  end

  private

  def create_initial_balance_snapshot
    account_balances.create!(running_balance: 0)
  end
end
