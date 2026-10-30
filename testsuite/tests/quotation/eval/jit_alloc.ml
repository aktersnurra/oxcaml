(* TEST
  include eval;
  modules = "jit_alloc_stubs.c";
  flags = "-extension runtime_metaprogramming";
  native;
*)

external page_size : unit -> int = "jit_get_page_size"
external allocate : int -> (nativeint, string) result = "jit_memalign"
external load : nativeint -> string -> int -> unit = "jit_load_section"
external protect_ro : nativeint -> int -> (unit, int) result = "jit_mprotect_ro"
external protect_rx : nativeint -> int -> (unit, int) result = "jit_mprotect_rx"
external misalign_break : unit -> unit = "jit_test_misalign_break"
external check_contents : nativeint -> string -> bool
  = "jit_test_check_contents"

let () =
  let page = page_size () in
  misalign_break ();
  let allocations = Array.init 256 (fun i ->
    let size = page * (1 + i mod 16) in
    let addr = match allocate size with
      | Ok addr -> addr
      | Error msg -> failwith msg
    in
    assert (Nativeint.rem addr (Nativeint.of_int page) = Nativeint.zero);
    let contents = String.make size (Char.chr (i mod 256)) in
    load addr contents size;
    let protect = if i mod 2 = 0 then protect_ro else protect_rx in
    assert (protect addr size = Ok ());
    addr, contents)
  in
  Gc.full_major ();
  Array.iter (fun (addr, contents) ->
    assert (check_contents addr contents)) allocations;
  print_endline "JIT allocation OK"
