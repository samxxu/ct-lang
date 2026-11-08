/*
 * 场景：文件权限位。一个 unsigned 里塞 read/write/exec 三个 1 位标志、
 * 5 位无名填充，再加 8 位 uid。
 *
 * CT 与 C 一致：位宽是不折叠的整数常量表达式，生成物原样发射；
 * 无名位域只占位、不进成员表。赋值超出位宽时按 C 的规则截断（uid=300
 * 读回来是 44），这正是要看的行为。
 */
#include <stdio.h>

struct Perm {
    unsigned read : 1;
    unsigned write : 1;
    unsigned exec : 1;
    unsigned : 5;               /* 填充位，无名字 */
    unsigned uid : 8;
};

int main(void)
{
    struct Perm p;
    unsigned raw;

    raw = 300;
    p.read = 1;
    p.write = 0;
    p.exec = 1;
    p.uid = raw;

    printf("%u %u %u %u\n", p.read, p.write, p.exec, p.uid);
    printf("%d\n", (int)sizeof(struct Perm));
    return 0;
}
