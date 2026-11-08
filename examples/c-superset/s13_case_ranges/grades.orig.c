/*
 * 场景：百分制成绩分档。三段连续区间用 GNU/C23 的 case 范围标签表达，
 * 比「一堆单值标签」更贴近区间语义。
 *
 * CT 与 C 一致：`case <low> ... <high>:` 原样发射；两端都是整数常量
 * 表达式。范围是 GNU 扩展（C23 正式化），clang 与 gcc 在 -std=c99 下
 * 都接受且不告警——这是该特性的编译期依赖。
 */
#include <stdio.h>

static char grade(int score)
{
    switch (score) {
    case 0 ... 59:
        return 'F';
    case 60 ... 89:
        return 'P';
    case 90 ... 100:
        return 'A';
    default:
        return '?';
    }
}

int main(void)
{
    printf("%c %c %c %c\n", grade(0), grade(59), grade(60), grade(89));
    printf("%c %c %c\n", grade(90), grade(100), grade(101));
    return 0;
}
