import accounting_api/model.{type ApiError, Conflict, Database, InvalidInput}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string
import pog

pub fn with_transaction(
  connection: pog.Connection,
  callback: fn(pog.Connection) -> Result(a, ApiError),
) -> Result(a, ApiError) {
  case pog.transaction(connection, callback) {
    Ok(value) -> Ok(value)
    Error(pog.TransactionRolledBack(error)) -> Error(error)
    Error(pog.TransactionQueryError(error)) -> Error(query_error(error))
  }
}

pub fn run(
  connection: pog.Connection,
  sql: String,
  parameters: List(pog.Value),
  decoder: decode.Decoder(a),
) -> Result(pog.Returned(a), ApiError) {
  let query =
    list.fold(parameters, pog.query(sql), fn(query, parameter) {
      pog.parameter(query, parameter)
    })
    |> pog.returning(decoder)
  pog.execute(query, on: connection)
  |> result.map_error(query_error)
}

pub fn first_or_not_found(returned: pog.Returned(a)) -> Result(a, ApiError) {
  case returned.rows {
    [row, ..] -> Ok(row)
    [] -> Error(model.NotFound)
  }
}

pub fn first_or_database_error(
  returned: pog.Returned(a),
  message: String,
) -> Result(a, ApiError) {
  case returned.rows {
    [row, ..] -> Ok(row)
    [] -> Error(Database(message))
  }
}

fn query_error(error: pog.QueryError) -> ApiError {
  case error {
    pog.ConstraintViolated(_, "accounts_external_id_key", _) -> Conflict
    pog.ConstraintViolated(_, "transfers_external_id_key", _) -> Conflict
    pog.ConstraintViolated(_, _, _) ->
      InvalidInput("a database constraint was violated")
    pog.PostgresqlError("23505", _, _) -> Conflict
    pog.PostgresqlError("23503", _, _) ->
      InvalidInput("an account reference does not exist")
    pog.PostgresqlError("23514", _, _) ->
      InvalidInput("a database constraint was violated")
    pog.PostgresqlError("23502", _, _) ->
      InvalidInput("a required field is missing")
    _ -> Database(string.inspect(error))
  }
}
