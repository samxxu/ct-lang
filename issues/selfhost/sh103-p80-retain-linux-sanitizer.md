---
id: SH-103
title: "p80_retain 在 Ubuntu clang/gcc 的 sanitizer 段失败（macOS 绿）"
status: open
area: selfhost
severity: P1
opened: 2026-11-21
confirmed-by: CI-44804723025
---

# SH-103 p80_retain Linux sanitizer 段失败

## 现象

v0.82.0 起 CI `ubuntu-clang-smoke` 与 `ubuntu-gcc` 的 AST 套件报：
`FAIL PH-80-SH-102 retain (D-013 §3 automatic retain trace, ASan/UBSan, escapes)`；
探针输出停在 `ok struct_lit -fsanitize=address`，无最终 `p80_retain: OK`；
macOS clang 同版本全绿。常规运行、UBSan 的 retain/jump/field_reassign 均 ok。

## 复现

CI run `44804723025`；本地 macOS `sh test/ast/p80_retain.sh <ct-ast>` 绿。

## 期望

两平台 `p80_retain: OK`；若 Linux 触发真实 ASan/UBSan 报告，应修产品代码而不是跳过。

## 处置

待查：在 Linux 容器/CI 上取 `struct_lit` sanitizer 完整 stderr；`test/ast/p80_retain.sh`
现已输出完整 stderr（commit 8dfb34c7 的诊断改动）。修复前 PH-82 tag 的 CI 为红。

## 处置（DEV，2026-11-21）：**fixed**

`status` 保持 REV/CI 写的 `open`（5.4：DEV 只写正文处置段，由 REV 复核后改 `verified`）。
根因与 `struct_lit` sanitizer 失败同源：字段定义表压缩时的 `snprintf` 自拷贝。

### 根因

`Emitter.h.ct` 的字段定义表在两个压缩点用

```c
snprintf(g_sb.fpath[j], MAX_TEXT, "%s", g_sb.fpath[i]);   /* i == j 时 */
```

当没有条目被丢弃（`i == j`）时，这是**重叠对象上的 `snprintf`**，C 标准未定义：

- macOS libc 原地复制，路径保持 → 全绿；
- Linux aarch64 / glibc（容器 clang 18.1.8 / Fedora 40）返回**空串**，字段路径被清空。

空路径使 `sb_field_if_merge` 插入无名条目，后续 `sb_field_find` 查不到：

- `field_branch_else`：分支后的重赋不 release 旧值 → `final live=1`（泄漏）；
- `field_branch0` / `field_branch_rt` / `field_switch`：`maybe` 条目查不到 → 负例被接受
  （R6a 在 Linux 失效）。

不是 `char` 符号、指针哈希或结构填充问题；是标准库对 UB 的实现差异。

### 修复

两个压缩点只在真正移动时复制（`if (j != i)` / `if (j2 != i2)`），原地条目保持不变。
同一份生成的 ct-ast C 在 macOS 与 Linux 各自编译后行为一致；macOS 上同样存在的 UB 一并消除。

### 提交

- `210f0209` `test(ct-ast): SH-103 红（Linux 字段表压缩）`（新增 `field_branch_two` + 红证，baseline `69819d44`）
- `1764b4d6` `fix(ct-ast): SH-103 字段表压缩不得自拷贝`
- 收口提交：v0.82.1（版本、卡 §7.9.8、本处置段、golden）

### 红 → 绿（Linux 容器 aarch64 / clang 18 / glibc；macOS 对照）

```console
# Linux，修复前（baseline 69819d44 的 /tmp/ct-ast）
$ CC=clang sh test/ast/p80_retain.sh /tmp/ct-ast
FAIL p80/retain: field_branch_else behaviour
  -after ifelse refs=1 live=1   +after ifelse refs=1 live=2
  -final live=0                 +final live=1
FAIL p80/retain: field_branch_two behaviour
  -after ifelse a=1 b=1 live=2  +after ifelse a=1 b=1 live=4
  -final live=0                 +final live=2
FAIL p80/retain: field_branch0 / field_branch_rt / field_switch
  accepted a negative

# Linux，修复后（同一份生成的 C，容器内 clang 编译）
$ CC=clang sh test/ast/p80_retain.sh /tmp/ct-ast-fixed
51 ok … p80_retain: OK
$ ./field_branch_two -> after ifelse a=1 b=1 live=2 / final live=0

# macOS，修复后
$ sh test/ast/p80_retain.sh <ct-ast>
51 ok … p80_retain: OK
```

其余 Linux 探针（`p80_layout` / `p80_literal` / `p80_methods` / `p80_cstr` / `p80_migrate`）与
`check-ast` 关键段见交付报告。

### 仍未覆盖

- 其它依赖 libc 未定义行为的写法（如非重叠前提下的 `memcpy`、自赋值结构体）未逐处扫描；
  本轮只扫描了 `snprintf` 自拷贝（仓库内已 0 命中）。
- `field_ptr` 的登记泄漏、`foreach item` 等既有边界不变（卡 §7.9.7）。
- SH-103 的 `struct_lit` CI 症状未单独复跑：本轮 Linux 全量 `p80_retain` 已覆盖该夹具的
  ASan/UBSan 段，均为 ok。
