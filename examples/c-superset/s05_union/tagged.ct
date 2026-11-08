/*
 * 场景：带标签的 variant。tag 决定当前有效成员，写入与读取走同一条分支。
 *
 * CT 与 C 一致：union 与 struct 共用记录文法，typedef union { ... } Alias
 * 两种写法都接受。union 没有 use 子句（成员共享存储，追加 vptr 会冲突）。
 * sizeof 等于最大成员，所有成员的 offsetof 都是 0——这两点由 C 保证。
 */
#include <stddef.h>
#include <stdio.h>

union Value {
    int i;
    char c;
    long long ll;
};

struct Tagged {
    int kind;
    union Value value;
};

static int store_int(struct Tagged *t, int v)
{
    t->kind = 0;
    t->value.i = v;
    return t->value.i;
}

static char store_char(struct Tagged *t, char v)
{
    t->kind = 1;
    t->value.c = v;
    return t->value.c;
}

static long long store_ll(struct Tagged *t, long long v)
{
    t->kind = 2;
    t->value.ll = v;
    return t->value.ll;
}

int main(void)
{
    struct Tagged t;

    printf("%d %d %c %lld\n", store_int(&t, 42), t.kind,
           store_char(&t, 'q'), store_ll(&t, 1234567890123LL));
    printf("%d %d %d %d\n", (int)sizeof(union Value),
           (int)offsetof(union Value, i), (int)offsetof(union Value, c),
           (int)offsetof(union Value, ll));
    return 0;
}
