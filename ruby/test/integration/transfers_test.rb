require "test_helper"

class TransfersTest < ActionDispatch::IntegrationTest
  test "creates entries and snapshots for a transfer from an untracked source" do
    source = Account.create!(external_id: "root-source", track_balance: false)
    destination = Account.create!(external_id: "funded-account")

    post "/api/v1/transfers", params: {
      transfer: {
        external_id: "root-funding",
        debit_account_id: source.id,
        credit_account_id: destination.id,
        amount: 1250
      }
    }, as: :json

    assert_response :created
    transfer = JSON.parse(response.body)
    assert_equal 1250, transfer["amount"]
    assert_not transfer.key?("entries")
    assert_equal 2, Entry.where(transfer_id: transfer["id"]).count
    assert Entry.exists?(transfer_id: transfer["id"], account_id: source.id, debit: true, amount: 1250)
    assert Entry.exists?(
      transfer_id: transfer["id"], account_id: destination.id, debit: false, amount: 1250
    )
    assert_equal [ 0, 1250 ], destination.account_balances.order(:id).pluck(:running_balance)
    assert_not AccountBalance.exists?(account_id: source.id)

    get "/api/v1/transfers/#{transfer["id"]}"
    assert_response :success
    assert_equal transfer["id"], JSON.parse(response.body)["id"]

    get "/api/v1/transfers"
    assert_response :success
    assert_equal [ transfer["id"] ], JSON.parse(response.body).map { |record| record["id"] }
  end

  test "tracked debit accounts cannot overspend and failures are atomic" do
    source = Account.create!(external_id: "funding-source", track_balance: false)
    debit_account = Account.create!(external_id: "limited-account")
    credit_account = Account.create!(external_id: "credit-account")
    Transfers::Create.new(
      external_id: "initial-funding",
      debit_account_id: source.id,
      credit_account_id: debit_account.id,
      amount: 1000
    ).call

    counts_before = [ Transfer.count, Entry.count, AccountBalance.count ]
    post "/api/v1/transfers", params: {
      transfer: {
        external_id: "overspend",
        debit_account_id: debit_account.id,
        credit_account_id: credit_account.id,
        amount: 1001
      }
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal counts_before, [ Transfer.count, Entry.count, AccountBalance.count ]
    assert_equal 1000, debit_account.reload.current_balance
  end

  test "rejects a transfer to the same account" do
    account = Account.create!(external_id: "self-transfer-account")

    assert_no_difference "Transfer.count" do
      post "/api/v1/transfers", params: {
        transfer: {
          external_id: "self-transfer",
          debit_account_id: account.id,
          credit_account_id: account.id,
          amount: 1
        }
      }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "records entries but no snapshots when both accounts are untracked" do
    debit_account = Account.create!(external_id: "untracked-debit", track_balance: false)
    credit_account = Account.create!(external_id: "untracked-credit", track_balance: false)

    post "/api/v1/transfers", params: {
      transfer: {
        external_id: "untracked-transfer",
        debit_account_id: debit_account.id,
        credit_account_id: credit_account.id,
        amount: 50
      }
    }, as: :json

    assert_response :created
    transfer_id = JSON.parse(response.body).fetch("id")
    assert_equal 2, Entry.where(transfer_id: transfer_id).count
    assert_empty AccountBalance.where(account_id: [ debit_account.id, credit_account.id ])
  end
end
