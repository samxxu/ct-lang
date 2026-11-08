/*
 * 场景：类型词的组合面。volatile 计数器、restrict 指针参数、bool 返回值、
 * int32_t / size_t 形参，以及 static inline 与 inline static 两种顺序。
 *
 * CT 与 C 一致：声明原样发射，语义由 C 与对应头文件负责；
 * volatile / restrict 是类型的一部分，因此能出现在参数、返回值和局部上。
 * ct 只多一条限制：`inline` 后面必须是函数。
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

static volatile int ticks;

static inline int twice(int v)
{
    return v + v;
}

inline static int thrice(int v)
{
    return v + v + v;
}

static int first(int *restrict p, int n)
{
    return p[0] + n;
}

static bool positive(int32_t v)
{
    return v > 0;
}

static size_t count(const char *s)
{
    size_t n;

    n = 0;
    while (s[n] != '\0') {
        n = n + 1;
    }
    return n;
}

int main(void)
{
    int v;

    ticks = 1;
    ticks = ticks + 1;
    v = 7;
    printf("%d %d %d %d\n", ticks, twice(3), thrice(2), first(&v, 4));
    printf("%d %d %d\n", positive(1), positive(-1), (int)count("hello"));
    printf("%d %d\n", (int)sizeof(int32_t), (int)sizeof(size_t));
    return 0;
}
