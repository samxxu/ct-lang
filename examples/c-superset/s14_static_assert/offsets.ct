/*
 * 场景：用断言把「首字段偏移为 0」和 union 大小钉住。offsetof 是 ct 内建，
 * 在 _Static_assert 的常量条件里同样可用。
 *
 * CT 与 C 一致：断言失败时是 C 编译器的错误消息；ct 只负责把断言原样
 * 发射到正确位置。
 */
#include <stddef.h>
#include <stdio.h>

typedef struct Header {
    unsigned char magic;
    unsigned short len;
    unsigned int seq;
} Header;

typedef union Number {
    int i;
    long long ll;
} Number;

_Static_assert(offsetof(Header, magic) == 0, "magic is first");
_Static_assert(offsetof(union Number, ll) == 0, "union members overlap");
_Static_assert(sizeof(Number) == sizeof(long long), "union is the largest member");

int main(void)
{
    printf("%d %d %d\n", (int)sizeof(Header), (int)sizeof(Number),
           (int)offsetof(Header, magic));
    return 0;
}
