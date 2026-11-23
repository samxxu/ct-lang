---
phase-id: v0-PH-46
version-minor: 46
---

# Phase 46 — `Map` 元素完整性（用户 struct 按值入 `Map`，`ct build` 可编译）

> **状态：完成（2026-11-15；v0.46.0；S1–S5 全绿）**
> **归属**：本仓库维护规格与判据；实现与夹具由外部 DeepSeek harness 交付（[手册](../../design/phase46-52-handoff.md)）。
> **基线**：本卡最后一次提交（`git log -1 --format=%H -- docs/phases/v0-PH-46/card.md`）；v0-PH-45 已于 v0.45.0 收口。
> **规模**：≤120 行（编译器；裁决席按 F1 下调）。夹具与文档另计。
> **版本**：收口 bump `v0.46.0`（若采纳裁决 U-4 A）。

## 0 一句话目标

让 `Map<K, 用户 struct>` 在 `ct build`（多单元）下生成完整类型的条目结构并跑通，而不是只在单文件下通过。

## 1 本卡做 / 本卡不做

| 做 | 不做 |
| --- | --- |
| 修 `MapEntry_*` 的**单元归属**：元素类型是用户 struct 时，条目结构下沉到使用它的翻译单元 | 不改 `Map` API、`MapEntry` 字段与布局 |
| 同时覆盖第二实参判定（`MapEntry` 不是白名单类型，`inst_elem_foreign` 需认它） | 不改键类型白名单、键比较（归 v0-PH-47） |
| 单单元与多单元两档都验收；`--lib` 导出面不回归 | 不引入「元素必须完整类型」的新限制条款 |
| 生成物按 `/tmp` 快照 `cmp`，不引入新符号 | 不碰 `Vec` 生成物 |

## 2 前置依赖

无硬前置。与 v0-PH-48 共享「单元归属策略」：本卡的 D46-2 先冻结，v0-PH-48 的 S0 引用它（不合并两相）。

## 3 现状（实测）

| 形态 | 单文件 | `ct build` |
| --- | --- | --- |
| `Vec<JsonRef>` / `Map<char*,JsonRef*>` / `Map<char*,void*>` / `Map<char*,int>` | 通过 | 通过 |
| `Map<char*, JsonRef>` | 通过 | **失败** |

```text
.ctbuild/Vec.h:31:20: error: field has incomplete type 'struct JsonRef'
```

复现（基线提交，`/tmp`，`m.h` 无需初始化）：

```sh
mkdir -p /tmp/p46 && cd /tmp/p46
# lib.h.ct: pub struct JsonRef { int tag; }
# main.ct : struct Doc { Map<char *, JsonRef> slots; }
"$work/ct-ast" main.ct -o main.c ; echo "single=$?"        # 0
"$work/ct-ast" build main.ct -o out ; echo "build=$?"      # 1 + 上面的错误
```

## 4 修法方向（指到文件与函数）

| 点 | 位置 | 改法 |
| --- | --- | --- |
| 实例/条目归属判定 | `selfhost/ct-ast/backend/emit/Emitter.h.ct:1981-2016`（`inst_elem_foreign`） | 把 `MapEntry_<K,V>` 纳入「元素在 foreign 单元」的判定：`V` 为用户类型时条目结构随使用单元发射 |
| 具体实例发射 | `Emitter.h.ct:1609-1625` | 按 D46-2 只在该条目被使用的单元发一份完整定义；其他单元不发 |
| 声明通道 | `Emitter.h.ct:1597-1618` | 需要前置声明时只发 `struct MapEntry_*;`，不重复定义 |
| 模板声明 | `lib/std/Vec.h.ct:47-50` | 不改 |

**D46-2（冻结）**：唯一方案 = 条目结构下沉到使用单元。删除「共享头补 `#include`」备选（会形成 include 环，且把用户头拉进 `--lib` 面）。

**D46-5（冻结）**：`MapEntry_*` 是 C 结构体标签，不产生连接符号；任何「新增符号」的判据都作废。

