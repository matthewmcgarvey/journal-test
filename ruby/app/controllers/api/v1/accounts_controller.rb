module Api
  module V1
    class AccountsController < ApplicationController
      def index
        accounts = Account.includes(:current_balance_snapshot).order(:id)
        render json: accounts.map { |account| account_json(account) }
      end

      def show
        render json: account_json(Account.includes(:current_balance_snapshot).find(params[:id]))
      end

      def create
        account = Account.create!(account_params)
        render json: account_json(account), status: :created
      end

      private

      def account_params
        params.require(:account).permit(:external_id, :track_balance)
      end

      def account_json(account)
        {
          id: account.id,
          external_id: account.external_id,
          track_balance: account.track_balance,
          current_balance: account.current_balance,
          created_at: account.created_at
        }
      end
    end
  end
end
