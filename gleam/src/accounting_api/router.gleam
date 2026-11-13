import accounting_api/model
import accounting_api/repository
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http.{Get, Post}
import gleam/int
import gleam/io
import gleam/json
import pog
import wisp

pub fn handle(
  request: wisp.Request,
  connection: pog.Connection,
) -> wisp.Response {
  use <- wisp.log_request(request)
  case wisp.path_segments(request), request.method {
    ["api", "v1", "accounts"], Get -> list_accounts(connection)
    ["api", "v1", "accounts"], Post ->
      with_body(request, fn(body) { create_account(body, connection) })
    ["api", "v1", "accounts", id], Get -> show_account(id, connection)
    ["api", "v1", "transfers"], Get -> list_transfers(connection)
    ["api", "v1", "transfers"], Post ->
      with_body(request, fn(body) { create_transfer(body, connection) })
    ["api", "v1", "transfers", id], Get -> show_transfer(id, connection)
    ["api", "v1", "account_balances"], Get -> list_account_balances(connection)
    _, _ -> json_error(404, "not found")
  }
}

fn list_accounts(connection: pog.Connection) -> wisp.Response {
  case repository.accounts(connection) {
    Ok(accounts) ->
      json_response(
        200,
        json.object([#("accounts", json.array(accounts, model.account_json))]),
      )
    Error(error) -> error_response(error)
  }
}

fn show_account(id: String, connection: pog.Connection) -> wisp.Response {
  case parse_id(id) {
    Error(error) -> error_response(error)
    Ok(id) ->
      case repository.account(connection, id) {
        Ok(account) ->
          json_response(
            200,
            json.object([#("account", model.account_json(account))]),
          )
        Error(error) -> error_response(error)
      }
  }
}

fn create_account(body: String, connection: pog.Connection) -> wisp.Response {
  case wrapped_value(body, "account") {
    Error(error) -> error_response(error)
    Ok(value) ->
      case decode.run(value, model.new_account_decoder()) {
        Error(_) -> json_error(422, "invalid account")
        Ok(new_account) ->
          case repository.create_account(connection, new_account) {
            Ok(account) ->
              json_response(
                201,
                json.object([#("account", model.account_json(account))]),
              )
            Error(error) -> error_response(error)
          }
      }
  }
}

fn list_transfers(connection: pog.Connection) -> wisp.Response {
  case repository.transfers(connection) {
    Ok(transfers) ->
      json_response(
        200,
        json.object([#("transfers", json.array(transfers, model.transfer_json))]),
      )
    Error(error) -> error_response(error)
  }
}

fn show_transfer(id: String, connection: pog.Connection) -> wisp.Response {
  case parse_id(id) {
    Error(error) -> error_response(error)
    Ok(id) ->
      case repository.transfer(connection, id) {
        Ok(transfer) ->
          json_response(
            200,
            json.object([#("transfer", model.transfer_json(transfer))]),
          )
        Error(error) -> error_response(error)
      }
  }
}

fn create_transfer(body: String, connection: pog.Connection) -> wisp.Response {
  case wrapped_value(body, "transfer") {
    Error(error) -> error_response(error)
    Ok(value) ->
      case decode.run(value, model.new_transfer_decoder()) {
        Error(_) -> json_error(422, "invalid transfer")
        Ok(new_transfer) ->
          case repository.create_transfer(connection, new_transfer) {
            Ok(transfer) ->
              json_response(
                201,
                json.object([#("transfer", model.transfer_json(transfer))]),
              )
            Error(error) -> error_response(error)
          }
      }
  }
}

fn list_account_balances(connection: pog.Connection) -> wisp.Response {
  case repository.account_balances(connection) {
    Ok(balances) ->
      json_response(
        200,
        json.object([
          #(
            "account_balances",
            json.array(balances, model.account_balance_json),
          ),
        ]),
      )
    Error(error) -> error_response(error)
  }
}

fn wrapped_value(
  body: String,
  wrapper: String,
) -> Result(Dynamic, model.ApiError) {
  case json.parse(body, decode.dynamic) {
    Error(_) -> Error(model.InvalidInput("request body must be valid JSON"))
    Ok(value) ->
      case
        decode.run(value, decode.field(wrapper, decode.dynamic, decode.success))
      {
        Ok(wrapped) -> Ok(wrapped)
        Error(_) -> Error(model.MissingWrapper)
      }
  }
}

fn with_body(
  request: wisp.Request,
  next: fn(String) -> wisp.Response,
) -> wisp.Response {
  case wisp.read_body_bits(request) {
    Error(_) -> json_error(413, "request body is too large")
    Ok(body) ->
      case bit_array.to_string(body) {
        Error(_) -> json_error(400, "request body must be valid UTF-8")
        Ok(body) -> next(body)
      }
  }
}

fn parse_id(value: String) -> Result(Int, model.ApiError) {
  case int.parse(value) {
    Ok(id) if id > 0 -> Ok(id)
    _ -> Error(model.NotFound)
  }
}

fn json_response(status: Int, body: json.Json) -> wisp.Response {
  wisp.json_response(json.to_string(body), status)
}

fn json_error(status: Int, message: String) -> wisp.Response {
  json_response(status, json.object([#("error", json.string(message))]))
}

fn error_response(error: model.ApiError) -> wisp.Response {
  case error {
    model.MissingWrapper -> json_error(400, "missing required JSON wrapper")
    model.InvalidInput(message) -> json_error(422, message)
    model.NotFound -> json_error(404, "not found")
    model.Conflict -> json_error(409, "external_id already exists")
    model.InsufficientFunds -> json_error(422, "insufficient funds")
    model.Database(message) -> {
      io.println("Database error: " <> message)
      json_error(500, "internal server error")
    }
  }
}
