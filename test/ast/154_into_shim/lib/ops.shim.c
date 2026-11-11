#include "ops.shim.h"
#include "types.h"

int ct_slot_bump(struct ct_slot *s, int by)
{
    s->n = s->n + by;
    s->hits = s->hits + 1;
    return s->n;
}

int ct_slot_total(struct ct_slot *s)
{
    return s->n;
}
