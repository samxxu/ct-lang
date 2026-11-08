/*
 * 场景：一个缓冲区描述符，一条声明写多个字段：`unsigned len, cap;`
 * 共享类型，`int *data, count;` 里的星号只属于 data。
 *
 * CT 与 C 一致：第一个声明符的拼写作为共享类型，后续声明符各自补上
 * 自己的星号、维度与位宽；位域也可以成列。字段表按名字逐个登记，
 * 成员访问与 offsetof 不受影响。
 */
#include <stdio.h>

struct Buf {
    char name[8];
    unsigned len, cap;
    int *data, count;
    unsigned a : 3, b : 5;
};

int main(void)
{
    struct Buf b;
    int cell;

    cell = 42;
    b.data = &cell;
    b.count = 1;
    b.len = 3;
    b.cap = 8;
    b.a = 5;
    b.b = 17;
    b.name[0] = 'x';
    b.name[1] = '\0';

    printf("%s %u %u %d %d\n", b.name, b.len, b.cap, *b.data, b.count);
    printf("%u %u %d %d\n", b.a, b.b, (int)sizeof(b.data), (int)sizeof(b.count));
    return 0;
}
