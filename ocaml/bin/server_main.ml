open Journal

let () =
  match (Config.server_port (), Config.database_uri ()) with
  | Error message, _ | _, Error message ->
      prerr_endline message;
      exit 2
  | Ok port, Ok database_uri -> (
      match Store.connect database_uri with
      | Error error ->
          prerr_endline (Caqti.Error.show error);
          exit 1
      | Ok pool -> Dream.run ~port (Dream.logger (Api.router pool)))
