open Alcotest
open Journal

let test_account_default_balance_tracking () =
  match Api.parse_account [ ("external_id", `String "acct-1") ] with
  | Ok ("acct-1", true) -> ()
  | _ -> fail "track_balance should default to true"

let test_account_optional_tracking () =
  match
    Api.parse_account
      [ ("external_id", `String "acct-2"); ("track_balance", `Bool false) ]
  with
  | Ok ("acct-2", false) -> ()
  | _ -> fail "explicit track_balance=false should be preserved"

let test_missing_account_wrapper () =
  match Api.parse_wrapper "account" {|{"external_id":"acct-1"}|} with
  | Error (`Bad_request _) -> ()
  | _ -> fail "missing account wrapper should be a bad request"

let test_transfer_requires_positive_integer_amount () =
  let fields =
    [
      ("external_id", `String "transfer-1");
      ("debit_account_id", `Int 1);
      ("credit_account_id", `Int 2);
      ("amount", `Int 0);
    ]
  in
  match Api.parse_transfer fields with
  | Error _ -> ()
  | Ok _ -> fail "zero transfer amount should be rejected"

let () =
  run "request validation"
    [
      ( "accounts",
        [
          test_case "tracking defaults to true" `Quick
            test_account_default_balance_tracking;
          test_case "tracking can be disabled" `Quick
            test_account_optional_tracking;
          test_case "required wrapper" `Quick test_missing_account_wrapper;
        ] );
      ( "transfers",
        [
          test_case "amount must be positive" `Quick
            test_transfer_requires_positive_integer_amount;
        ] );
    ]
