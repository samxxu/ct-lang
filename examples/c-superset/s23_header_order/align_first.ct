/*
 * 场景：头文件顺序的另一半：_Alignas / __attribute__ 写在存储类之前。
 *
 * CT 与 C 的区别：源里写 `_Alignas(16) static int g;`，ct 统一发射为
 * 规范顺序 `static _Alignas ( 16 ) int g;`；局部变量也接受属性前缀写法，
 * 发射时挪到声明尾部、`=` 之前。语义（能否用于某个对象）仍由 C 判断。
 */
#include <stdio.h>

_Alignas(16) static int g;
__attribute__((aligned(32))) static int h;

int main(void)
{
    _Alignas(8) static int l;
    __attribute__((unused)) int spare;
    int trailing __attribute__((unused));

    g = 1;
    h = 2;
    l = 3;
    spare = 7;
    printf("%d %d %d %d\n", g, h, l, spare);
    printf("%d %d\n", (int)((unsigned long)&g % 16),
           (int)((unsigned long)&h % 32));
    return 0;
}
