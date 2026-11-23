# 55_c_boundary_shim —— 声明式 C 边界的最小样例

| 项 | 值 |
| --- | --- |
| 能力 | `.m.ct` 静态映射 + `<base>.shim.h` / `<base>.shim.c` |
| 源码 | `src/main.ct`、`src/lib/lib.m.ct`、`src/lib/lib.shim.*` |
| 门禁 | `test/run.sh` 的 near-phase 层；`check-warnings.sh` 的 src-layout build 段 |

映射单元只写 `recipe`，调用点在生成的 C 里是一条普通 C 调用；shim 头承载
recipe 拼不出的形状（`errno` 这类全局），shim 源提供实现。`lib::Io.clear()`
先把 `errno` 清零，再读一次，证明读到的是 C 全局而不是本进程的旧值。
