defmodule Journal.Repo.Migrations.RequireNonnegativeBalances do
  use Ecto.Migration

  def change do
    create constraint(:account_balances, :account_balances_running_balance_nonnegative,
             check: "running_balance >= 0"
           )
  end
end
