/*
 * 场景：把四种整数字面量后缀写在一起，验证大小写与顺序都接受。
 *
 * CT 与 C 的区别：后缀只影响拼写，不改变数值；发射时规范化为「先 U 后 L」
 * （0xFFu -> 0xFFU，16l -> 16L，1ll -> 1LL）。值仍存放在 long 里，超过
 * LONG_MAX 的 ULL 会按 long 回绕——这是既有的容量边界。
 */
#include <stdio.h>

int main(void)
{
    unsigned long a;
    long b;
    unsigned long long c;
    long d;
    unsigned long e;
    unsigned f;
    long long g;
    unsigned long long h;

    a = 0xFFu;
    b = 0777L;
    c = 1ULL;
    d = 16l;
    e = 0x10U;
    f = 0x1fU;
    g = 1ll;
    h = 2ull;

    printf("%lu %ld %llu %ld %lu %u\n", a, b, c, d, e, f);
    printf("%lld %llu\n", g, h);
    printf("%d %d\n", (int)sizeof(0ULL), (int)sizeof(16l));
    return 0;
}
