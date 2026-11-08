/*
 * 场景：把各种浮点拼写一次性读出来。字面量按原文发射，后缀与指数写法
 * 都不会丢；转成 int 时按 C 规则截断。
 *
 * CT 与 C 一致：`<digits>.<digits>`、`.5`、`1.5e3`、`f/F/l/L` 后缀都接受。
 * 区别在诊断面：浮点字面量不是整数常量表达式，`case 1.5:` 会被 ct 拒绝。
 */
#include <stdio.h>

int main(void)
{
    double d;
    float f;
    long double ld;
    double tiny;
    double big;

    d = 1.5;
    f = 2.25f;
    ld = 3.5L;
    tiny = .5;
    big = 1.5e3;

    printf("%d %d %d %d %d\n", (int)d, (int)f, (int)ld, (int)tiny, (int)big);
    printf("%d %d\n", (int)9.99, (int).5e1);
    return 0;
}
