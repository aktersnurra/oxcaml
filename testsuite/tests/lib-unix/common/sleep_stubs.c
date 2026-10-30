#include <time.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

CAMLprim value sleep_test_monotonic_time(value unit)
{
  CAMLparam1(unit);
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) == -1)
    caml_failwith("clock_gettime failed");
  CAMLreturn(caml_copy_double((double)now.tv_sec + now.tv_nsec / 1e9));
}
