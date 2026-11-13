class Transfer < ApplicationRecord
  include ImmutableRecord

  belongs_to :debit_account, class_name: "Account", inverse_of: :debit_transfers
  belongs_to :credit_account, class_name: "Account", inverse_of: :credit_transfers
  has_many :entries, inverse_of: :transfer

  validates :external_id, presence: true, uniqueness: true
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validate :accounts_must_differ

  private

  def accounts_must_differ
    return if debit_account_id.blank? || credit_account_id.blank?
    return unless debit_account_id == credit_account_id

    errors.add(:credit_account_id, "must differ from debit_account_id")
  end
end
