module Api
  module V1
    class TransfersController < ApplicationController
      rescue_from Transfers::Create::InsufficientFunds do
        render json: { error: "Debit account has insufficient funds" },
          status: :unprocessable_entity
      end

      def index
        render json: Transfer.order(:id).map { |transfer| transfer_json(transfer) }
      end

      def show
        render json: transfer_json(Transfer.find(params[:id]))
      end

      def create
        transfer = Transfers::Create.new(transfer_params).call
        render json: transfer_json(transfer), status: :created
      end

      private

      def transfer_params
        params.require(:transfer).permit(
          :external_id,
          :debit_account_id,
          :credit_account_id,
          :amount
        )
      end

      def transfer_json(transfer)
        {
          id: transfer.id,
          external_id: transfer.external_id,
          debit_account_id: transfer.debit_account_id,
          credit_account_id: transfer.credit_account_id,
          amount: transfer.amount,
          created_at: transfer.created_at
        }
      end
    end
  end
end
