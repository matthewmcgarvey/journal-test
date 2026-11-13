defmodule Journal.Repo.Migrations.CreateLedgerTables do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :external_id, :text, null: false
      add :track_balance, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:accounts, [:external_id])

    create table(:transfers) do
      add :external_id, :text, null: false
      add :debit_account_id, references(:accounts, on_delete: :restrict), null: false
      add :credit_account_id, references(:accounts, on_delete: :restrict), null: false
      add :amount, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:transfers, [:external_id])
    create constraint(:transfers, :transfers_amount_positive, check: "amount > 0")

    create constraint(:transfers, :transfers_accounts_differ,
             check: "debit_account_id <> credit_account_id"
           )

    create table(:entries) do
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :transfer_id, references(:transfers, on_delete: :restrict), null: false
      add :amount, :integer, null: false
      add :debit, :boolean, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:entries, [:account_id, :id])

    create unique_index(:entries, [:transfer_id],
             where: "debit",
             name: :entries_one_debit_per_transfer
           )

    create unique_index(:entries, [:transfer_id],
             where: "NOT debit",
             name: :entries_one_credit_per_transfer
           )

    create constraint(:entries, :entries_amount_positive, check: "amount > 0")

    create table(:account_balances) do
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :running_balance, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:account_balances, [:account_id, :id])

    execute(
      """
      CREATE FUNCTION reject_immutable_record_mutation() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'records are immutable'
          USING ERRCODE = '55000';
      END;
      $$ LANGUAGE plpgsql
      """,
      "DROP FUNCTION reject_immutable_record_mutation()"
    )

    for table <- ~w(accounts transfers entries account_balances) do
      execute(
        "CREATE TRIGGER #{table}_immutable BEFORE UPDATE OR DELETE ON #{table} " <>
          "FOR EACH ROW EXECUTE FUNCTION reject_immutable_record_mutation()",
        "DROP TRIGGER #{table}_immutable ON #{table}"
      )
    end
  end
end
