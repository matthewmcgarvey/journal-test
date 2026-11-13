require "test_helper"

class ImmutableRecordsTest < ActiveSupport::TestCase
  test "records cannot be changed through model methods" do
    account = Account.create!(external_id: "immutable-account")

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      account.update!(external_id: "changed-account")
    end
    assert_raises(ActiveRecord::ReadOnlyRecord) { account.destroy! }
  end

  test "database rejects direct updates to immutable records" do
    account = Account.create!(external_id: "database-immutable-account")

    assert_raises(ActiveRecord::StatementInvalid) do
      Account.where(id: account.id).update_all(external_id: "changed-in-database")
    end
  end

  test "database rejects balance snapshots for untracked accounts" do
    account = Account.create!(external_id: "no-balance-account", track_balance: false)

    assert_raises(ActiveRecord::StatementInvalid) do
      AccountBalance.create!(account:, running_balance: 0)
    end
  end
end
