require "test_helper"

class AccountsTest < ActionDispatch::IntegrationTest
  test "creates a tracked account with a zero balance" do
    post "/api/v1/accounts", params: {
      account: { external_id: "tracked-account" }
    }, as: :json

    assert_response :created
    account = JSON.parse(response.body)
    assert_equal true, account["track_balance"]
    assert_equal 0, account["current_balance"]
    assert_equal 0, AccountBalance.find_by!(account_id: account["id"]).running_balance
  end

  test "creates an untracked account without a balance snapshot" do
    post "/api/v1/accounts", params: {
      account: { external_id: "untracked-account", track_balance: false }
    }, as: :json

    assert_response :created
    account = JSON.parse(response.body)
    assert_equal false, account["track_balance"]
    assert_nil account["current_balance"]
    assert_not AccountBalance.exists?(account_id: account["id"])
  end

  test "account index and show include current balance" do
    post "/api/v1/accounts", params: {
      account: { external_id: "shown-account" }
    }, as: :json
    account = JSON.parse(response.body)

    get "/api/v1/accounts"
    assert_response :success
    assert_equal 0, JSON.parse(response.body).find { |record| record["id"] == account["id"] }["current_balance"]

    get "/api/v1/accounts/#{account["id"]}"
    assert_response :success
    assert_equal 0, JSON.parse(response.body)["current_balance"]
  end

  test "duplicate external IDs are rejected" do
    Account.create!(external_id: "duplicate-account")

    assert_no_difference "Account.count" do
      post "/api/v1/accounts", params: {
        account: { external_id: "duplicate-account" }
      }, as: :json
    end

    assert_response :unprocessable_entity
    assert JSON.parse(response.body).key?("errors")
  end
end
