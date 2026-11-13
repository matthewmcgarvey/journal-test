open Journal

let () =
  match Config.database_uri () with
  | Error message ->
      prerr_endline message;
      exit 2
  | Ok database_uri -> (
      match Store.connect database_uri with
      | Error error ->
          prerr_endline (Caqti.Error.show error);
          exit 1
      | Ok pool -> (
          match Lwt_main.run (Migrations.apply pool) with
          | Ok () -> print_endline "Database migrations applied"
          | Error message ->
              prerr_endline ("Migration failed: " ^ message);
              exit 1))
