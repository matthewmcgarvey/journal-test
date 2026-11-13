defmodule JournalWeb.AccountBalanceJSON do
  alias Journal.Accounting.AccountBalance

  def index(balances), do: Enum.map(balances, &data/1)

  defp data(%AccountBalance{} = balance) do
    %{
      id: balance.id,
      account_id: balance.account_id,
      running_balance: balance.running_balance,
      created_at: balance.inserted_at
    }
  end
end
