/*
 * 场景：一整块「只有副作用、没有循环体」的代码：for 的空体、while 的
 * 空体、if 的空分支、switch 里只有空语句的 case，以及标签后的空语句。
 *
 * CT 与 C 一致：`;` 是空语句，不发射任何字符；它也是「标签后必须有语句」
 * 的最省写法（`done: ;`）。CT 的区别：`case 3: ;` 合法，`case 3: int x;`
 * 仍被拒绝。
 */
#include <stdio.h>

static int scan_to(int limit)
{
    int i;

    i = 0;
    while (i++ < limit) ;       /* 循环体是空语句 */
    return i;
}

int main(void)
{
    int i;
    int n;

    for (i = 0; i < 3; i++) ;   /* 空体，只保留步进 */
    n = i;

    if (n == 3) ;
    else n = 9;

    switch (n) {
    case 3:
        ;                       /* case 后最省的非声明语句 */
        break;
    default:
        n = 0;
        break;
    }

    if (n == 3) {
        goto done;
    }
    n = -1;
done:
    ;

    printf("%d %d %d\n", n, scan_to(4), i);
    return 0;
}
