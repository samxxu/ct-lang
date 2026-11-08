/*
 * 场景：一整张关键字表。初始化器文本远超旧节点 160 字节的 text 字段，
 * 用来验证「花括号初始化器不再按小缓冲区截断」。
 *
 * CT 与 C 一致：长列表、尾逗号、字符串字面量都完整保留；ct 把最终文本
 * 存进 arena 的字符串池（单个初始化器 4 KiB，重写后 16 KiB）。
 */
#include <stdio.h>
#include <string.h>

static const char *kw[] = {
    "void", "char", "short", "int", "long", "float", "double",
    "signed", "unsigned", "_Bool", "const", "volatile", "restrict",
    "struct", "union", "enum", "sizeof", "switch", "case", "default",
    "while", "for", "do", "break", "continue", "return", "goto",
    "typedef", "static", "extern", "inline", "sizeof",
};

int main(void)
{
    int n;

    n = (int)(sizeof(kw) / sizeof(kw[0]));
    printf("%d\n", n);
    printf("%s %s %s\n", kw[0], kw[15], kw[30]);
    printf("%d %d\n", (int)strlen(kw[0]), (int)strlen(kw[15]));
    return 0;
}
