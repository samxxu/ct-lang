#ifndef SYS_SHIM_H
#define SYS_SHIM_H

// 用固定倍率模拟“每毫秒 3 个 tick”，保证样例在任何机器上输出一致。
static inline int sys_ticks(int ms) { return ms * 3; }

#endif
