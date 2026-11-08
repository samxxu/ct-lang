/*
 * 场景：一张固定宽度的表结构。维度写成宏乘倍数、位移和括号求和，
 * 长度由 C 折叠。
 *
 * CT 与 C 一致：方括号里除数字与单个名字外，还可以写表达式；多 token 的
 * 表达式原样保留，单个名字若解析为枚举成员则按 mangling 后的 C 拼写发射。
 * 维度只影响「是不是数组」的判定，对成员访问、sizeof、offsetof 没有区别。
 */
#include <stdio.h>

#define WIDTH 4
#define SLOTS (WIDTH * 2)

static int g_tbl[WIDTH * 2];

struct Box {
    int cells[SLOTS];
    char name[(1 << 3)];
    short pairs[WIDTH + 1];
};

int main(void)
{
    struct Box b;
    int i;

    g_tbl[0] = 9;
    for (i = 0; i < SLOTS; i++) {
        b.cells[i] = i;
    }
    for (i = 0; i < WIDTH + 1; i++) {
        b.pairs[i] = (short)i;
    }
    b.name[0] = 'b';
    b.name[1] = '\0';

    printf("%d %d %d\n", (int)(sizeof(g_tbl) / sizeof(g_tbl[0])),
           (int)(sizeof(b.cells) / sizeof(b.cells[0])),
           (int)(sizeof(b.pairs) / sizeof(b.pairs[0])));
    printf("%s %d %d\n", b.name, b.cells[3], b.pairs[4]);
    return 0;
}
