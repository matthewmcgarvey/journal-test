defmodule JournalWeb.TransferJSON do
  alias Journal.Accounting.Transfer

  def index(transfers), do: Enum.map(transfers, &data/1)
  def show(%Transfer{} = transfer), do: data(transfer)

  defp data(%Transfer{} = transfer) do
    %{
      id: transfer.id,
      external_id: transfer.external_id,
      debit_account_id: transfer.debit_account_id,
      credit_account_id: transfer.credit_account_id,
      amount: transfer.amount,
      created_at: transfer.inserted_at
    }
  end
end
