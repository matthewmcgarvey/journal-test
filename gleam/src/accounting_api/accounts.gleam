import accounting_api/http as api_http
import accounting_api/model
import accounting_api/repository
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
  case repository.accounts(connection) {
    Ok(accounts) ->
      api_http.json_response(
        200,
        json.object([#("accounts", json.array(accounts, model.account_json))]),
      )
    Error(error) -> api_http.error_response(error)
  }
}

fn show(id: String, connection: pog.Connection) -> wisp.Response {
  case api_http.parse_id(id) {
    Error(error) -> api_http.error_response(error)
    Ok(id) ->
      case repository.account(connection, id) {
        Ok(account) ->
          api_http.json_response(
            200,
            json.object([#("account", model.account_json(account))]),
          )
        Error(error) -> api_http.error_response(error)
      }
  }
}

fn create(body: String, connection: pog.Connection) -> wisp.Response {
  case api_http.wrapped_value(body, "account") {
    Error(error) -> api_http.error_response(error)
    Ok(value) ->
      case decode.run(value, model.new_account_decoder()) {
        Error(_) -> api_http.json_error(422, "invalid account")
        Ok(new_account) ->
          case repository.create_account(connection, new_account) {
            Ok(account) ->
              api_http.json_response(
                201,
                json.object([#("account", model.account_json(account))]),
              )
            Error(error) -> api_http.error_response(error)
          }
      }
  }
}