## 5 任务切分

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| S0 | 只读核对上述四处锚点与实际分支；产出「条目归属现状」一页 | 无提交 |
| S1 | 红证夹具（单文件绿 / build 红）+ 原始输出 | `test: v0-PH-46 红`，父提交即红证 |
| S2 | 改 `inst_elem_foreign` + 发射归属 | ≤3 文件、≤120 行 |
| S3 | 四形态对照 + `foreach`/`remove`/`from` 回归 + `--lib` 导出 | 新增夹具与快照 |
| S4 | 文档：容器章节「元素完整性」一句；`language-spec.md` 等文档线落定 | 或记 `blocked-by` |
| S5 | 收口 | 见 §6 |

## 6 验收判据（可执行、可判真假）

| ID | 命令 / 比对 | 通过条件 | 失败条件 |
| --- | --- | --- | --- |
| E46-1 | `"$work/ct-ast" build /tmp/p46/main.ct -o /tmp/p46/out && cc -std=c99 /tmp/p46/out/*.c -o /tmp/p46/bin && /tmp/p46/bin > /tmp/p46/build.txt`；`"$work/ct-ast" /tmp/p46/main.ct -o /tmp/p46/single.c && cc … && …/single > /tmp/p46/single.txt`；`cmp /tmp/p46/single.txt /tmp/p46/build.txt` | rc 全 0 且 `cmp` rc=0 | 任一 rc≠0 或 `cmp` 有差异 |
| E46-2 | 收口前后各生成一份 `/tmp/p46/before-<file>.c` 与 `after`，`cmp` 四种对照形态 | 四对 `cmp` 全 rc=0 | 任一有 diff |
| E46-3 | `nm -g --defined-only` 比较基线与本相产物 | **新增符号数 = 0** | 出现任何新符号 |
| E46-4 | `grep -c 'struct MapEntry_' /tmp/p46/out/*.c`，按文件分别统计 | header 侧 0 份、使用单元 1 份 | 0 份或 ≥2 份 |
| E46-5 | `bash selfhost/check-all.sh` | rc=0，末行 `check-all: OK (11 hard gates green)` | 任一失败 |
| E46-6 | 红证链：`git log --oneline -2`，test 提交为实现父提交，正文含 `baseline: <sha>` + 原始输出 | 结构符合 T-7 | 红证与实现同提交 / 无 baseline |

## 7 范围外归属

| 项 | 归属 |
| --- | --- |
| 键类型、键比较、键所有权 | v0-PH-47 |
| 跨单元 Drop | v0-PH-48 |
| `Map` 的 `has` 入口 | v0-PH-50 |
| 多单元下仍失败的情形（若 S0 证明 `--lib` 与下沉互斥） | O1 降级为 O4 条件，写进收口报告，不扩张本卡 |

## 8 风险与回滚

| 风险 | 信号 | 回滚 |
| --- | --- | --- |
| 两个单元各发一份完整定义 | E46-4 计数 ≥2 | 回到 S2 前的提交；归属判定改为「首个使用单元」 |
| 既有 `Vec` 生成物漂移 | E46-2 有 diff | 回滚 S2；归属判定必须只对 `MapEntry` 生效 |
| `--lib` 导出头回归 | E46-3 新符号或导出失败 | 回滚 S2；改用前置声明通道（`1597-1618`） |
| golden 漂移 | `check-goldens` 红 | 只允许重生成受影响文件，逐字节核对；否则回滚 |

**回滚粒度**：S2 一个提交可整体回退，S3 夹具保留不受影响。

### 9 收口记录（2026-11-15）

| 项 | 结果 |
| --- | --- |
| E46-1 | 单文件 / build 输出 `cmp` rc=0；`put 1 get 1 tag 7 len 1` |
| E46-2 | 四种对照形态前后逐字节一致；目标形态仅 body 从 `Vec.h` 移到 `prog.c` |
| E46-3 | `nm -g --defined-only` 无 `MapEntry_*` 符号 |
| E46-4 | 产物头 0 份 body，使用单元 1 份；`--lib` ABI 面无 `MapEntry_` |
| E46-5 | check-all 11/11 |
| E46-6 | 红证 `p46_map.sh` 基线 4 failures → 0 |

tag/push：`v0.46.0` annotated tag 与分支自动 push。
