# SH-69 · GitHub CI 在 glibc/musl 环境的可移植性缺陷

| 项 | 值 |
| --- | --- |
| 模块 | selfhost / CI |
| 严重度 | High（CI 红；安装与全量门禁在 Ubuntu 失败） |
| 锚点 | `v0.42.0`（`8458238b`） |
| 状态 | fixed（DEV，2026-11-14；v0.42.1） |

## 现象

GitHub Actions 的 `ubuntu-gcc` / `ubuntu-clang-smoke` / `macos-clang` 在 v0.42.0 失败。Podman 复现：

- Ubuntu 20.04 GCC 9：`Module.h.ct` 的 `setenv` 在 `-std=c99` 下隐式声明；`ctc.c` 种子编译报 `label at end of compound statement`；`p34_cache_mtime` 用 BSD `stat`；example 32 的 `%p` 输出 glibc 为 `(nil)`；`153_into_type_host` shim 宏 `-Wunused-value`。
- Ubuntu 20.04 clang：`_Atomic(void *)` 用 `0` 初始化触发 `-Wint-conversion`。
- Alpine musl：安装脚本与 `ct build` 可通过；上述修复不回归。

## 处置

- `Module.h.ct` 增加 `_POSIX_C_SOURCE 200809L`。
- 空 label 后发射 `;`，避免 C99 label-at-end。
- `fwd` 排序改用两个临时量，消除 GCC `-Wrestrict`。
- example 32 改为 `missing == 0 ? "null" : "non-null"`。
- p41 指针初值改 `(void *)0`。
- shim 宏去掉逗号右操作。
- `check-ast` 的 mtime 用 `stat -c %Y || stat -f %m`。

## 验证

- 本机 macOS `check-all: OK (11/11)`（v0.42.1）。
- Podman Ubuntu 20.04 GCC 9 `check-all: OK (11/11)`。
- Podman Ubuntu 20.04 clang `check-all: OK (11/11)`。
- Podman Alpine musl `install.sh` + `ct build examples/01_greeter` 成功。
- 版本 `v0.42.1`；fix 不打 tag（V-7）。
