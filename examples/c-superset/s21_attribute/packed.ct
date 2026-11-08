/*
 * 场景：一个 packed 的线格式记录、一个 16 字节对齐的全局计数器，以及
 * 给自定义日志函数挂 printf 风格格式检查。
 *
 * CT 与 C 的区别：ct 只把 __attribute__((...)) 原样带进生成物，语义完全
 * 交给 C 编译器。接受的位置包括函数声明/定义、形参、字段、全局变量、
 * typedef 别名与记录体的 } 之后；写在声明符之前的属性见 header_order。
 *
 * L0 实测：记录体之后的 `} __attribute__((packed));` 会被 L0 丢掉，生成的
 * C 里 sizeof(struct Packed) 变成 8（ct-ast 是 5）。前缀属性（如 prefix.ct
 * 里的 aligned/unused）L0 能保留。因此本文件标 l0=no。
 */
#include <stdarg.h>
#include <stdio.h>

struct Packed {
    char c;
    int i;
} __attribute__((packed));

int g_tick __attribute__((aligned(16)));

static void trace(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

static void trace(const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
}

int main(void)
{
    struct Packed p;

    p.c = 'a';
    p.i = 0x01020304;
    g_tick = g_tick + 1;
    trace("tick %d\n", g_tick);
    printf("%d %d\n", (int)sizeof(p), (int)((unsigned long)&g_tick % 16));
    return 0;
}
