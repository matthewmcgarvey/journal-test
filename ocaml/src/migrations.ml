open Lwt.Infix

let ( let* ) result f =
  Lwt.bind result (function
    | Ok value -> f value
    | Error error -> Lwt.return (Error error))

let create_migration_table =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (unit ->. unit)
    {|
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  |}

let list_applied_migrations =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (unit ->* string) "SELECT name FROM schema_migrations ORDER BY name"

let insert_migration =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (string ->. unit) "INSERT INTO schema_migrations (name) VALUES (?)"

let dynamic_statement sql =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (unit ->. unit) ~oneshot:true sql

let read_file path = In_channel.with_open_bin path In_channel.input_all

let migration_files directory =
  Sys.readdir directory |> Array.to_list
  |> List.filter (fun filename -> Filename.check_suffix filename ".sql")
  |> List.sort String.compare

let pool_error_message = function
  | `Store_error (Store.Database_error message)
  | `Store_error (Store.Invariant_violation message) ->
      message
  | `Store_error _ -> "Unexpected store error while applying migrations"
  | `Load_rejected _ as error -> Caqti.Error.show error
  | `Load_failed _ as error -> Caqti.Error.show error
  | `Connect_rejected _ as error -> Caqti.Error.show error
  | `Connect_failed _ as error -> Caqti.Error.show error
  | `Post_connect _ as error -> Caqti.Error.show error
  | `Request_failed _ as error -> Caqti.Error.show error
  | `Response_failed _ as error -> Caqti.Error.show error
  | `Decode_rejected _ as error -> Caqti.Error.show error
  | `Encode_failed _ as error -> Caqti.Error.show error
  | `Encode_rejected _ as error -> Caqti.Error.show error
  | `Response_rejected _ as error -> Caqti.Error.show error

let apply_one (module Db : Caqti_lwt.CONNECTION) directory name =
  let sql = read_file (Filename.concat directory name) in
  Db.with_transaction (fun () ->
      Db.exec (dynamic_statement sql) () >>= function
      | Error error -> Lwt.return (Error error)
      | Ok () -> Db.exec insert_migration name)

let apply (pool : Store.pool) =
  let directory =
    match Sys.getenv_opt "MIGRATIONS_DIR" with
    | Some value when String.trim value <> "" -> value
    | _ -> "migrations"
  in
  Caqti_lwt_unix.Pool.use
    (fun (module Db : Caqti_lwt.CONNECTION) ->
      let* () = Db.exec create_migration_table () in
      let* applied = Db.collect_list list_applied_migrations () in
      let rec apply_files = function
        | [] -> Lwt.return (Ok ())
        | name :: rest ->
            if List.mem name applied then apply_files rest
            else
              let* () = apply_one (module Db) directory name in
              apply_files rest
      in
      apply_files (migration_files directory))
    pool
  >|= Result.map_error pool_error_message
