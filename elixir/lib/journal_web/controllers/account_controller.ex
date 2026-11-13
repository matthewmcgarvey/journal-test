defmodule JournalWeb.AccountController do
  use JournalWeb, :controller

  alias Journal.Accounting
  alias JournalWeb.{AccountJSON, ErrorResponse}

  def index(conn, _params) do
    json(conn, AccountJSON.index(Accounting.list_accounts()))
  end

  def show(conn, %{"id" => id}) do
    case parse_id(id) do
      {:ok, account_id} ->
        case Accounting.get_account(account_id) do
          nil -> ErrorResponse.detail(conn, :not_found, "account not found")
          account -> json(conn, AccountJSON.show(account))
        end

      :error ->
        ErrorResponse.detail(conn, :not_found, "account not found")
    end
  end

  def create(conn, _params) do
    with {:ok, attrs} <- object_param(conn.body_params, "account") do
      case Accounting.create_account(attrs) do
        {:ok, account} ->
          conn
          |> put_status(:created)
          |> json(
            AccountJSON.show(%{
              account: account,
              current_balance: if(account.track_balance, do: 0)
            })
          )

        {:error, changeset} ->
          ErrorResponse.changeset(conn, changeset)
      end
    else
      {:error, key} -> ErrorResponse.missing_object(conn, key)
    end
  end

  defp object_param(params, key) do
    case Map.get(params, key) do
      value when is_map(value) -> {:ok, value}
      _ -> {:error, key}
    end
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> :error
    end
  end
end
