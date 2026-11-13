import accounting_api/codec
import accounting_api/http as api_http
import accounting_domain/account_balances_repository
import gleam/http.{Get}
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
    _, _ -> api_http.json_error(404, "not found")
  }
}

fn index(connection: pog.Connection) -> wisp.Response {
  case account_balances_repository.account_balances(connection) {
    Ok(balances) ->
      api_http.json_response(
        200,
        json.object([
          #(
            "account_balances",
            json.array(balances, codec.account_balance_json),
          ),
        ]),
      )
    Error(error) -> api_http.error_response(error)
  }
}
