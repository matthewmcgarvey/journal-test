defmodule JournalWeb.AccountBalanceController do
  use JournalWeb, :controller

  alias Journal.Accounting
  alias JournalWeb.{AccountBalanceJSON, ErrorResponse}

  def index(conn, params) do
    case Map.fetch(params, "account_id") do
      :error ->
        json(conn, AccountBalanceJSON.index(Accounting.list_account_balances()))

      {:ok, account_id} ->
        case parse_id(account_id) do
          {:ok, id} ->
            json(conn, AccountBalanceJSON.index(Accounting.list_account_balances(id)))

          :error ->
            ErrorResponse.detail(
              conn,
              :unprocessable_entity,
              "account_id must be a positive integer"
            )
        end
    end
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> :error
    end
  end
end
