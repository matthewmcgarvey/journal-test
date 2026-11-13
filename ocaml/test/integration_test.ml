open Alcotest
open Journal

let fail_store operation = function
  | Ok value -> value
  | Error _ -> fail (operation ^ " failed")

let new_external_id prefix =
  Printf.sprintf "%s-%08x-%08x" prefix (Random.bits ()) (Random.bits ())

let test_atomic_concurrent_debits () =
  match Sys.getenv_opt "TEST_DATABASE_URL" with
  | None -> skip ()
  | Some database_uri ->
      Random.self_init ();
      let pool =
        match Store.connect database_uri with
        | Ok pool -> pool
        | Error error -> fail (Caqti.Error.show error)
      in
      let test =
        let open Lwt.Infix in
        Migrations.apply pool >>= function
        | Error message -> Lwt.fail_with message
        | Ok () ->
            let create_account track_balance =
              Store.create_account pool
                ~external_id:(new_external_id "account")
                ~track_balance
            in
            create_account false >>= fun source_result ->
            create_account true >>= fun tracked_result ->
            create_account false >>= fun recipient_a_result ->
            create_account false >>= fun recipient_b_result ->
            let source = fail_store "create source" source_result in
            let tracked = fail_store "create tracked account" tracked_result in
            let recipient_a =
              fail_store "create recipient" recipient_a_result
            in
            let recipient_b =
              fail_store "create recipient" recipient_b_result
            in
            Store.create_account pool ~external_id:source.external_id
              ~track_balance:false
            >>= fun duplicate_result ->
            (match duplicate_result with
            | Error Store.Duplicate_external_id -> ()
            | _ -> fail "duplicate external_id should be rejected");
            Store.list_account_balances pool (Some source.id)
            >>= fun source_balances_result ->
            check (list int) "untracked source has no balance snapshots" []
              (List.map
                 (fun snapshot -> snapshot.Store.running_balance)
                 (fail_store "read source snapshots" source_balances_result));
            Store.create_transfer pool ~external_id:(new_external_id "fund")
              ~debit_account_id:source.id ~credit_account_id:tracked.id
              ~amount:1000
            >>= fun funding_result ->
            let funding = fail_store "fund tracked account" funding_result in
            Store.entries_for_transfer pool funding.id
            >>= fun funding_entries ->
            let funding_entries =
              fail_store "read funding entries" funding_entries
            in
            check
              (list (pair int (pair int bool)))
              "both funding entries are recorded"
              [ (source.id, (1000, true)); (tracked.id, (1000, false)) ]
              (List.map
                 (fun entry ->
                   (entry.Store.account_id, (entry.amount, entry.debit)))
                 funding_entries);
            let external_id_a = new_external_id "concurrent" in
            let external_id_b = new_external_id "concurrent" in
            let transfer (recipient : Store.account) external_id =
              Store.create_transfer pool ~external_id
                ~debit_account_id:tracked.id ~credit_account_id:recipient.id
                ~amount:700
            in
            Lwt.both
              (transfer recipient_a external_id_a)
              (transfer recipient_b external_id_b)
            >>= fun (result_a, result_b) ->
            let successful =
              [ result_a; result_b ]
              |> List.filter (function Ok _ -> true | Error _ -> false)
              |> List.length
            in
            check int "one concurrent debit commits" 1 successful;
            let insufficient =
              [ result_a; result_b ]
              |> List.filter (function
                | Error Store.Insufficient_balance -> true
                | Error _ -> fail "concurrent debit failed unexpectedly"
                | Ok _ -> false)
              |> List.length
            in
            check int "the other debit is rejected for insufficient funds" 1
              insufficient;
            let committed_external_ids =
              match (result_a, result_b) with
              | Ok _, Error Store.Insufficient_balance -> [ external_id_a ]
              | Error Store.Insufficient_balance, Ok _ -> [ external_id_b ]
              | _ -> fail "exactly one concurrent transfer should commit"
            in
            let committed_transfer =
              match (result_a, result_b) with
              | Ok transfer, Error Store.Insufficient_balance
              | Error Store.Insufficient_balance, Ok transfer ->
                  transfer
              | _ -> fail "exactly one concurrent transfer should commit"
            in
            Store.entries_for_transfer pool committed_transfer.id
            >>= fun concurrent_entries_result ->
            let concurrent_entries =
              fail_store "read concurrent transfer entries"
                concurrent_entries_result
            in
            check int "both entries for the committed debit are stored" 2
              (List.length concurrent_entries);
            Store.find_account pool tracked.id >>= fun final_account ->
            let final_account = fail_store "read final account" final_account in
            check (option int) "balance reflects one debit" (Some 300)
              final_account.current_balance;
            Store.list_account_balances pool (Some tracked.id)
            >>= fun history_result ->
            let history = fail_store "read snapshots" history_result in
            check (list int) "only committed snapshots are recorded"
              [ 0; 1000; 300 ]
              (List.map
                 (fun snapshot -> snapshot.Store.running_balance)
                 history);
            Store.list_transfers pool >|= fun transfer_result ->
            let transfers = fail_store "read transfers" transfer_result in
            let saved_external_ids =
              transfers
              |> List.filter_map (fun transfer ->
                  if
                    List.mem transfer.Store.external_id
                      [ external_id_a; external_id_b ]
                  then Some transfer.external_id
                  else None)
            in
            check (list string) "only the successful transfer is stored"
              committed_external_ids saved_external_ids
      in
      (try Lwt_main.run test
       with exn ->
         Lwt_main.run (Caqti_lwt_unix.Pool.drain pool);
         raise exn);
      Lwt_main.run (Caqti_lwt_unix.Pool.drain pool)

let () =
  run "PostgreSQL integration"
    [
      ( "transfers",
        [
          test_case "concurrent debits cannot overspend" `Slow
            test_atomic_concurrent_debits;
        ] );
    ]
