#ifndef IO_SHIM_H
#define IO_SHIM_H

// 真实库会把这个 struct 藏在 .c 里，只暴露指针；
// 为了样例能编译，这里给出完整定义。
struct ct_handle {
    int fd;
};

static inline int io_fd(struct ct_handle *h) { return h->fd; }

#endif
