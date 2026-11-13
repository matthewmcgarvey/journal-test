class CreateJournalSchema < ActiveRecord::Migration[8.1]
  IMMUTABLE_TABLES = %w[accounts transfers entries account_balances].freeze

  def up
    create_table :accounts, id: :integer do |t|
      t.string :external_id, null: false
      t.boolean :track_balance, null: false, default: true
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :accounts, :external_id, unique: true

    create_table :transfers, id: :integer do |t|
      t.string :external_id, null: false
      t.references :debit_account, null: false, type: :integer, foreign_key: { to_table: :accounts }
      t.references :credit_account, null: false, type: :integer, foreign_key: { to_table: :accounts }
      t.integer :amount, null: false
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :transfers, :external_id, unique: true
    add_check_constraint :transfers, "amount > 0", name: "transfers_amount_positive"
    add_check_constraint :transfers,
      "debit_account_id <> credit_account_id",
      name: "transfers_accounts_differ"

    create_table :entries, id: :integer do |t|
      t.references :account, null: false, type: :integer, foreign_key: true
      t.references :transfer, null: false, type: :integer, foreign_key: true
      t.integer :amount, null: false
      t.boolean :debit, null: false
    end
    add_index :entries, [ :transfer_id, :account_id ], unique: true
    add_check_constraint :entries, "amount > 0", name: "entries_amount_positive"

    create_table :account_balances, id: :integer do |t|
      t.references :account, null: false, type: :integer, index: false, foreign_key: true
      t.integer :running_balance, null: false
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :account_balances, [ :account_id, :id ]

    execute <<~SQL
      CREATE FUNCTION prevent_immutable_record_mutation() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION '% records are immutable', TG_TABLE_NAME
          USING ERRCODE = '55000';
      END;
      $$ LANGUAGE plpgsql;
    SQL

    IMMUTABLE_TABLES.each do |table|
      execute <<~SQL
        CREATE TRIGGER prevent_immutable_record_mutation
        BEFORE UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION prevent_immutable_record_mutation();
      SQL
    end

    execute <<~SQL
      CREATE FUNCTION require_tracked_account_for_balance() RETURNS trigger AS $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM accounts WHERE id = NEW.account_id AND track_balance
        ) THEN
          RAISE EXCEPTION 'Cannot record a balance for an untracked account'
            USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER require_tracked_account_for_balance
      BEFORE INSERT ON account_balances
      FOR EACH ROW EXECUTE FUNCTION require_tracked_account_for_balance();
    SQL
  end

  def down
    execute "DROP TRIGGER require_tracked_account_for_balance ON account_balances"
    execute "DROP FUNCTION require_tracked_account_for_balance()"
    IMMUTABLE_TABLES.each do |table|
      execute "DROP TRIGGER prevent_immutable_record_mutation ON #{table}"
    end
    execute "DROP FUNCTION prevent_immutable_record_mutation()"

    drop_table :account_balances
    drop_table :entries
    drop_table :transfers
    drop_table :accounts
  end
end
