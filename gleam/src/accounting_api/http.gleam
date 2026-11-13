import accounting_api/model
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import wisp

pub fn wrapped_value(
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

pub fn with_body(
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

pub fn parse_id(value: String) -> Result(Int, model.ApiError) {
  case int.parse(value) {
    Ok(id) if id > 0 -> Ok(id)
    _ -> Error(model.NotFound)
  }
}

pub fn json_response(status: Int, body: json.Json) -> wisp.Response {
  wisp.json_response(json.to_string(body), status)
}

pub fn json_error(status: Int, message: String) -> wisp.Response {
  json_response(status, json.object([#("error", json.string(message))]))
}

pub fn error_response(error: model.ApiError) -> wisp.Response {
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
