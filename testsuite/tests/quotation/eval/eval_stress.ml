(* TEST
  include eval;
  directories += "${ocamlsrcdir}/stdlib/unix";
  hasunix;
  not-target-windows;
  flags = "-extension runtime_metaprogramming";
  native;
*)

#syntax quotations on

let iterations =
  match Sys.getenv_opt "OCAML_JIT_STRESS_ITERATIONS" with
  | None -> 8
  | Some n -> int_of_string n

let names = [| "zero"; "one"; "two"; "three";
               "four"; "five"; "six"; "seven" |]

let check f seed =
  let values, name, number = f seed in
  assert (name = names.(seed land 7));
  assert (number = float_of_int seed +. 1.25);
  Array.iteri (fun i value -> assert (value = seed lxor i)) values;
  match f (-1) with
  | _ -> failwith "JIT code did not raise Invalid_argument"
  | exception Invalid_argument msg -> assert (msg = "negative seed")

let () =
  assert (iterations > 0);
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
      let retained = Array.init iterations (fun seed ->
        let f : int -> int array * string * float = Eval.eval <[
          fun seed ->
            if seed < 0 then invalid_arg "negative seed";
            let name = match seed land 7 with
              | 0 -> "zero" | 1 -> "one" | 2 -> "two" | 3 -> "three"
              | 4 -> "four" | 5 -> "five" | 6 -> "six" | _ -> "seven"
            in
            Array.init 257 (fun i -> seed lxor i),
            name, float_of_int seed +. 1.25
        ]> in
        check f seed;
        if seed mod 8 = 0 then Gc.full_major ();
        f)
      in
      Gc.compact ();
      for round = 0 to 7 do
        Array.iteri (fun i f -> check f (i + round)) retained;
        Gc.full_major ()
      done;
      assert (!signals > 0));
  print_endline "JIT stress OK"
