# 54_freestanding_alloc —— 裸机生成契约的最小样例

| 项 | 值 |
| --- | --- |
| 能力 | `--freestanding`（不拉 libc / 堆）与 `--alloc`（把 malloc/free 映射到目标符号） |
| 源码 | `src/main.ct`（约 20 行） |
| 门禁 | `test/run.sh` 的 near-phase 层：`--freestanding --alloc my_alloc,my_free` 生成 C，`-ffreestanding -nostdlib -c` 编译，`nm -u` 只允许 `my_alloc`/`my_free` |

`--freestanding` 下编译器不补系统头，`malloc`/`free` 的原型由 `#ct-raw`
显式带入；`--alloc` 把调用改写成目标符号。产物里出现 `my_alloc`/`my_free`
未定义符号是预期——它们由目标运行时提供。本项目只证明生成器没有偷偷回退到
libc，不提供运行时实现。

> 已知边界：`Box`/`new` 的 helper 仍直接发射 `malloc`（`--alloc` 不覆盖该路径），
> 所以本样例用源级 `malloc`/`free` 演示映射，不把 Box 与 `--freestanding` 混用。
