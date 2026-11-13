module Transfers
  class Create
    class InsufficientFunds < StandardError; end

    def initialize(attributes)
      @attributes = attributes
    end

    def call
      transfer = Transfer.new(@attributes)
      raise ActiveRecord::RecordInvalid, transfer unless transfer.valid?

      Account.transaction do
        accounts = Account.where(id: [ transfer.debit_account_id, transfer.credit_account_id ])
          .order(:id)
          .lock
          .to_a
        raise ActiveRecord::RecordNotFound unless accounts.length == 2

        accounts_by_id = accounts.index_by(&:id)
        debit_account = accounts_by_id.fetch(transfer.debit_account_id)
        credit_account = accounts_by_id.fetch(transfer.credit_account_id)

        if debit_account.track_balance? && debit_account.current_balance < transfer.amount
          raise InsufficientFunds, "Debit account has insufficient funds"
        end

        transfer.debit_account = debit_account
        transfer.credit_account = credit_account
        transfer.save!

        entries = [
          Entry.create!(account: debit_account, transfer:, amount: transfer.amount, debit: true),
          Entry.create!(account: credit_account, transfer:, amount: transfer.amount, debit: false)
        ]

        entries.each do |entry|
          account = entry.account
          next unless account.track_balance?

          balance_change = entry.debit? ? -entry.amount : entry.amount
          AccountBalance.create!(
            account:,
            running_balance: account.current_balance + balance_change
          )
        end

        transfer
      end
    end
  end
end
