defmodule Journal.Accounting.Transfer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transfers" do
    field :external_id, :string
    field :debit_account_id, :id
    field :credit_account_id, :id
    field :amount, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(transfer, attrs) do
    transfer
    |> cast(attrs, [:external_id, :debit_account_id, :credit_account_id, :amount])
    |> validate_required([
      :external_id,
      :debit_account_id,
      :credit_account_id,
      :amount
    ])
    |> validate_length(:external_id, min: 1)
    |> validate_number(:amount, greater_than: 0)
    |> validate_distinct_accounts()
    |> unique_constraint(:external_id)
    |> foreign_key_constraint(:debit_account_id)
    |> foreign_key_constraint(:credit_account_id)
  end

  defp validate_distinct_accounts(changeset) do
    debit_account_id = get_field(changeset, :debit_account_id)
    credit_account_id = get_field(changeset, :credit_account_id)

    if debit_account_id && debit_account_id == credit_account_id do
      add_error(changeset, :credit_account_id, "must differ from debit_account_id")
    else
      changeset
    end
  end
end
