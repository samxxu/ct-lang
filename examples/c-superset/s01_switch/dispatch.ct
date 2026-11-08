/*
 * 场景：命令行子命令分派。一次 switch 把数字 verb 映射到退出码。
 *
 * CT 与 C 在这里完全一致：switch / case / default / break 按原样发射，
 * case 的取值（枚举成员）由 ct 归一化成 C 名字，最终由 C 编译器折叠。
 * 这个文件不依赖任何 CT 扩展，dispatch.orig.c 是它的逐字节副本，
 * 直接用 cc 编译得到同样的输出。
 */
#include <stdio.h>

enum Verb {
    VERB_ADD = 1,
    VERB_DEL = 2,
    VERB_LIST = 4
};

static int run(int verb)
{
    int rc;

    rc = -1;
    switch (verb) {
    case VERB_ADD:
        rc = 10;
        break;
    case VERB_DEL:
    case 3:                 /* 两个标签共享下一段语句 */
        rc = 20;
        break;
    case VERB_LIST:
        rc = 30;
        break;
    default:
        rc = 0;
        break;
    }
    return rc;
}

int main(void)
{
    printf("%d %d %d %d\n", run(1), run(2), run(3), run(4));
    printf("%d\n", run(9));
    return 0;
}
