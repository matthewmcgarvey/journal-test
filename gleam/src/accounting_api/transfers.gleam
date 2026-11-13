import accounting_api/codec
import accounting_api/http as api_http
import accounting_domain/transfers_repository
import gleam/dynamic/decode
import gleam/http.{Get, Post}
import gleam/json
import pog
import wisp

pub fn handle(
  request: wisp.Request,
  connection: pog.Connection,
  path: List(String),
) -> wisp.Response {
  case path, request.method {
    [], Get -> index(connection)
    [], Post ->
      api_http.with_body(request, fn(body) { create(body, connection) })
    [id], Get -> show(id, connection)
    _, _ -> api_http.json_error(404, "not found")
  }
}

fn index(connection: pog.Connection) -> wisp.Response {
  case transfers_repository.transfers(connection) {
    Ok(transfers) ->
      api_http.json_response(
        200,
        json.object([#("transfers", json.array(transfers, codec.transfer_json))]),
      )
    Error(error) -> api_http.error_response(error)
  }
}

fn show(id: String, connection: pog.Connection) -> wisp.Response {
  case api_http.parse_id(id) {
    Error(error) -> api_http.error_response(error)
    Ok(id) ->
      case transfers_repository.transfer(connection, id) {
        Ok(transfer) ->
          api_http.json_response(
            200,
            json.object([#("transfer", codec.transfer_json(transfer))]),
          )
        Error(error) -> api_http.error_response(error)
      }
  }
}

fn create(body: String, connection: pog.Connection) -> wisp.Response {
  case api_http.wrapped_value(body, "transfer") {
    Error(error) -> api_http.request_error_response(error)
    Ok(value) ->
      case decode.run(value, codec.new_transfer_decoder()) {
        Error(_) -> api_http.json_error(422, "invalid transfer")
        Ok(new_transfer) ->
          case transfers_repository.create_transfer(connection, new_transfer) {
            Ok(transfer) ->
              api_http.json_response(
                201,
                json.object([#("transfer", codec.transfer_json(transfer))]),
              )
            Error(error) -> api_http.error_response(error)
          }
      }
  }
}
