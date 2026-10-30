#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <caml/mlvalues.h>
#include <caml/fail.h>

CAMLprim value jit_test_misalign_break(value unit)
{
#if defined(__FreeBSD__) && defined(__x86_64__)
  void *brk = sbrk(0);
  if (brk == (void *)-1) caml_failwith("sbrk(0) failed");
  if ((uintptr_t)brk % getpagesize() == 0 && sbrk(1) == (void *)-1)
    caml_failwith("sbrk(1) failed");
#endif
  return Val_unit;
}

CAMLprim value jit_test_check_contents(value addr, value contents)
{
  return Val_bool(memcmp((void *)Nativeint_val(addr), String_val(contents),
                         caml_string_length(contents)) == 0);
}
