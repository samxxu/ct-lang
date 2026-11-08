/*
 * 场景：一个粗略的 variant：tag + 匿名 union（int 或两个 short），
 * 外面再带 4 位状态。
 *
 * 匿名成员是 C11 语法：成员名提升进外层，o.i / o.lo / o.hi 都能直接访问。
 * CT 的解析器把提升后的名字写进外层字段表，因此 o.lo 的类型推断、
 * offsetof(..., lo) 的校验都与普通字段一致；生成物照原样发射嵌套记录。
 */
#include <stddef.h>
#include <stdio.h>

struct Outer {
    int tag;
    union {
        int i;
        struct {
            short lo;
            short hi;
        };
    };
    unsigned bits : 4;
};

int main(void)
{
    struct Outer o;

    o.tag = 1;
    o.i = 7;
    o.bits = 3;
    printf("%d %d %u\n", o.tag, o.i, o.bits);

    o.lo = 2;
    o.hi = 5;
    printf("%d %d\n", (int)o.lo, (int)o.hi);
    printf("%d %d\n", (int)sizeof(struct Outer),
           (int)offsetof(struct Outer, tag));
    return 0;
}
