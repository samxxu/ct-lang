/*
 * 场景：把赋值当值用——循环条件里边读边析构、if 里保存解析结果、
 * 右结合的 a = b = 0。
 *
 * CT 与 C 一致：括号里以及 if / while / do-while / switch / for 的条件里，
 * 赋值可以当取值使用；语句层的赋值完全不变。CT 的区别：目标是 own 变量
 * 时拒绝（所有权只在语句层记账）。
 */
#include <stdio.h>

static const char *input = "42";
static int pos;

static int next_char(void)
{
    int c;

    c = input[pos];
    if (c != '\0') {
        pos = pos + 1;
    }
    return c;
}

int main(void)
{
    int c;
    int value;
    int n;
    int a;
    int b;
    int r;

    value = 0;
    while ((c = next_char()) != '\0') {
        value = value * 10 + (c - '0');
    }
    printf("%d %d\n", value, pos);

    if ((n = value) > 0) {
        printf("%d\n", n);
    }

    r = (a = b = 3);
    printf("%d %d %d\n", r, a, b);
    return 0;
}
