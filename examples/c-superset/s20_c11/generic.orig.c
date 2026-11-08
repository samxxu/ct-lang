/*
 * 场景：用 _Generic 在编译期按实参类型选一个整数码，避免为 int/double/
 * 字符串各写一个函数。
 *
 * CT 与 C 的区别：_Generic 整段透传——控制表达式与每个分支都交给 C，
 * ct 不读分支。因此分支里**不能**出现需要 ct 重写的 trait 调用/装箱；
 * 这里的分支都是 C 编译器自己能接受的常量。
 */
#include <stdio.h>

#define KIND(x) _Generic((x), int: 1, double: 2, char *: 3, default: 0)

int main(void)
{
    int n;
    double d;
    char *s;

    n = 0;
    d = 0.0;
    s = "x";

    printf("%d %d %d %d\n", KIND(n), KIND(d), KIND(s), KIND(1.5f));
    printf("%d\n", _Generic(n + 1, int: 10, default: 20));
    return 0;
}
