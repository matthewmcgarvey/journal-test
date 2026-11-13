defmodule JournalWeb.TransferControllerTest do
  use JournalWeb.ConnCase, async: false

  import Ecto.Query

  alias Journal.Accounting
  alias Journal.Accounting.{AccountBalance, Entry, Transfer}
  alias Journal.Repo

  test "creates an atomic transfer and snapshots only tracked accounts", %{conn: conn} do
    source = create_account(conn, "source", false)
    destination = create_account(conn, "destination", true)

    response =
      conn
      |> json_post(~p"/api/v1/transfers", %{
        transfer: %{
          external_id: "move-1",
          debit_account_id: source["id"],
          credit_account_id: destination["id"],
          amount: 1250
        }
      })
      |> json_response(201)

    assert response["amount"] == 1250
    refute Map.has_key?(response, "entries")

    assert [%{"running_balance" => 0}, %{"running_balance" => 1250}] =
             conn
             |> get(~p"/api/v1/account_balances?account_id=#{destination["id"]}")
             |> json_response(200)

    assert [] =
             conn
             |> get(~p"/api/v1/account_balances?account_id=#{source["id"]}")
             |> json_response(200)

    assert [%{amount: 1250, debit: true}, %{amount: 1250, debit: false}] =
             Repo.all(
               from(entry in Entry,
                 order_by: entry.id,
                 select: %{amount: entry.amount, debit: entry.debit}
               )
             )

    assert [%Transfer{}] = Repo.all(Transfer)
    assert Repo.aggregate(AccountBalance, :count) == 2
  end

  test "rejects insufficient funds without writing partial records", %{conn: conn} do
    source = create_account(conn, "tracked-source", true)
    destination = create_account(conn, "sink", false)

    assert %{"errors" => %{"detail" => "insufficient funds"}} =
             conn
             |> json_post(~p"/api/v1/transfers", %{
               transfer: %{
                 external_id: "too-large",
                 debit_account_id: source["id"],
                 credit_account_id: destination["id"],
                 amount: 1
               }
             })
             |> json_response(422)

    assert Repo.aggregate(Transfer, :count) == 0
    assert Repo.aggregate(Entry, :count) == 0
    assert Repo.aggregate(AccountBalance, :count) == 1
  end

  test "validates transfer data, missing accounts, and required request object", %{conn: conn} do
    source = create_account(conn, "source", false)
    destination = create_account(conn, "destination", true)

    assert %{"errors" => _} =
             conn
             |> json_post(~p"/api/v1/transfers", %{
               transfer: %{
                 external_id: "zero",
                 debit_account_id: source["id"],
                 credit_account_id: destination["id"],
                 amount: 0
               }
             })
             |> json_response(422)

    assert %{"errors" => _} =
             conn
             |> json_post(~p"/api/v1/transfers", %{
               transfer: %{
                 external_id: "missing-account",
                 debit_account_id: 999_999,
                 credit_account_id: destination["id"],
                 amount: 1
               }
             })
             |> json_response(422)

    assert %{"errors" => _} =
             conn
             |> json_post(~p"/api/v1/transfers", %{})
             |> json_response(400)
  end

  test "returns transfer index and show without exposing entries", %{conn: conn} do
    source = create_account(conn, "index-source", false)
    destination = create_account(conn, "index-destination", true)

    transfer =
      Accounting.create_transfer(%{
        external_id: "index-transfer",
        debit_account_id: source["id"],
        credit_account_id: destination["id"],
        amount: 1
      })
      |> elem(1)

    assert [%{"id" => transfer_id}] =
             conn
             |> get(~p"/api/v1/transfers")
             |> json_response(200)

    assert transfer_id == transfer.id

    assert %{"id" => ^transfer_id} =
             conn
             |> get(~p"/api/v1/transfers/#{transfer_id}")
             |> json_response(200)

    assert %{"errors" => %{"detail" => "transfer not found"}} =
             conn
             |> get(~p"/api/v1/transfers/999999")
             |> json_response(404)
  end

  test "concurrent transfers cannot overspend a tracked debit account" do
    {:ok, source} = Accounting.create_account(%{external_id: "concurrent-source"})

    {:ok, root} =
      Accounting.create_account(%{external_id: "concurrent-root", track_balance: false})

    {:ok, destination} = Accounting.create_account(%{external_id: "concurrent-destination"})

    {:ok, _funding} =
      Accounting.create_transfer(%{
        external_id: "concurrent-funding",
        debit_account_id: root.id,
        credit_account_id: source.id,
        amount: 100
      })

    results =
      Task.async_stream(
        1..2,
        fn index ->
          Accounting.create_transfer(%{
            external_id: "concurrent-#{index}",
            debit_account_id: source.id,
            credit_account_id: destination.id,
            amount: 75
          })
        end,
        max_concurrency: 2,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, %Transfer{}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :insufficient_funds})) == 1

    assert %{account: ^source, current_balance: 25} = Accounting.get_account(source.id)
  end

  defp create_account(conn, external_id, track_balance) do
    conn
    |> json_post(~p"/api/v1/accounts", %{
      account: %{external_id: external_id, track_balance: track_balance}
    })
    |> json_response(201)
  end

  defp json_post(conn, path, body) do
    conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end
end
