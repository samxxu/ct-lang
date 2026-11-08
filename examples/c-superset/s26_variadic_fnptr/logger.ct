/*
 * 场景：日志接口。typedef 出一个变参函数指针，结构体字段、全局变量都
 * 可以持有它，通过指针调用时多余实参原样透传给 vprintf。
 *
 * CT 与 C 一致：`...` 属于函数指针签名的拼写，typedef / 字段 / 全局 /
 * 局部声明都自动带上它；`...` 前必须至少有一个具名参数。
 */
#include <stdarg.h>
#include <stdio.h>

typedef int (*logger_fn)(const char *fmt, ...);

struct Sink {
    const char *name;
    logger_fn log;
};

static int say(const char *fmt, ...)
{
    va_list ap;
    int r;

    va_start(ap, fmt);
    r = vprintf(fmt, ap);
    va_end(ap);
    return r;
}

static logger_fn g_log = say;

int main(void)
{
    struct Sink s;

    s.name = "sink";
    s.log = say;
    g_log("g %d\n", 1);
    s.log("s %s %d\n", s.name, 2);
    return 0;
}
