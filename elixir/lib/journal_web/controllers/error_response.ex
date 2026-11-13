defmodule JournalWeb.ErrorResponse do
  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  alias Ecto.Changeset

  def changeset(conn, %Changeset{} = changeset) do
    status =
      if unique_conflict?(changeset),
        do: :conflict,
        else: :unprocessable_entity

    conn
    |> put_status(status)
    |> json(%{errors: changeset_errors(changeset)})
  end

  def detail(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{errors: %{detail: message}})
  end

  def missing_object(conn, key) do
    detail(conn, :bad_request, "missing required #{key} object")
  end

  defp unique_conflict?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, options}} ->
      Keyword.get(options, :constraint) == :unique
    end)
  end

  defp changeset_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end
end
