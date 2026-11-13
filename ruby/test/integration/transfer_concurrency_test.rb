require "test_helper"

class TransferConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    clear_records
  end

  teardown do
    clear_records
  end

  test "concurrent transfers cannot overspend a tracked account" do
    source = Account.create!(external_id: "concurrent-source", track_balance: false)
    tracked_account = Account.create!(external_id: "concurrent-tracked")
    destination = Account.create!(external_id: "concurrent-destination", track_balance: false)
    Transfers::Create.new(
      external_id: "concurrent-funding",
      debit_account_id: source.id,
      credit_account_id: tracked_account.id,
      amount: 1000
    ).call

    start = Queue.new
    results = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            start.pop
            Transfers::Create.new(
              external_id: "concurrent-spend-#{index}",
              debit_account_id: tracked_account.id,
              credit_account_id: destination.id,
              amount: 700
            ).call
            :created
          rescue Transfers::Create::InsufficientFunds
            :insufficient_funds
          end
        end
      end
    end

    results.length.times { start << true }
    outcomes = results.map(&:value)

    assert_equal 1, outcomes.count(:created)
    assert_equal 1, outcomes.count(:insufficient_funds)
    assert_equal 300, tracked_account.reload.current_balance
    assert_equal 2, Transfer.count
    assert_equal 4, Entry.count
  end

  private

  def clear_records
    ActiveRecord::Base.connection.execute(
      "TRUNCATE TABLE account_balances, entries, transfers, accounts RESTART IDENTITY CASCADE"
    )
  end
end
