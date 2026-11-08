/*
 * 场景：for 的两个子句都用逗号表达式：初始化里同时设两个游标，步进里
 * 一个加、一个减；另外演示语句层的 `i = 1, j = 2;`。
 *
 * CT 与 C 一致：表达式语句、for 的初始化子句与步进子句共用同一个解析
 * 入口，每个操作数按赋值表达式解析，所以读法与 C 相同（左到右）。
 */
#include <stdio.h>

int main(void)
{
    int i;
    int j;
    int sum;

    sum = 0;
    for (i = 0, j = 10; i < 3; i++, j--) {
        sum = sum + j;
    }
    printf("%d %d %d\n", i, j, sum);

    i = 0;
    j = 0;
    i = 1, j = 2;
    printf("%d %d\n", i, j);
    return 0;
}
