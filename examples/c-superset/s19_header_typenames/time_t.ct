/*
 * 场景：时间戳工具。time_t 只由 <time.h> 声明，ct 不认识它，但声明位置
 * 的「未知标识符 + 声明符名」会按类型处理，拼写原样发射。
 *
 * CT 与 C 的区别：ct 不展开 #include，头文件里的 typedef 对解析器是未知
 * 名字。判据是「既不是已登记的类型，也不是变量/函数，还不是语句关键字」。
 * 转换与 sizeof 里同样可用，因此 (time_t)raw 不会退化成函数调用。
 */
#include <stdio.h>
#include <time.h>

static time_t g_base;

struct Stamp {
    time_t when;
};

static void show(time_t t)
{
    printf("%ld\n", (long)t);
}

int main(void)
{
    time_t now;
    time_t *ref;

    now = (time_t)7;
    ref = &now;
    g_base = *ref;
    show(g_base);
    printf("%d\n", (int)sizeof(time_t));
    return 0;
}
