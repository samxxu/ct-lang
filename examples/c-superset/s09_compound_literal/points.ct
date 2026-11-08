/*
 * 场景：二维点。复合字面量 `(struct Point){ ... }` 生成一个临时对象，
 * 可以直接赋给变量、当实参、从函数返回。
 *
 * CT 与 C 一致：花括号按声明的初始化器处理；函数内是自动存储期。
 * 带 trait 的 struct 会由 ct 补 vptr 项（本文件没有 trait）。
 */
#include <stdio.h>

struct Point {
    int x;
    int y;
};

static int sum(struct Point p)
{
    return p.x + p.y;
}

static struct Point make(int x, int y)
{
    return (struct Point){ x, y };
}

int main(void)
{
    struct Point p;
    struct Point q;

    p = (struct Point){ 1, 2 };
    q = make(5, 6);
    printf("%d %d\n", p.x, sum((struct Point){ 3, 4 }));
    printf("%d %d\n", q.x, q.y);
    return 0;
}
