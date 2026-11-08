/*
 * 场景：前缀自增/自减作表达式值，以及它们与后缀形式的区别。
 *
 * CT 与 C 一致：前缀运算符与其它一元运算符同级，操作数是再一个一元表达式，
 * 因此 s[--n]、*--p、独立的 --i 都按 C 的读法成立；前缀的值是更新后的值。
 */
#include <stdio.h>

int main(void)
{
    int a[5];
    int i;
    int j;
    int k;
    int n;
    int *p;

    a[0] = 1;
    a[1] = 2;
    a[2] = 3;
    a[3] = 4;
    a[4] = 5;

    i = 5;
    j = ++i;
    k = i++;
    printf("%d %d %d\n", i, j, k);

    i = 7;
    --i;
    printf("%d\n", i);

    n = 4;
    a[--n] = 9;
    printf("%d %d\n", n, a[3]);

    p = &a[2];
    printf("%d\n", *(--p));
    return 0;
}
