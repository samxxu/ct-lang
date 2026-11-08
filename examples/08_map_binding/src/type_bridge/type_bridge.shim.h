#ifndef TYPE_BRIDGE_SHIM_H
#define TYPE_BRIDGE_SHIM_H

/* The C handle the type host is keyed on. The mapping unit turns
   `FileHandle` into `struct ct_file *`; this struct is what a pointer
   actually points at. */
struct ct_file {
    int fd;
    int pos;
};

static inline int ct_file_read(struct ct_file *f, int n) {
    f->pos = f->pos + n;
    return f->pos;
}

static inline int ct_file_write(struct ct_file *f, int n) {
    f->pos = f->pos + n;
    return n;
}

static inline int ct_file_tell(struct ct_file *f) {
    return f->pos;
}

#endif
