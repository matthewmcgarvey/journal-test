open Lwt.Infix

type account = {
  id : int;
  external_id : string;
  track_balance : bool;
  created_at : string;
  current_balance : int option;
}

type transfer = {
  id : int;
  external_id : string;
  debit_account_id : int;
  credit_account_id : int;
  amount : int;
  created_at : string;
}

type account_balance = {
  id : int;
  account_id : int;
  running_balance : int;
  created_at : string;
}

type entry = { account_id : int; transfer_id : int; amount : int; debit : bool }

type error =
  | Duplicate_external_id
  | Invalid_reference
  | Invalid_record
  | Insufficient_balance
  | Not_found
  | Invariant_violation of string
  | Database_error of string

type pool_error = [ Caqti.Error.t | `Store_error of error ]
type pool = (Caqti_lwt.connection, pool_error) Caqti_lwt_unix.Pool.t

let ( let* ) result f =
  Lwt.bind result (function
    | Ok value -> f value
    | Error error -> Lwt.return (Error error))

let database_error error =
  let cause =
    match error with
    | `Request_failed _ as error -> Caqti.Error.cause error
    | `Response_failed _ as error -> Caqti.Error.cause error
    | _ -> `Unspecified__don't_match
  in
  match cause with
  | `Unique_violation -> Duplicate_external_id
  | `Foreign_key_violation -> Invalid_reference
  | `Check_violation | `Not_null_violation -> Invalid_record
  | _ -> Database_error (Caqti.Error.show error)

let pool_error = function
  | `Store_error error -> error
  | `Load_rejected _ as error -> Database_error (Caqti.Error.show error)
  | `Load_failed _ as error -> Database_error (Caqti.Error.show error)
  | `Connect_rejected _ as error -> Database_error (Caqti.Error.show error)
  | `Connect_failed _ as error -> Database_error (Caqti.Error.show error)
  | `Post_connect _ as error -> Database_error (Caqti.Error.show error)
  | `Request_failed _ as error -> database_error error
  | `Response_failed _ as error -> database_error error
  | `Decode_rejected _ as error -> Database_error (Caqti.Error.show error)
  | `Encode_failed _ as error -> Database_error (Caqti.Error.show error)
  | `Encode_rejected _ as error -> Database_error (Caqti.Error.show error)
  | `Response_rejected _ as error -> Database_error (Caqti.Error.show error)

let connect database_uri : (pool, Caqti.Error.load_or_connect) result =
  match Caqti_lwt_unix.connect_pool (Uri.of_string database_uri) with
  | Error error -> Error error
  | Ok pool -> Ok (pool :> pool)

let with_connection pool f =
  Caqti_lwt_unix.Pool.use
    (fun connection ->
      f connection >|= Result.map_error (fun error -> `Store_error error))
    pool
  >|= function
  | Ok value -> Ok value
  | Error error -> Error (pool_error error)

let account_list_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (unit ->* t5 int string bool string (option int))
    {|
    SELECT a.id, a.external_id, a.track_balance, a.created_at::text,
      (SELECT b.running_balance
       FROM account_balances AS b
       WHERE b.account_id = a.id
       ORDER BY b.id DESC
       LIMIT 1)
    FROM accounts AS a
    ORDER BY a.id
  |}

let account_by_id_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (int ->? t5 int string bool string (option int))
    {|
    SELECT a.id, a.external_id, a.track_balance, a.created_at::text,
      (SELECT b.running_balance
       FROM account_balances AS b
       WHERE b.account_id = a.id
       ORDER BY b.id DESC
       LIMIT 1)
    FROM accounts AS a
    WHERE a.id = ?
  |}

let account_insert_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (t2 string bool ->! t4 int string bool string)
    {|
    INSERT INTO accounts (external_id, track_balance)
    VALUES (?, ?)
    RETURNING id, external_id, track_balance, created_at::text
  |}

let account_lock_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (int ->? t2 int bool)
    "SELECT id, track_balance FROM accounts WHERE id = ? FOR UPDATE"

let balance_for_account_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (int ->? int)
    {|
    SELECT running_balance
    FROM account_balances
    WHERE account_id = ?
    ORDER BY id DESC
    LIMIT 1
  |}

let account_balance_insert_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (t2 int int ->. unit)
    "INSERT INTO account_balances (account_id, running_balance) VALUES (?, ?)"

let transfer_insert_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (t4 string int int int ->! t6 int string int int int string)
    {|
    INSERT INTO transfers
      (external_id, debit_account_id, credit_account_id, amount)
    VALUES (?, ?, ?, ?)
    RETURNING id, external_id, debit_account_id, credit_account_id,
      amount, created_at::text
  |}

let entry_insert_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (t4 int int int bool ->. unit)
    "INSERT INTO entries (account_id, transfer_id, amount, debit) VALUES (?, \
     ?, ?, ?)"

let transfer_list_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (unit ->* t6 int string int int int string)
    {|
    SELECT id, external_id, debit_account_id, credit_account_id,
      amount, created_at::text
    FROM transfers
    ORDER BY id
  |}

let transfer_by_id_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (int ->? t6 int string int int int string)
    {|
    SELECT id, external_id, debit_account_id, credit_account_id,
      amount, created_at::text
    FROM transfers
    WHERE id = ?
  |}

let account_balance_list_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (unit ->* t4 int int int string)
    {|
    SELECT id, account_id, running_balance, created_at::text
    FROM account_balances
    ORDER BY id
  |}

let account_balance_list_for_account_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (int ->* t4 int int int string)
    {|
    SELECT id, account_id, running_balance, created_at::text
    FROM account_balances
    WHERE account_id = ?
    ORDER BY id
  |}

let entries_for_transfer_request =
  let open Caqti_type.Std in
  let open Caqti_request.Infix in
  (int ->* t4 int int int bool)
    {|
      SELECT account_id, transfer_id, amount, debit
      FROM entries
      WHERE transfer_id = ?
      ORDER BY debit DESC
    |}

let account_of_row (id, external_id, track_balance, created_at, current_balance)
    =
  { id; external_id; track_balance; created_at; current_balance }

let transfer_of_row
    (id, external_id, debit_account_id, credit_account_id, amount, created_at) =
  { id; external_id; debit_account_id; credit_account_id; amount; created_at }

let balance_of_row (id, account_id, running_balance, created_at) =
  { id; account_id; running_balance; created_at }

let validate_account_balance account =
  if account.track_balance && account.current_balance = None then
    Error (Invariant_violation "tracked account has no balance snapshot")
  else Ok account

let list_accounts pool =
  with_connection pool (fun (module Db : Caqti_lwt.CONNECTION) ->
      Db.collect_list account_list_request ()
      |> Lwt.map
           (Result.map
              (List.map (fun row ->
                   account_of_row row |> validate_account_balance)))
      >|= function
      | Error error -> Error (database_error error)
      | Ok accounts ->
          let rec collect acc = function
            | [] -> Ok (List.rev acc)
            | Ok account :: rest -> collect (account :: acc) rest
            | Error error :: _ -> Error error
          in
          collect [] accounts)

let find_account pool id =
  with_connection pool (fun (module Db : Caqti_lwt.CONNECTION) ->
      Db.find_opt account_by_id_request id >|= function
      | Error error -> Error (database_error error)
      | Ok None -> Error Not_found
      | Ok (Some row) -> account_of_row row |> validate_account_balance)

let create_account pool ~external_id ~track_balance =
  with_connection pool (fun (module Db : Caqti_lwt.CONNECTION) ->
      let work () =
        let* id, external_id, track_balance, created_at =
          Db.find account_insert_request (external_id, track_balance)
        in
        let* () =
          if track_balance then Db.exec account_balance_insert_request (id, 0)
          else Lwt.return (Ok ())
        in
        Lwt.return
          (Ok
             {
               id;
               external_id;
               track_balance;
               created_at;
               current_balance = (if track_balance then Some 0 else None);
             })
      in
      Db.with_transaction work >|= function
      | Ok account -> Ok account
      | Error error -> Error (database_error error))

let find_locked_account (module Db : Caqti_lwt.CONNECTION) id =
  Db.find_opt account_lock_request id

let latest_balance (module Db : Caqti_lwt.CONNECTION) id =
  Db.find_opt balance_for_account_request id

let transaction_error = function
  | `Abort error -> error
  | `Request_failed _ as error -> database_error error
  | `Response_failed _ as error -> database_error error
  | `Decode_rejected _ as error -> database_error error
  | `Encode_failed _ as error -> database_error error
  | `Encode_rejected _ as error -> database_error error
  | `Response_rejected _ as error -> database_error error

let create_transfer pool ~external_id ~debit_account_id ~credit_account_id
    ~amount =
  if debit_account_id = credit_account_id then Lwt.return (Error Invalid_record)
  else
    with_connection pool (fun (module Db : Caqti_lwt.CONNECTION) ->
        let work () =
          let first_id = min debit_account_id credit_account_id in
          let second_id = max debit_account_id credit_account_id in
          let* first_account = find_locked_account (module Db) first_id in
          let* second_account = find_locked_account (module Db) second_id in
          match (first_account, second_account) with
          | Some (first_id, first_tracked), Some (_, second_tracked) ->
              let debit_tracked, credit_tracked =
                if debit_account_id = first_id then
                  (first_tracked, second_tracked)
                else (second_tracked, first_tracked)
              in
              let* debit_balance =
                if debit_tracked then
                  let* balance = latest_balance (module Db) debit_account_id in
                  match balance with
                  | Some balance -> Lwt.return (Ok balance)
                  | None ->
                      Lwt.return
                        (Error
                           (`Abort
                              (Invariant_violation
                                 "tracked debit account has no balance snapshot")))
                else Lwt.return (Ok 0)
              in
              if debit_tracked && debit_balance < amount then
                Lwt.return (Error (`Abort Insufficient_balance))
              else
                let* transfer_row =
                  Db.find transfer_insert_request
                    (external_id, debit_account_id, credit_account_id, amount)
                in
                let transfer = transfer_of_row transfer_row in
                let* () =
                  Db.exec entry_insert_request
                    (debit_account_id, transfer.id, amount, true)
                in
                let* () =
                  Db.exec entry_insert_request
                    (credit_account_id, transfer.id, amount, false)
                in
                let* () =
                  if debit_tracked then
                    Db.exec account_balance_insert_request
                      (debit_account_id, debit_balance - amount)
                  else Lwt.return (Ok ())
                in
                let* () =
                  if credit_tracked then
                    let* credit_balance =
                      latest_balance (module Db) credit_account_id
                    in
                    match credit_balance with
                    | Some balance ->
                        Db.exec account_balance_insert_request
                          (credit_account_id, balance + amount)
                    | None ->
                        Lwt.return
                          (Error
                             (`Abort
                                (Invariant_violation
                                   "tracked credit account has no balance \
                                    snapshot")))
                  else Lwt.return (Ok ())
                in
                Lwt.return (Ok transfer)
          | _ -> Lwt.return (Error (`Abort Invalid_reference))
        in
        Db.with_transaction (fun () ->
            work ()
            >|= Result.map_error (function
              | `Abort error -> `Abort error
              | error -> error))
        >|= function
        | Ok transfer -> Ok transfer
        | Error error -> Error (transaction_error error))

let list_transfers pool =
  with_connection pool (fun (module Db : Caqti_lwt.CONNECTION) ->
      Db.collect_list transfer_list_request () >|= function
      | Ok rows -> Ok (List.map transfer_of_row rows)
      | Error error -> Error (database_error error))

let find_transfer pool id =
  with_connection pool (fun (module Db : Caqti_lwt.CONNECTION) ->
      Db.find_opt transfer_by_id_request id >|= function
      | Ok (Some row) -> Ok (transfer_of_row row)
      | Ok None -> Error Not_found
      | Error error -> Error (database_error error))

let list_account_balances pool account_id =
  with_connection pool (fun (module Db : Caqti_lwt.CONNECTION) ->
      let result =
        match account_id with
        | Some account_id ->
            Db.collect_list account_balance_list_for_account_request account_id
        | None -> Db.collect_list account_balance_list_request ()
      in
      result >|= function
      | Ok rows -> Ok (List.map balance_of_row rows)
      | Error error -> Error (database_error error))

let entries_for_transfer pool transfer_id =
  with_connection pool (fun (module Db : Caqti_lwt.CONNECTION) ->
      Db.collect_list entries_for_transfer_request transfer_id >|= function
      | Ok rows ->
          Ok
            (List.map
               (fun (account_id, transfer_id, amount, debit) ->
                 { account_id; transfer_id; amount; debit })
               rows)
      | Error error -> Error (database_error error))
