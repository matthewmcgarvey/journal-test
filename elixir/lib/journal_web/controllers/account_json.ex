defmodule JournalWeb.AccountJSON do
  def index(accounts), do: Enum.map(accounts, &data/1)
  def show(account), do: data(account)

  defp data(%{account: account, current_balance: current_balance}) do
    %{
      id: account.id,
      external_id: account.external_id,
      track_balance: account.track_balance,
      current_balance: current_balance,
      created_at: account.inserted_at
    }
  end

  defp data(account) do
    %{
      id: account.id,
      external_id: account.external_id,
      track_balance: account.track_balance,
      current_balance: if(account.track_balance, do: 0, else: nil),
      created_at: account.inserted_at
    }
  end
end
