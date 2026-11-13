defmodule JournalWeb.TransferController do
  use JournalWeb, :controller

  alias Journal.Accounting
  alias JournalWeb.{ErrorResponse, TransferJSON}

  def index(conn, _params) do
    json(conn, TransferJSON.index(Accounting.list_transfers()))
  end

  def show(conn, %{"id" => id}) do
    case parse_id(id) do
      {:ok, transfer_id} ->
        case Accounting.get_transfer(transfer_id) do
          nil -> ErrorResponse.detail(conn, :not_found, "transfer not found")
          transfer -> json(conn, TransferJSON.show(transfer))
        end

      :error ->
        ErrorResponse.detail(conn, :not_found, "transfer not found")
    end
  end

  def create(conn, _params) do
    with {:ok, attrs} <- object_param(conn.body_params, "transfer") do
      case Accounting.create_transfer(attrs) do
        {:ok, transfer} ->
          conn
          |> put_status(:created)
          |> json(TransferJSON.show(transfer))

        {:error, %Ecto.Changeset{} = changeset} ->
          ErrorResponse.changeset(conn, changeset)

        {:error, :insufficient_funds} ->
          ErrorResponse.detail(conn, :unprocessable_entity, "insufficient funds")

        {:error, :invalid_account} ->
          ErrorResponse.detail(conn, :unprocessable_entity, "account not found")
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
