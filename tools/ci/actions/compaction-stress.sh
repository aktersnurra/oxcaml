#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
prefix=$(cd "$1" && pwd)
work=$(mktemp -d /tmp/oxcaml-compaction.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$root/_ci_logs"
cp "$root/testsuite/tests/compaction/test_compact_multi.ml" "$work/"
git hash-object "$root/testsuite/tests/compaction/test_compact_multi.ml"
uname -a
(cd "$work" && "$prefix/bin/ocamlopt" -dcanonical-ids \
  test_compact_multi.ml -o compact.exe)
result=0
for round in 1 2 3; do
  echo "Native compaction round $round"
  output="$root/_ci_logs/compaction-$round.output"
  start=$(date +%s)
  timeout -s KILL 600 "$work/compact.exe" > "$output" 2>&1 &
  supervisor=$!
  (
    for sample in $(seq 1 20); do
      kill -0 "$supervisor" 2>/dev/null || break
      for pid in $(pgrep -P "$supervisor" || true); do
        date -u
        if [[ $(uname -s) == FreeBSD ]]; then
          procstat -t "$pid" || true
          procstat -r "$pid" || true
        else
          ps -L -p "$pid" -o pid,lwp,stat,time,wchan || true
        fi
        if [[ $round == 3 && $sample == 17 ]]; then
          if command -v lldb >/dev/null; then
            timeout -s KILL 30 lldb --batch -p "$pid" \
              -o 'thread backtrace all' -o detach -o quit || true
          elif command -v gdb >/dev/null; then
            timeout -s KILL 30 gdb --batch -p "$pid" \
              -ex 'thread apply all bt' -ex detach || true
          fi
        fi
      done
      sleep 30
    done
  ) > "$root/_ci_logs/compaction-$round.processes" 2>&1 &
  watcher=$!
  status=0
  wait "$supervisor" || status=$?
  elapsed=$(( $(date +%s) - start ))
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  echo "Compaction round $round: status=$status elapsed=$elapsed seconds"
  cat "$output"
  if [[ $status != 0 || -s $output ]]; then
    result=1
    cat "$root/_ci_logs/compaction-$round.processes"
  fi
done
exit "$result"
