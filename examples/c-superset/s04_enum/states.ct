/*
 * 场景：连接状态机。enum 成员既做状态值，也做数组下标与 switch 标签。
 *
 * CT 与 C 一致的地方：无初值成员自增、显式初值、尾逗号、typedef enum 都
 * 原样发射，值由 C 折叠。CT 的区别：成员在文件作用域按命名空间 mangling
 * 发射（本文件在全局命名空间，所以看不出来），裸名 `State` 与
 * `enum State` 两种拼写都接受。
 */
#include <stdio.h>

enum State {
    ST_IDLE,
    ST_OPEN = 5,
    ST_BUSY,
    ST_CLOSED,
};

typedef enum Mode {
    MODE_FAST = 1,
    MODE_SLOW = 2
} Mode;

static int weight(enum State s)
{
    switch (s) {
    case ST_IDLE:
        return 0;
    case ST_OPEN:
        return 10;
    case ST_BUSY:
        return 11;
    case ST_CLOSED:
        return 12;
    default:
        return -1;
    }
}

static int mode_of(Mode m)
{
    return (int)m;
}

int main(void)
{
    int names[ST_CLOSED + 1];
    int i;

    for (i = 0; i <= ST_CLOSED; i++) {
        names[i] = i;
    }
    printf("%d %d %d %d\n", ST_IDLE, ST_OPEN, ST_BUSY, ST_CLOSED);
    printf("%d %d %d\n", weight(ST_OPEN), names[6], mode_of(MODE_SLOW));
    return 0;
}
