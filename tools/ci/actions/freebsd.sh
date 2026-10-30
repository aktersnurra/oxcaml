#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mkdir -p _ci_logs
work=$(mktemp -d /tmp/sleep-control.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/sleep.c" <<'C'
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/time.h>
#include <time.h>
static volatile sig_atomic_t ticks;
static void tick(int signal) { (void)signal; ticks++; }
static double now(clockid_t id) {
  struct timespec ts;
  if (clock_gettime(id, &ts) != 0) { perror("clock_gettime"); return -1; }
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}
int main(void) {
  struct sigaction action = {0};
  action.sa_handler = tick;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGALRM, &action, NULL) != 0) return 1;
  for (int signals = 0; signals < 2; signals++) {
    struct itimerval timer = {{0, signals ? 10000 : 0},
                             {0, signals ? 10000 : 0}};
    if (setitimer(ITIMER_REAL, &timer, NULL) != 0) return 1;
    for (int round = 0; round < 10; round++) {
      struct timespec delay = {1, 0};
      double wall = now(CLOCK_REALTIME), mono = now(CLOCK_MONOTONIC);
      int ret, interrupted = 0;
      do {
        ret = nanosleep(&delay, &delay);
        if (ret == -1 && errno == EINTR) interrupted++;
      } while (ret == -1 && errno == EINTR);
      double mono_end = now(CLOCK_MONOTONIC);
      double wall_end = now(CLOCK_REALTIME);
      printf("signals=%d round=%d ret=%d wall=%.9f mono=%.9f eintr=%d\n",
             signals, round, ret, wall_end-wall, mono_end-mono, interrupted);
      fflush(stdout);
    }
  }
  return 0;
}
C
cc -Wall -Wextra -Werror "$work/sleep.c" -o "$work/sleep"
sysctl kern.timecounter.hardware kern.timecounter.choice
"$work/sleep" 2>&1 | tee _ci_logs/sleep-control.log
