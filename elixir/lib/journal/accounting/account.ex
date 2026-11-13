defmodule Journal.Accounting.Account do
  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :external_id, :string
    field :track_balance, :boolean, default: true

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:external_id, :track_balance])
    |> validate_required([:external_id, :track_balance])
    |> validate_length(:external_id, min: 1)
    |> unique_constraint(:external_id)
  end
end
