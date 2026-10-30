#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
root=$PWD
configuration=${1:?configuration required}
prefix="$root/_install"

# Repeat the existing regressions with a smaller minor heap and more JIT loads.
export OCAMLRUNPARAM=s=32k
export OCAML_JIT_STRESS_ITERATIONS=256
for round in 1 2 3; do
  echo "Runtime stress round $round ($configuration)"
  for dir in quotation/eval runtime-errors callback effects/tls; do
    gmake -s test-one-no-rebuild DIR="$dir"
  done
  if [[ $configuration == multidomain ]]; then
    for dir in parallel lib-dynlink-domains lib-systhreads; do
      gmake -s test-one-no-rebuild DIR="$dir"
    done
  fi
done
unset OCAMLRUNPARAM OCAML_JIT_STRESS_ITERATIONS

# Register the installed compiler without rebuilding it or using bootstrap
# libraries, then build third-party packages and run their own test suites.
work=$(mktemp -d /tmp/oxcaml-freebsd-packages.XXXXXX)
trap 'rm -rf "$work"' EXIT
unset OCAMLLIB CAMLLIB OCAMLPATH CAML_LD_LIBRARY_PATH OCAMLFIND_CONF \
  OCAMLFIND_COMMANDS OCAMLFIND_TOOLCHAIN OPAM_SWITCH_PREFIX OPAMSWITCH
export PATH="$prefix/bin:$PATH"
test "$(ocamlc -where)" = "$prefix/lib/ocaml"
version=$(ocamlc -version)
test "$version" = 5.4.0+ox
opam switch create installed --empty --yes
export OPAMSWITCH=installed
mkdir "$work/compiler"
opam show --raw ocaml-system.5.4.0 | \
  sed 's/sys-ocaml-version = "5.4.0"/sys-ocaml-version = "5.4.0+ox"/' \
    > "$work/compiler/opam"
opam pin add --no-action --yes "ocaml-system.$version" "$work/compiler"
opam install --yes "ocaml-system.$version"
eval "$(opam env --switch=installed --set-switch --shell=sh)"
test "$(ocamlc -where)" = "$prefix/lib/ocaml"
opam install --yes dune.3.23.1 ocamlfind.1.9.8
opam install --yes --with-test cppo.1.8.0 yojson.3.0.0 lwt.5.9.2
opam list --installed --columns=name,version
dune --version
ocamlfind printconf
printf '#define ANSWER 42\nlet answer = ANSWER\n' > "$work/macro.ml"
cppo -n "$work/macro.ml" > "$work/expanded.ml"
grep -Fx 'let answer = 42' "$work/expanded.ml"
printf '{"message":"FreeBSD","values":[1,2,3]}\n' > "$work/input.json"
ydump "$work/input.json" > "$work/output.json"

cat > "$work/smoke.ml" <<'OCAML'
let () =
  let json = "{\"message\":\"FreeBSD\",\"values\":[1,2,3]}" in
  let value = Yojson.Safe.from_string json in
  assert (Yojson.Safe.from_string (Yojson.Safe.to_string value) = value);
  assert (Yojson.Safe.from_file Sys.argv.(1) = value);
  let output = Lwt_main.run
    (Lwt_process.pmap ("/bin/cat", [| "cat" |]) json) in
  assert (output = json);
  print_endline "Installed applications OK"
OCAML
for compiler in ocamlc ocamlopt; do
  ocamlfind "$compiler" -package yojson,lwt.unix -linkpkg \
    "$work/smoke.ml" -o "$work/smoke.$compiler"
  "$work/smoke.$compiler" "$work/output.json" > "$work/smoke.out"
  cat "$work/smoke.out"
  grep -Fx 'Installed applications OK' "$work/smoke.out"
done
opam switch export "$root/_ci_logs/installed-packages.export"
