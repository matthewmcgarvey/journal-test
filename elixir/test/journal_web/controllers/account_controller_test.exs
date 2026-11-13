defmodule JournalWeb.AccountControllerTest do
  use JournalWeb.ConnCase, async: true

  alias Journal.Accounting.Account
  alias Journal.Repo

  test "creates tracked and untracked accounts with the correct balance", %{conn: conn} do
    tracked = create_account(conn, "tracked", true)
    untracked = create_account(conn, "untracked", false)

    assert tracked["track_balance"]
    assert tracked["current_balance"] == 0
    refute untracked["track_balance"]
    assert is_nil(untracked["current_balance"])

    assert %{"current_balance" => 0} =
             conn
             |> get(~p"/api/v1/accounts/#{tracked["id"]}")
             |> json_response(200)
  end

  test "lists accounts and returns 404 for a missing account", %{conn: conn} do
    create_account(conn, "listed", true)

    assert [%{"external_id" => "listed", "current_balance" => 0}] =
             conn
             |> get(~p"/api/v1/accounts")
             |> json_response(200)

    assert %{"errors" => %{"detail" => "account not found"}} =
             conn
             |> get(~p"/api/v1/accounts/999999")
             |> json_response(404)
  end

  test "requires an account object and reports duplicate external IDs as conflicts", %{
    conn: conn
  } do
    assert %{"errors" => %{"detail" => message}} =
             conn
             |> json_post(~p"/api/v1/accounts", %{})
             |> json_response(400)

    assert message =~ "account"

    create_account(conn, "duplicate", true)

    assert %{"errors" => _} =
             conn
             |> json_post(~p"/api/v1/accounts", %{account: %{external_id: "duplicate"}})
             |> json_response(409)
  end

  test "the database rejects account updates", %{conn: conn} do
    account = create_account(conn, "immutable", true)

    assert_raise Postgrex.Error, fn ->
      Repo.query!("UPDATE accounts SET external_id = $1 WHERE id = $2", [
        "changed",
        account["id"]
      ])
    end

    assert %Account{external_id: "immutable"} = Repo.get!(Account, account["id"])
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
