# Phase 50 — 容器取用契约（`has` / `at`，越界与缺键可判）

> **状态：规划中**（定稿候选；本卡只写规格，实现由外部 harness 执行）
> **归属**：本仓库维护规格与判据；实现由外部 harness 交付（[手册](phase46-52-handoff.md)）。
> **基线**：本卡最后一次提交；起点为 PH-47 收口提交。
> **规模**：220–380 行。
> **版本**：`v0.50.0`（若采纳 U-4 A）。

## 0 一句话目标

让「取到了 0」与「没取到」可区分，且不引入所有权转移：`Vec::has(i)` + `Vec::at(i)->T*`、`Map::has(k)`（`get` 已返回 `V*`）。

## 1 本卡做 / 本卡不做

| 做 | 不做 |
| --- | --- |
| `Vec<T>::has(int) -> int`、`Vec<T>::at(int) -> T *`（借用指针，不复制） | **不做** `try_get(..., V *out)`：实测对 `Str`/`use Drop` 元素双释放 |
| `Map<K,V>::has(K) -> int`；`Map::get` 保持返回 `V *` | 不改既有 `get` 的签名、零值/`0` 语义 |
| `int`/`char*`/`Str` 三份 `Map` 特化都补 `has` | 不引入哈希、不改线性扫描 |
| 契约写清：容器只认 retain/release，元素是借用句柄 | 不做自动释放元素 |
| 32 例固定表锁 `has` 与 `at`/`get` 的一致性 | 不做新语法（无 `v[i]?`） |

## 2 前置依赖

PH-47 收口（`Str` 键比较）。`Str` 键的 `has` 用例依赖它；`Vec` 与 `int`/`char*` 键不依赖。

## 3 现状（实测）

```sh
# c3.ct: Map<char*,int> m; int *p = m.get("none"); Vec<int> v; v.h=0; v.push(0); v.get(5)
"$work/ct-ast" c3.ct -o c3.c && cc -std=c99 c3.c -o c3 && ./c3
# missing=0x0 oob=0   rc=0
```

- `Map::get` 缺键返回 `0`；`Vec::get` 越界返回零值（`memset` 后返回）。
- **出参形态双释放实测**（裁决席）：`*out = v->get(0)` 后 `out.release()` + `v.release()` →
  ASAN `double-free in Str_release`，rc=134。→ 本卡不提供出参 API。

## 4 修法方向

| 点 | 位置 | 改法 |
| --- | --- | --- |
| `Vec` 入口 | `lib/std/Vec.h.ct`（`get` 附近） | `has(i)`：`h != 0 && 0 <= i && i < h->len`；`at(i)`：命中返回 `&((T*)h->data)[i]`，否则 `0` |
| `Map` 入口 | `Vec.h.ct:219-296`（`char*` 特化）、`int` 特化、PH-47 的 `Str` 特化 | 三份都加 `has(k)`；返回比较结果，不复制 |
| 契约 | 文档章节 | 「容器只认 retain/release；元素是借用句柄；`release` 只释放容器自己的引用」 |
| 既有 `get` | 三份特化 | **零改动**；`Vec::get` 的零值语义保持 |

**D50-1（冻结）**：只加并行入口，不改 `get`。
**D50-2（冻结）**：`at` 返回借用指针，**不复制**、不交出所有权；调用方不得 `release`。
**D50-3（冻结）**：`has` 与 `at` 分开；`at` 未命中返回 `0`，不用零值哨兵。

## 5 任务切分

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| S0 | 核对三份 `Map` 特化与 `Vec` 的 get/release；产出 32 例表（固定键、固定下标） | 无提交 |
| S1 | 红证：缺键/越界与零值不可分（两种容器） | `test: PH-50 红` |
| S2 | `Vec::has` + `Vec::at` | ≤150 行 |
| S3 | `Map` 三份 `has`（`Str` 依赖 47） | ≤150 行 |
| S4 | 32 例表 + 契约文档 | 夹具与文档 |
| S5 | 收口 | §6 |

## 6 验收判据

| ID | 命令 / 比对 | 通过条件 | 失败条件 |
| --- | --- | --- | --- |
| E50-1 | `p50_vec_has`：越界 `has==0 && at==0`；真实元素（含值 0）`has==1 && *at==0` | 四项全真 | 任一项假 |
| E50-2 | `p50_map_has`：缺键 `has==0 && get==0`；命中 `has==1 && *get==v` | 四项全真 | 任一项假 |
| E50-3 | 32 行固定表逐行打印 `id,has,at_hit,val`，与期望文件 `cmp` | `cmp` rc=0 | 任一 diff |
| E50-4 | 既有 `get` 夹具快照 `/tmp` `cmp` + `check-ast.sh` 末行 `0 failed` | 全 rc=0 | 任一 diff |
| E50-5 | `p50_str_has`：含 `\0` 键与 PH-47 同组用例 `cmp` | `cmp` rc=0 | 任一 diff |
| E50-6 | `p50_sanitize`：`at` 返回的指针不 release、容器 release 后 ASAN 无 double-free | rc=0 | 双释放/UAF |
| E50-7 | `bash selfhost/check-all.sh` | 11 green | 任一失败 |

## 7 范围外归属

| 项 | 归属 |
| --- | --- |
| 越界插入 / 缺键建槽 | `set`/`put`（PH-29 已冻结） |
| 自动释放元素 | 不做 |
| `Str` 键比较 | PH-47 |
| 出参 `try_get` | 废弃（本卡明确不做） |

## 8 风险与回滚

| 风险 | 信号 | 回滚 |
| --- | --- | --- |
| 有人把 `get` 改成 `has` 语义 | E50-4 diff | 回滚 S2/S3；`get` 零 diff 是收口条件 |
| `at` 被当成所有权转移 | E50-6 双释放 | 回滚 S2，文档加粗「借用」 |
| 漏改某份 `Map` 特化 | E50-3 表缺项 | 回滚 S3，补第三份 |
| `release` 契约被误读为递归释放 | 包方按 `delete` 容器排期 | 文档写死并在交付报告重复 |
| golden 漂移 | `check-goldens` 红 | 逐字节核对后重生成；否则回滚 |
