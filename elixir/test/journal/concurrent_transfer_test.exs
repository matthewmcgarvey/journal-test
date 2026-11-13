defmodule Journal.ConcurrentTransferTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Journal.Accounting
  alias Journal.Accounting.Transfer
  alias Journal.Repo

  test "concurrent debits cannot overspend a tracked account" do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      Repo.query!(
        "TRUNCATE account_balances, entries, transfers, accounts RESTART IDENTITY CASCADE"
      )

      {:ok, source} = Accounting.create_account(%{external_id: "concurrent-source"})

      {:ok, root} =
        Accounting.create_account(%{external_id: "concurrent-root", track_balance: false})

      {:ok, destination} =
        Accounting.create_account(%{external_id: "concurrent-destination"})

      {:ok, _funding} =
        Accounting.create_transfer(%{
          external_id: "concurrent-funding",
          debit_account_id: root.id,
          credit_account_id: source.id,
          amount: 100
        })

      parent = self()

      tasks =
        Enum.map(1..2, fn index ->
          Task.async(fn ->
            :ok = Sandbox.checkout(Repo, sandbox: false)

            try do
              send(parent, {:ready, index})

              receive do
                :start -> :ok
              after
                5_000 -> raise "timed out waiting to start concurrent transfer"
              end

              Accounting.create_transfer(%{
                external_id: "concurrent-#{index}",
                debit_account_id: source.id,
                credit_account_id: destination.id,
                amount: 75
              })
            after
              Sandbox.checkin(Repo)
            end
          end)
        end)

      assert_receive {:ready, _index}, 5_000
      assert_receive {:ready, _index}, 5_000
      Enum.each(tasks, &send(&1.pid, :start))

      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, %Transfer{}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :insufficient_funds})) == 1
      assert %{account: ^source, current_balance: 25} = Accounting.get_account(source.id)
    after
      Repo.query!(
        "TRUNCATE account_balances, entries, transfers, accounts RESTART IDENTITY CASCADE"
      )

      Sandbox.checkin(Repo)
    end
  end
end
