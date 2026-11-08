/*
 * 场景：在二维表里找第一对满足条件的下标，找到后直接跳出两层循环。
 *
 * CT 与 C 一致：goto 与标签都是函数作用域的，生成物同形；不同函数可以
 * 复用同名标签。区别是 ct 在解析期就校验「目标必须在同一函数里」，
 * 并把重复标签（即使分处不同块）当作错误。
 */
#include <stdio.h>

static int find_pair(int limit, int *out_i, int *out_j)
{
    int i;
    int j;
    int found;

    found = 0;
    for (i = 0; i < limit; i++) {
        for (j = 0; j < limit; j++) {
            if (i * i + j * j == 25 && i != j) {
                *out_i = i;
                *out_j = j;
                found = 1;
                goto done;
            }
        }
    }
done:
    return found;
}

static int find_self(int n)
{
    int i;

    for (i = 0; i < n; i++) {
        if (i * i == 16) {
            goto done;
        }
    }
    i = -1;
done:
    return i;
}

int main(void)
{
    int a;
    int b;

    a = 0;
    b = 0;
    printf("%d %d %d\n", find_pair(8, &a, &b), a, b);
    printf("%d\n", find_self(10));
    return 0;
}
