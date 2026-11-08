/*
 * 场景：进程级的自增 ID 与一次性字符串。两者都靠函数内 static 跨调用保持
 * 取值；未写初始化器的 static 按 C 规则零初始化。
 *
 * CT 与 C 一致：生成物原样发射 static 前缀，初始化器不折叠（是否常量由 C
 * 判断）。区别是 ct 会把 static 声明照常登记进变量表，所以成员访问、
 * 数组下标的类型推断不变；static own 被拒绝（静态对象不归作用域管）。
 */
#include <stdio.h>

static int next_id(void)
{
    static int n;
    n = n + 1;
    return n;
}

static const char *greeting(void)
{
    static const char *msg = "hi";
    return msg;
}

static int ledger_sum(void)
{
    static int ledger[3];
    int i;
    int total;

    total = 0;
    for (i = 0; i < 3; i++) {
        total = total + ledger[i];
    }
    ledger[0] = ledger[0] + 1;
    return total;
}

int main(void)
{
    printf("%d %d %d\n", next_id(), next_id(), next_id());
    printf("%s %s\n", greeting(), greeting());
    printf("%d %d %d\n", ledger_sum(), ledger_sum(), ledger_sum());
    return 0;
}
