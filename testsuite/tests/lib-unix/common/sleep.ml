(* TEST
  modules = "sleep_stubs.c";
  include unix;
  hasunix;
  not-target-windows;
  {
    bytecode;
  }{
    native;
  }
*)

external monotonic_time : unit -> float = "sleep_test_monotonic_time"

let () =
  let signals = ref 0 in
  let handler = Sys.signal Sys.sigalrm
    (Sys.Signal_handle (fun _ -> incr signals)) in
  let timer = Unix.setitimer Unix.ITIMER_REAL
    { Unix.it_interval = 0.01; it_value = 0.01 } in
  Fun.protect
    ~finally:(fun () ->
      ignore (Unix.setitimer Unix.ITIMER_REAL timer);
      ignore (Sys.signal Sys.sigalrm handler))
    (fun () ->
      for round = 0 to 2 do
        let duration = if round = 0 then 1.0 else 0.2 in
        let before = !signals in
        let start = monotonic_time () in
        if round = 0 then Unix.sleep 1 else Unix.sleepf duration;
        let elapsed = monotonic_time () -. start in
        assert (!signals > before);
        assert (elapsed >= duration)
      done);
  print_endline "Sleep under signals OK"
