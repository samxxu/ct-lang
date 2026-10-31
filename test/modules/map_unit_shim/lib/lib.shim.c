#include "lib.shim.h"

static int calls;

int ct_shim_next(void)
{
    calls++;
    return calls;
}
