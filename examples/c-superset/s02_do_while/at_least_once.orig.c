/*
 * 场景：先执行、后判断的倒计时。do-while 的体至少跑一次，
 * 这与 while 的「先判断」形成对照。
 *
 * CT 与 C 完全一致：do { ... } while (c); 原样发射。注意 C 要求
 * while (...) 后面的分号，ct 也要求。
 */
#include <stdio.h>

static int drain(int start)
{
    int n;

    n = 0;
    do {
        n = n + 1;
        start = start - 1;
    } while (start > 0);
    return n;
}

int main(void)
{
    int i;
    int once;

    /* 条件一开始就为假，但体仍执行一次 */
    i = 10;
    once = 0;
    do {
        once = once + 1;
    } while (i < 3);

    printf("%d %d %d %d\n", once, drain(0), drain(1), drain(4));
    return 0;
}
