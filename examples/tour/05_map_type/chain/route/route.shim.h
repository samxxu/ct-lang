#ifndef ROUTE_SHIM_H
#define ROUTE_SHIM_H

struct Path {
    int hops;
};

// 只增加跳数；name 故意不参与计算，表示“真实实现可以更重”，
// 但链式展开的开销与 name 无关。
static inline struct Path route_seg(struct Path p, char *name) {
    (void)name;
    p.hops = p.hops + 1;
    return p;
}

static inline int route_hops(struct Path p) { return p.hops; }

#endif
