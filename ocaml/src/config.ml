let env name fallback =
  match Sys.getenv_opt name with
  | Some value when String.trim value <> "" -> value
  | _ -> fallback

let database_uri () =
  match Sys.getenv_opt "DATABASE_URL" with
  | Some value when String.trim value <> "" -> Ok value
  | _ -> (
      let username = env "POSTGRES_USER" "app" in
      let password = env "POSTGRES_PASSWORD" "app" in
      let host = env "POSTGRES_HOST" "127.0.0.1" in
      let port = int_of_string_opt (env "POSTGRES_PORT" "5432") in
      let database = env "POSTGRES_DB" "accounting" in
      match port with
      | Some port when port > 0 && port <= 65535 ->
          let userinfo =
            Uri.pct_encode username ^ ":" ^ Uri.pct_encode password
          in
          Uri.make ~scheme:"postgresql" ~userinfo ~host ~port
            ~path:("/" ^ database) ()
          |> Uri.to_string |> Result.ok
      | _ -> Error "POSTGRES_PORT must be an integer between 1 and 65535")

let server_port () =
  match int_of_string_opt (env "PORT" "4000") with
  | Some port when port > 0 && port <= 65535 -> Ok port
  | _ -> Error "PORT must be an integer between 1 and 65535"
