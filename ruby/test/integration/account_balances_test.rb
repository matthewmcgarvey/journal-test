require "test_helper"

class AccountBalancesTest < ActionDispatch::IntegrationTest
  test "index returns immutable balance snapshots" do
    account = Account.create!(external_id: "snapshot-account")
    AccountBalance.create!(account:, running_balance: 125)

    get "/api/v1/account_balances"

    assert_response :success
    balances = JSON.parse(response.body)
    assert_equal [ 0, 125 ], balances.select { |balance| balance["account_id"] == account.id }
      .map { |balance| balance["running_balance"] }
  end

  test "entries have no API endpoint" do
    get "/api/v1/entries"

    assert_response :not_found
  end
end
