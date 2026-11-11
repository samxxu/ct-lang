/* A recipe cannot spell a definition, so the state and its operations live in
   ops.shim.c; this header is what the consumer sees. */
struct ct_slot;

struct ct_slot *ct_slot_new(void);
int ct_slot_bump(struct ct_slot *s, int by);
int ct_slot_total(struct ct_slot *s);
