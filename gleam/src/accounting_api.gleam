import accounting_api/database
import accounting_api/router
import envoy
import gleam/erlang/process
import gleam/int
import gleam/option.{Some}
import mist
import pog
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()
  let pool_name = process.new_name("accounting_api_pool")
  let database_config =
    pog.default_config(pool_name)
    |> pog.host(environment("POSTGRES_HOST", "localhost"))
    |> pog.port(environment_int("POSTGRES_PORT", 5432))
    |> pog.database(environment("POSTGRES_DB", "accounting"))
    |> pog.user(environment("POSTGRES_USER", "app"))
    |> pog.password(Some(environment("POSTGRES_PASSWORD", "app")))
  let assert Ok(_) = pog.start(database_config)
    as "Could not start PostgreSQL pool"
  let connection = pog.named_connection(pool_name)
  let assert Ok(_) = database.migrate(connection) as "Database migration failed"
  let port = environment_int("PORT", 8000)
  let handler = fn(request) { router.handle(request, connection) }
  let server =
    handler
    |> wisp_mist.handler(environment(
      "SECRET_KEY_BASE",
      "local-development-secret-key-base-that-is-not-for-production",
    ))
    |> mist.new
    |> mist.port(port)
    |> mist.bind("0.0.0.0")
  let assert Ok(_) = mist.start(server) as "Could not start HTTP server"
  process.sleep_forever()
}

fn environment(name: String, default: String) -> String {
  case envoy.get(name) {
    Ok(value) -> value
    Error(_) -> default
  }
}

fn environment_int(name: String, default: Int) -> Int {
  case envoy.get(name) {
    Error(_) -> default
    Ok(value) -> {
      let assert Ok(parsed) = int.parse(value)
        as "Environment port must be an integer"
      parsed
    }
  }
}
