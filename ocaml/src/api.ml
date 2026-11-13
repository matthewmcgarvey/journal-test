let json status value = Dream.json ~status (Yojson.Basic.to_string value)
let error status message = json status (`Assoc [ ("error", `String message) ])

let account_json (account : Store.account) =
  let current_balance =
    match (account.track_balance, account.current_balance) with
    | true, Some balance -> `Int balance
    | _ -> `Null
  in
  `Assoc
    [
      ("id", `Int account.id);
      ("external_id", `String account.external_id);
      ("track_balance", `Bool account.track_balance);
      ("current_balance", current_balance);
      ("created_at", `String account.created_at);
    ]

let transfer_json (transfer : Store.transfer) =
  `Assoc
    [
      ("id", `Int transfer.id);
      ("external_id", `String transfer.external_id);
      ("debit_account_id", `Int transfer.debit_account_id);
      ("credit_account_id", `Int transfer.credit_account_id);
      ("amount", `Int transfer.amount);
      ("created_at", `String transfer.created_at);
    ]

let account_balance_json (balance : Store.account_balance) =
  `Assoc
    [
      ("id", `Int balance.id);
      ("account_id", `Int balance.account_id);
      ("running_balance", `Int balance.running_balance);
      ("created_at", `String balance.created_at);
    ]

let log_store_error = function
  | Store.Database_error message | Store.Invariant_violation message ->
      prerr_endline ("journal API: " ^ message)
  | _ -> ()

let respond_store_result success result =
  Lwt.bind result (function
    | Ok value -> success value
    | Error Store.Duplicate_external_id ->
        error `Conflict "external_id already exists"
    | Error Store.Invalid_reference ->
        error (`Status 422) "account reference does not exist"
    | Error Store.Invalid_record -> error (`Status 422) "invalid record"
    | Error Store.Insufficient_balance ->
        error (`Status 422) "insufficient balance"
    | Error Store.Not_found -> error `Not_Found "record not found"
    | Error (Store.Invariant_violation _ as error_value) ->
        log_store_error error_value;
        error `Internal_Server_Error "internal server error"
    | Error (Store.Database_error _ as error_value) ->
        log_store_error error_value;
        error `Internal_Server_Error "internal server error")

let object_fields = function `Assoc fields -> Some fields | _ -> None
let field fields name = List.assoc_opt name fields

let parse_json body =
  try Ok (Yojson.Basic.from_string body)
  with Yojson.Json_error _ -> Error "request body must be valid JSON"

let parse_wrapper wrapper body =
  match parse_json body with
  | Error message -> Error (`Bad_request message)
  | Ok json -> (
      match object_fields json with
      | Some fields -> (
          match field fields wrapper with
          | Some (`Assoc wrapped_fields) -> Ok wrapped_fields
          | _ ->
              Error
                (`Bad_request ("request must include a " ^ wrapper ^ " object"))
          )
      | None -> Error (`Bad_request "request body must be a JSON object"))

let required_string fields name =
  match field fields name with
  | Some (`String value) when String.trim value <> "" -> Ok value
  | _ -> Error (name ^ " must be a non-empty string")

let optional_boolean fields name default =
  match field fields name with
  | None -> Ok default
  | Some (`Bool value) -> Ok value
  | _ -> Error (name ^ " must be a boolean")

let required_positive_int fields name =
  match field fields name with
  | Some (`Int value) when value > 0 -> Ok value
  | _ -> Error (name ^ " must be a positive integer")

let parse_account fields =
  match
    ( required_string fields "external_id",
      optional_boolean fields "track_balance" true )
  with
  | Ok external_id, Ok track_balance -> Ok (external_id, track_balance)
  | Error message, _ | _, Error message -> Error message

let parse_transfer fields =
  match
    ( required_string fields "external_id",
      required_positive_int fields "debit_account_id",
      required_positive_int fields "credit_account_id",
      required_positive_int fields "amount" )
  with
  | Ok external_id, Ok debit_account_id, Ok credit_account_id, Ok amount ->
      Ok (external_id, debit_account_id, credit_account_id, amount)
  | Error message, _, _, _
  | _, Error message, _, _
  | _, _, Error message, _
  | _, _, _, Error message ->
      Error message

let decode_id value =
  match int_of_string_opt value with
  | Some id when id > 0 -> Some id
  | _ -> None

let list_accounts pool _request =
  Store.list_accounts pool
  |> respond_store_result (fun accounts ->
      json `OK (`List (List.map account_json accounts)))

let show_account pool request =
  match decode_id (Dream.param request "id") with
  | None -> error `Not_Found "account not found"
  | Some id ->
      Store.find_account pool id
      |> respond_store_result (fun account -> json `OK (account_json account))

let create_account pool request =
  let open Lwt.Infix in
  Dream.body request >>= fun body ->
  match parse_wrapper "account" body with
  | Error (`Bad_request message) -> error `Bad_Request message
  | Ok fields -> (
      match parse_account fields with
      | Error message -> error (`Status 422) message
      | Ok (external_id, track_balance) ->
          Store.create_account pool ~external_id ~track_balance
          |> respond_store_result (fun account ->
              json `Created (account_json account)))

let list_transfers pool _request =
  Store.list_transfers pool
  |> respond_store_result (fun transfers ->
      json `OK (`List (List.map transfer_json transfers)))

let show_transfer pool request =
  match decode_id (Dream.param request "id") with
  | None -> error `Not_Found "transfer not found"
  | Some id ->
      Store.find_transfer pool id
      |> respond_store_result (fun transfer ->
          json `OK (transfer_json transfer))

let create_transfer pool request =
  let open Lwt.Infix in
  Dream.body request >>= fun body ->
  match parse_wrapper "transfer" body with
  | Error (`Bad_request message) -> error `Bad_Request message
  | Ok fields -> (
      match parse_transfer fields with
      | Error message -> error (`Status 422) message
      | Ok (external_id, debit_account_id, credit_account_id, amount) ->
          Store.create_transfer pool ~external_id ~debit_account_id
            ~credit_account_id ~amount
          |> respond_store_result (fun transfer ->
              json `Created (transfer_json transfer)))

let list_account_balances pool request =
  let account_id =
    match Dream.query request "account_id" with
    | None -> Ok None
    | Some value -> (
        match decode_id value with
        | Some account_id -> Ok (Some account_id)
        | None -> Error "account_id must be a positive integer")
  in
  match account_id with
  | Error message -> error (`Status 422) message
  | Ok account_id ->
      Store.list_account_balances pool account_id
      |> respond_store_result (fun balances ->
          json `OK (`List (List.map account_balance_json balances)))

let router pool =
  Dream.router
    [
      Dream.scope "/api/v1" []
        [
          Dream.get "/accounts" (list_accounts pool);
          Dream.get "/accounts/:id" (show_account pool);
          Dream.post "/accounts" (create_account pool);
          Dream.get "/transfers" (list_transfers pool);
          Dream.get "/transfers/:id" (show_transfer pool);
          Dream.post "/transfers" (create_transfer pool);
          Dream.get "/account_balances" (list_account_balances pool);
        ];
    ]
