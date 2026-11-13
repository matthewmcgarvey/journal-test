import accounting_api/account_balances
import accounting_api/accounts
import accounting_api/http
import accounting_api/transfers
import pog
import wisp

pub fn handle(
  request: wisp.Request,
  connection: pog.Connection,
) -> wisp.Response {
  use <- wisp.log_request(request)
  case wisp.path_segments(request) {
    ["api", "v1", "accounts", ..path] ->
      accounts.handle(request, connection, path)
    ["api", "v1", "transfers", ..path] ->
      transfers.handle(request, connection, path)
    ["api", "v1", "account_balances", ..path] ->
      account_balances.handle(request, connection, path)
    _ -> http.json_error(404, "not found")
  }
}
