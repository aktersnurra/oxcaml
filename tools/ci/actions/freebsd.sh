#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != FreeBSD || $(uname -m) != amd64 ]]; then
  echo "This job requires FreeBSD/amd64." >&2
  exit 1
fi
configuration=${1:-default}
case "$configuration" in
  default) configure_flags=() ;;
  multidomain)
    configure_flags=(--enable-stack-checks --enable-poll-insertion
                     --enable-multidomain) ;;
  *) echo "Unknown configuration: $configuration" >&2; exit 1 ;;
esac

cd "$(git rev-parse --show-toplevel)"
root=$PWD
mkdir -p _ci_logs _ci_bin
ln -sf "$(command -v gmake)" _ci_bin/make
ln -sf "$(command -v gsed)" _ci_bin/sed
export PATH="$root/_ci_bin:$PATH"
export OPAMROOT
OPAMROOT=$(mktemp -d /tmp/oxcaml-ci-opam.XXXXXX)
export OPAMJOBS=2
export DUNE_JOBS=1

run_stage() {
  local name=$1
  shift
  echo "::notice title=FreeBSD validation::$name"
  "$@" 2>&1 | tee "$root/_ci_logs/$name.log"
}

run_stage platform sh -c 'uname -a; freebsd-version; cc --version'
run_stage opam-init opam init --bare --no-setup --yes \
  default https://github.com/ocaml/opam-repository.git
run_stage opam-repo opam repository add local \
  "$root/tools/ci/local-opam" --all-switches --yes
run_stage bootstrap opam switch create bootstrap --yes \
  --repositories=local,default \
  oxcaml-ci-deps.5.4.0-with-ocaml.5.4.0-with-ocamlformat.0.29.0
eval "$(opam env --switch=bootstrap --set-switch --shell=sh)"
run_stage versions sh -c 'ocamlopt -version; dune --version; menhir --version'
run_stage autoconf autoconf
run_stage configure ./configure --prefix="$root/_install" \
  --with-opam-switch=bootstrap "${configure_flags[@]}"
run_stage boot gmake -s boot-compiler
export OCAMLLIB="$root/_build/default/stdlib/build"
mkdir -p "$root/_ci_logs/native-smoke"
cd "$root/_ci_logs/native-smoke"
for name in stackoverflow stackoverflow_large_frame \
            stackoverflow_young_ptr stackoverflow_local_fiber; do
  cp "$root/testsuite/tests/runtime-errors/$name.ml" .
  run_stage "compile-$name" "$root/_build/default/boot_ocamlopt.exe" \
    "$name.ml" -o "$name.exe"
  run_stage "$name" "./$name.exe"
  reference="$root/testsuite/tests/runtime-errors/$name.reference"
  if [[ $name == stackoverflow ]]; then
    reference="$root/testsuite/tests/runtime-errors/stackoverflow.opt.reference"
  fi
  diff -u "$reference" "$root/_ci_logs/$name.log"
done
cp "$root/oxcaml/tests/backend/probes/t2.ml" .
for mode in optimized unoptimized; do
  flags=()
  if [[ $mode == unoptimized ]]; then
    flags=(-no-probes-optimized)
  fi
  run_stage "compile-probes-$mode" "$root/_build/default/boot_ocamlopt.exe" \
    "${flags[@]}" t2.ml -o "probes-$mode.exe"
  run_stage "probes-$mode" "./probes-$mode.exe"
  diff -u "$root/oxcaml/tests/backend/probes/t2.expected" \
    "$root/_ci_logs/probes-$mode.log"
done
cd "$root"
unset OCAMLLIB
run_stage fmt gmake -s fmt
git diff --exit-code
