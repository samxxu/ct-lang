# STD-1 · std 面向应用层仍有 6 项能力缺口

| 项 | 值 |
| --- | --- |
| 模块 | std |
| 严重度 | Medium |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | `std/str/String.m.ct`；`std/vec/Vec.h.ct`；`std/map/Map.h.ct`；`std/utf8/Utf8Ops.m.ct`；`std/fs/Fs.m.ct`；`std/README.md`（均为 ct-pkg 包 `std` 0.1.0 的包内路径） |
| 状态 | 已决策（2026-11-07）：三项优先、Map 按需、Vec 泛化 / utf8 宽度 0.x 不做；实现归 ct-pkg |

路径口径：下表与正文里的 `std/...` 行号按迁移前（`v0.19.0`）树内记录；std 现为 ct-pkg 包 `std` 0.1.0，
包内布局同形但部分文件已改名（`Str.h.ct` → `String.m.ct`、`Utf8.h.ct` → `Utf8Ops.m.ct`、
`Fs.h.ct` → `Fs.m.ct`）。`test/std/run.sh` 已随迁出删除，对应断言由包内 `tests/run.sh` 承担。

> **名称时点**：std 于 2026-11-06 从 ct-lang 迁入 ct-pkg 时，`Str` 统一改名为 `String`
> （ct-pkg/std 迁移提交 `1eddd4b`；同批还有 `Utf8.h.ct` → `Utf8Ops.m.ct`、`Fs.h.ct` → `Fs.m.ct`）。
> `VecStr` / `VecStrOps` **没有**跟着改名。本文 2026-11-03 的段落保留当时名称作为历史记录；
> ct 仓其余历史文档（`docs/design/phase17.md`、`primitive-methods.md`、`phase20-review.md`、
> `docs/history/reports/…`）中的 `Str` / `Str.h.ct` / `Str.m.ct` 同属历史记录，保持原样，
> 改名时点同上；新增的处置段落一律使用现行名称。

## 现象

std 现有 7 个模块（`arena` / `fs` / `map` / `str` / `test` / `utf8` / `vec`，共 1072 行），足以支撑
编译器自身与门禁，但不足以直接实现 Markdown 类应用：

1. **无 `StrBuf`**：`std/str/Str.h.ct:20,25` 只有创建 / 销毁 / 长度类接口，没有追加、截断、预留容量；
2. **Vec 只有 `VecInt` / `VecStr`**：`std/vec/Vec.h.ct:24,30`，没有泛型或自定义元素类型；
3. **Map 固定容量且不 rehash**：`std/map/Map.h.ct:4-11,27,31,39,85`；
4. **utf8 只有 decode / encode / length**：`std/utf8/Utf8.h.ct:20,60,92`，没有显示宽度；
5. **fs 只有 `exists` / `read_file` / `write_file` / `list`**：`std/fs/Fs.h.ct:20,25,31,36,63,82`，
   无 `rename`、无原子写；
6. **无公开 `stat`**：`exists` 内部调用它（`Fs.h.ct:63`），外部拿不到 size / mtime / 文件类型。

## 证据

`std/README.md` 明确把 std 定位为「源码库 + 模块表 + 入口」，因此上述是**已记录的能力取舍**，
不是实现缺陷：

```text
$ ls std/*/*.h.ct | wc -l
7
$ ls std
arena  fs  map  str  test  utf8  vec
```

对照复核报告的应用场景（Markdown 解析 / 渲染），动态文本、任意元素容器、按内容增长映射、列宽、
原子替换、文件时间戳全部需要绕过 std 直写 C。

## 影响

Medium：std 的「可复用」价值被削弱。应用层每实现一个 Markdown 相关能力，都要重复实现同一套底层设施，
且这些实现不受 `test/std/run.sh` 保护。

## 处置

**待决策，本轮不实现。** 2026-11-02 的复核已把 stdlib 归为「新能力 / 治理决策」不立案；本次 re-open
的理由是：这些缺口已在具体应用（Markdown 渲染）中反复出现，且每项都有明确的最小接口，不再是泛泛的
「要有标准库」。是否实现、优先级、是否为此引入泛型机制，仍由维护者决定。

## 修复建议

按最小改动排序：

1. `Str` 增 `append` / `truncate` / `reserve`，不改类型形态；
2. `Map` 增可选 `grow`（容量翻倍 + 重新散列），保持现有 API 兼容；
3. `Vec` 增 `VecPtr`，或按元素大小参数化的通用 Vec（是否上泛型需先定语言能力）；
4. `Utf8` 增 `width`（East Asian Width 近似表，先覆盖 CJK 与 emoji）；
5. `Fs` 增 `rename`（同目录原子替换）与 `stat`（size / mtime / is_dir）。

## 验证

无（本轮仅立项）。实现时每项需独立 `test/std/run.sh` 断言，并至少覆盖 macOS / Linux 两个平台的
`fs` 行为差异。

## 处置（2026-11-03 复核）

**维持待决策，本轮不实现。** 缺口本身认可，但这是一组新能力，且其中 3 项会触及语言/库形态选择：

- `StrBuf` 与 `Map.grow` 是纯增量，风险最低，可先做；
- `Vec` 的通用化要先定「是否引入泛型」——这属于语言能力（Phase 21+），不能由 std 单方面决定；
- `Utf8.width` 与 `Fs.rename/stat` 依赖平台细节，需要先有跨平台断言基建。

建议按「`StrBuf` → `Map.grow` → `Fs.rename/stat` → `Utf8.width` → `Vec` 泛型」的顺序推进，
每项单独提交并配 `test/std/run.sh` 用例。

## 处置（2026-11-07 决策）

**取舍已定。实现归 ct-pkg 仓的 `std` 包；ct 仓只记录决策与归属，不产生 ct 侧待办、不建 ct 侧任务单。**

| 项 | 决定 | 边界与落点 |
| --- | --- | --- |
| `String` 增量能力 | **优先做** | ct-pkg 目前没有 `StringBuf` 类型，因此不按缓冲类型立项；在 `std/str` 的 `String` trait（宿主 `char *`）上增加 append / truncate / reserve 一类方法，具体方法名与签名由 ct-pkg 定。 |
| fs 原子写 + `rename` | **优先做** | `std/fs` 的 `FsOps` 增 `rename`（同目录原子替换）与原子写（临时文件 + rename）；平台差异与断言由 ct-pkg 的 `tests/run.sh` 承担。 |
| 公开 `stat` | **优先做** | `std/fs` 暴露 size / mtime / 文件类型，不再只在 `exists` 内部使用；字段形态与平台差异由 ct-pkg 定。 |
| `Map` 增长 | **按需做** | 保留现有固定容量 API；确有调用方需要时再加 `grow`（容量翻倍 + 重新散列），不预先实现。 |
| `Vec` 泛化 | **0.x 不做** | 泛型是语言能力，不能由 std 单方面决定；0.x 继续只保留 `VecInt` / `VecStr` 两个单态类型（`VecStr` 未随 `Str` → `String` 改名，现行名称仍是 `VecStr` / `VecStrOps`）。 |
| utf8 显示宽度 | **0.x 不做** | East Asian Width 是随平台与 Unicode 版本变化的近似表，维护成本高且容易给出“看起来对”的错误列宽；需要宽度时由应用自带表。 |

顺序：三项「优先做」可并行；`Map` 增长按调用方需求触发；两项「0.x 不做」在 1.0 前重新评估。
每项由 ct-pkg 单独提交、单独补 `tests/run.sh` 断言。
