defmodule Journal.Accounting.AccountBalance do
  use Ecto.Schema
  import Ecto.Changeset

  schema "account_balances" do
    field :account_id, :id
    field :running_balance, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(account_balance, attrs) do
    account_balance
    |> cast(attrs, [:account_id, :running_balance])
    |> validate_required([:account_id, :running_balance])
    |> foreign_key_constraint(:account_id)
  end
end
