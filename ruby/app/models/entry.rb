class Entry < ApplicationRecord
  include ImmutableRecord

  belongs_to :account, inverse_of: :entries
  belongs_to :transfer, inverse_of: :entries

  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :debit, inclusion: { in: [ true, false ] }
end
