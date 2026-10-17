# TEST-5 · L2 驱动的错误分支仍无负例

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | **Medium** |
| 锚点 | commit `ec97f99`（2026-10-17） |
| 位置 | [selfhost/src/driver.ct](../../selfhost/src/driver.ct)、[selfhost/src/core.ct](../../selfhost/src/core.ct) |
| 状态 | 🟡 部分修复（2026-10-18；6 条已补，见下） |

## 现象

Phase 6 复审已指出「L2 驱动错误分支基本未测」，本轮复核**仍未补**。`test/modules/*/expected.err` 中只有 `map_noarg`（`--emit-map needs an argument`）一个参数类负例。

## 证据

以下站点在 `test/modules/*/expected.err` 中均无对应文案：

| 位置 | 诊断 |
| --- | --- |
| `driver.ct:390` | `-o needs an argument` |
| `driver.ct:395` | `-I needs an argument` |
| `driver.ct:397` | `too many -I roots` |
| `driver.ct:405` | `--ns-root needs an argument` |
| `driver.ct:408` | `namespace root too long` |
| `driver.ct:420` | `map path too long` |
| `driver.ct:435` | `unknown diagnostics format` |
| `driver.ct:331/445` | `too many units` / `too many inputs` |
| `core.ct:2719/2723/2727` | `cannot open` / `cannot read` / `short read` |
| `core.ct:2877` | `cannot create a temporary file` |
| `core.ct:4979/4984` | `cannot write`（map 文件） |

L0 侧同类分支已有 `cli/cannot-open`、`cli/cannot-read`、`cli/tmpfile-cannot-create` 等覆盖，但那些断言跑的是 `ctc.c`，**不会触达 L2**。

## 影响

L2 是当前唯一仍在开发的编译器；其驱动层回归网比 L0 薄。此前在 L0 上真实发生过的 I/O 失败缺陷（`cannot read` / `tmpfile`）说明这类分支并非纯理论。

## 修复建议

在 `test/modules/` 下补 designed 负例（`build.args` / `compile.args` + `expected.err`），优先顺序：

1. `-I` / `--ns-root` / `-o` 缺参（纯 CLI，成本最低）；
2. `cannot open`（不存在的输入）、`short read`（目录作输入）；
3. `--diagnostics=bogus`（未知格式）；
4. `--emit-map` 指向不可写路径（`cannot write`）。

`expected.err` 必须由真实 L2 二进制输出生成，禁止手写（见 `ctc-coverage-audit` skill §7）。

## 验证

新增用例后 `bash selfhost/check-archive.sh` 的 `designed cases` 计数增加且 0 regression；`bash selfhost/check-all.sh` 仍 `OK`。

## 处理（2026-10-18）

新增 6 条 designed 负例（`expected.err` 均由真实 L2 输出生成）：`cli_o_needs_arg`（`-o`）、`cli_i_needs_arg`（`-I`）、`cli_diag_bogus`（`--diagnostics=bogus`）、`cli_std_bogus`（`--std=c11`）、`cli_cannot_open`（不存在的输入）、`cli_short_read`（目录作输入）。已提升进 `check-archive.sh` 的 `baseline_designed`，计数 32 → 39。

未覆盖（受 runner 限制，留作后续）：build 模式的缺参分支（runner 总追加 `-o <dir>`，会被当作选项值）、`too many units/inputs`、`--ns-root` 缺参、map 文件不可写（沙箱下不稳定）。
