defmodule Journal.Accounting.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "entries" do
    field :account_id, :id
    field :transfer_id, :id
    field :amount, :integer
    field :debit, :boolean

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:account_id, :transfer_id, :amount, :debit])
    |> validate_required([:account_id, :transfer_id, :amount, :debit])
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:transfer_id)
  end
end
