#include "tick.shim.h"

// 这块状态不属于任何 ct 对象，只属于这个 C 链接单元。
static int g_ticks = 0;

int tick_bump(int by) {
    g_ticks = g_ticks + by;
    return g_ticks;
}
