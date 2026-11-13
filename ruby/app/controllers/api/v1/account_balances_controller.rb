module Api
  module V1
    class AccountBalancesController < ApplicationController
      def index
        balances = AccountBalance.order(:id)
        render json: balances.map { |balance| balance_json(balance) }
      end

      private

      def balance_json(balance)
        {
          id: balance.id,
          account_id: balance.account_id,
          running_balance: balance.running_balance,
          created_at: balance.created_at
        }
      end
    end
  end
end
