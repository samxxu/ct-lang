# ct-ast 内部架构（v1.1；L0/L1/L2 已退役）

> 中文

本文面向要修改 `selfhost/ct-ast/**` 的人/代理。当前唯一安装入口与开发主线是 **ct-ast**；
L0（`ctc.c`）、L1（`ctc.ct`）、L2（`core.ct`/`driver.ct`）已在 **SH-119** 删除（v1.0.0 的 tag
仍可取回历史源码），不再参与构建、安装或门禁。

## 1. 入口与构建

```console
$ cc -O2 -std=c99 -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o ct
$ ./ct -v
```

- `bootstrap/ct-ast/` 是冻结 seed（D-022），由 `selfhost/gen-seed.sh` 在发版时重生成；
- `install.sh` 只编译 seed；`ctc` 是 `ct` 的兼容别名；
- 改动 ct-ast 源码后，用 seed 构建的 `ct` 重建（`selfhost/seed-ct.sh` / `ct build`）。

## 2. 源码分组

| 目录 | 职责 |
| --- | --- |
| `frontend/lex` | 词法器（`TokView`，零拷贝 token） |
| `frontend/module` | 单元、import、namespace、构建图 |
| `frontend/parse` | 表达式 / 语句 / 声明解析与 AST 构造 |
| `frontend/sym` | 符号表、类型表、trait/impl、ADT 变体、容量常量 |
| `frontend/type` | `ct check --types` 语义检查（B/B+ 规则） |
| `runtime/arena` | 节点 arena、`NodeKind`、临时/清理辅助 |
| `backend/mem` | Drop/释放胶水与内存辅助 |
| `backend/emit` | C 发射器（76 个 `em_*` 切片；`match` 按 kind 穷尽） |
| `tool/pkg` | `ct get/install/verify`、索引、lock |
| `tool/diag` | 诊断文本 / JSON / 诊断码 |
| `tool/cache` | 增量缓存（`.ctcache` 键） |
| `tool/driver` | CLI、构建模式、`--emit-c`/`--emit-model` |

每个单元一个主类型；命名与拆分边界见 [AGENTS.md §3](../AGENTS.md) 与 `check-ast` 的 unit-name lint。
ADT/`match`（§4.73）在 `frontend/sym`（变体表）+ `frontend/parse`（语句）+
`backend/emit`（穷尽 `match`）中实现；对应 spec §4.73。

## 3. 编译路径

- **compile**：单 C 翻译单元；parse → typecheck → emit C；
- **build**：多单元；module 图 → 每单元 emit `.c/.h` → `cc`；
- **check**：parse → typecheck，不写产物；`--types` 为受限语义检查；
- **seed 自举**：`bootstrap/ct-ast` → `ct` → 重建自身（gate 13 两轮逐字节）。

## 4. 门禁

`bash selfhost/check-all.sh`：gate 1（seed `ct` 冒烟）、7 包管理、8 `check-ast`、
9 warning-free、10 语义入口、11 docs、12 静态 goldens + archive manifest、13 冻结 seed。
gate 2–5 随 L0/L1/L2 退役（SH-119 S2），gate 6 随编辑器插件迁出退役（现由
[ct-vscode](https://github.com/samxxu/ct-vscode) 的 `npm test` 负责）；历史证据见
[history](history/README.md) 与 tag `v1.0.0`。
