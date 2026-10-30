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
work=$(mktemp -d /tmp/lwt-timing.XXXXXX)
opam source --yes lwt.5.9.2 --dir="$work/lwt"
timing_test="$work/lwt/test/unix/test_lwt_engine.ml"
sed -i '/let () = Unix.sleep 1 in/a\
        Printf.eprintf "sleep elapsed = %.9f\\n%!" \
          (Unix.gettimeofday () -. start);' "$timing_test"
sed -i '/Lwt.return (stop -. start >= 1.5)/i\
    Printf.eprintf "total elapsed = %.9f\\n%!" (stop -. start);' \
  "$timing_test"
cat "$timing_test"
sysctl kern.timecounter.hardware kern.timecounter.choice || true
opam pin add --no-action --yes lwt.5.9.2 "$work/lwt"
lwt_control() {
  local status=0
  opam install --keep-build-dir --yes --with-test lwt.5.9.2 || status=$?
  cat "$OPAMROOT"/log/lwt-*.out
  return "$status"
}
run_stage lwt-control lwt_control
for round in 1 2 3; do
  echo "Lwt clock control round $round"
  "$OPAM_SWITCH_PREFIX"/.opam-switch/build/lwt.5.9.2/\
_build/default/test/unix/main.exe
done
