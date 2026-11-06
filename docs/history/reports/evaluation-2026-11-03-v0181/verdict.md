# `ct-lang-evaluation-v0.18.1` 复核意见

> 复核对象：[evaluation-2026-11-03-v0181.md](evaluation-2026-11-03-v0181.md)（原文快照，未改动）
> 复核锚点：原文 `v0.18.1`（`528d7c5`）+ 附录 C `v0.19.1`（`4176c636`）
> 复核环境：本机 HEAD `c27da3d`、已安装 `ct v0.19.1`、Apple clang
> 复核方式：静态核对 + 探针（命名空间静态初始化、容量、C 头常量、trait 签名、`ct check`）

## 总体判断

**认可这份评估的定位与风险排序，不等于认可它的全部细节。** 它的强项是取舍判断（ct 适合做
「可读 C 的代码生成器 + 核心逻辑层」，不适合承担 UI 与生态），以及几个关键数字——本轮逐项复核：

- `L1+L2` 10864 行、`ct-ast` 17100 行、`std` 7 模块 1072 行、`issues` 121 条：**全部精确吻合**
  原文锚点 `528d7c5`；
- `SH-14` 跨单元 vtable 为 `static`、`TEST-7` 无逐字节 oracle、`tutorial` 标 `v0.16.0`：**均复现**；
- 单文件容量常量 256 / 128 / 64 / 16 / 4096 与「报错不点名上限」：**复现**；
- 附录 C 新增的「命名空间静态初始化器不重写被引用全局」：**复现，且会让生成的 C 编译失败**。

因此把原文完整入库，并把**新发现**与**已有台账**分开记录：新问题立 issue，已跟踪的只引用、不重复立案。

## 逐项核对

| 原文位置 | 判断 | 复核意见 |
| --- | --- | --- |
| §0 / §5 结论与评分 6.4（语言 7.8 / 平台 4.2） | **认可结论，评分仅作参考** | 风险排序（生态 > 容量 > 类型 => 跨单元装箱）与实测一致；加权分数是主观标度，不宜当作事实引用 |
| §3.1 定位克制、零运行时、可读 C | **认可** | 与 README / `docs/vision.md` 一致，无可证伪点 |
| §3.2 trait / Drop / borrow / map | **认可** | 与 `docs/language-spec.md` 第 4 章一致 |
| §3.3 工程质量、11 道硬门禁、121 条台账 | **认可（限 `v0.18.1`）** | 121 条精确吻合；**当前 `v0.19.1` 已是 12 道门禁**，原文的「11 道」是版本快照，不是现状 |
| §3.4 诊断格式 `文件:行:列:` | **认可，但需限定** | `ct check` 的列号在 `v0.19.1` 才补齐（SH-50，已修）；原文写作时 check 侧只有 `file:line:` |
| §3.7 macOS 探针（pthread / AudioToolbox / framework） | **认可（未逐条复跑）** | 与原文附录 A.4 / A.5 自洽；本轮只复现了 C 头常量的边界（见 §4.4） |
| §4.1 无类型检查 / trait 签名不比对（P0） | **部分过时** | 编译路径仍是 warning-only（`ct compile` 返回 0），但 `v0.19.0` 起 `ct check` 对 arity / 实参 / 歧义 / impl 漂移报 `error:` 并 exit 1；附录 C 写「§4.1 不变」**不准确** |
| §4.2 单文件容量硬上限（P0） | **认可，但需分层** | 常量与报错复现：`many.ct:258:1: error: too many functions`（`MAX_FUNCS 256`）；「动态扩容」属能力决策，`SH-1` / `SH-47` 已记录同一主题 |
| §4.3 生态几乎为零 | **认可** | `bindings/` 仅 2 个；`std` 缺口见 STD-1；官方包不在本仓库，按外部仓库计 |
| §4.4 C 头常量不可见（P1） | **部分认可，原文过宽** | 实测：头文件 `enum { kFoo = 7 }` 在表达式里报 `use of an undeclared variable`；但 `#define K_BAR 9` **能透传**（大写宏在若干位置被按宏放行）。原文「enum 常量 / 宏对象都不可见」应改为「enum 常量与非宏名字不可见；大写 `#define` 可透传」 |
| §4.5 SH-14 跨单元装箱（P0） | **认可** | 台账仍为「待修（Batch 2 / 2a.1）」，发射端确为 `static`（`Emitter.h.ct:1397/1455` 等） |
| §4.6 三套管线 / TEST-7 | **认可** | `TEST-7` 仍开；`check-ast` 以行为探针为主，无逐字节 golden |
| §4.7 文档漂移 / 版本治理（P2） | **认可，数字订正** | `tutorial` / `memory-guide` 均标 `v0.16.0`（新立 DOC-63）；原文「约 15 条待修」偏低，锚点 `528d7c5` 上 `状态 | 待修` 为 **20** 条 |
| §4.8 语言面缺口（P2） | **认可** | 无泛型 / 重载 / 异常；`SH-46` 的「按 use 顺序取首个」仍为既定决策 |
| §4.9 零运行时的另一面 | **认可（观点）** | 属设计取舍，不需要行动项 |
| 附录 C.2 `ct check` 列号 / 文档修正 | **认可** | SH-50、DOC-60、DOC-62 在 `v0.19.1` 均已修，与本次复核一致 |
| 附录 C.4-1 静态初始化不重写命名空间前缀 | **认可，且升级为 High** | 探针复现：生成的 `static struct ns_Bar ns_k_bar = { 9, &k_foo };` 中 `&k_foo` 未改名为 `&ns_k_foo`，`cc` 直接报错（见 SH-52） |
| 附录 C.4-2 `ct check` 拒绝 import 但带列号 | **认可** | 与本轮实测一致 |
| 附录 C.4-3 `--emit-c --outdir` 要求目录存在 | **认可（未逐条复跑）** | 属 CLI 输入校验，建议并入后续体验项，不单独立案 |
| 「三平台 CI」 | **措辞订正** | 实为两个操作系统、三种编译器配置（`ubuntu-gcc` / `macos-clang` / `ubuntu-clang-smoke`） |

## 本轮新增 issue

| ID | 严重度 | 内容 |
| --- | --- | --- |
| [SH-52](../../../../issues/selfhost/sh52-namespace-static-initializer.md) | **High** | 命名空间静态初始化器不重写被引用全局的名字，生成 C 无法编译 |
| [DOC-63](../../../../issues/docs/doc63-tutorial-version-stale.md) | Low | `tutorial` / `memory-guide` 的「适用版本」仍写 `v0.16.0` |
| [DOC-64](../../../../issues/docs/doc64-header-enum-constants.md) | Medium | 未文档化「C 头 enum 常量在表达式里不可见」，应给出 shim 写法 |
| [SH-53](../../../../issues/selfhost/sh53-capacity-message-limit-and-unit.md) | Low | 容量触顶诊断不点名上限值与单元（`MAX_FUNCS` / `MAX_STRUCTS` / `MAX_PARAMS` / `MAX_VARS`） |

## 已跟踪、不重复立案

- `SH-14`（跨单元 vtable `static`，High，待修）；
- `TEST-7`（ct-ast 无逐字节 golden，High，待修）；
- `SH-46`（多 trait 同名方法按 use 顺序取首个，已决策）；
- `SH-47`（字段容量报错文案，已修，可作 SH-53 的文案范式）；
- `STD-1`（std 应用层缺口，待决策）。

## 未验证范围

- 原文的 6.44s 自举时间未复跑（本轮按 `~/.local/bin/ct v0.19.1` 与源码静态核对）；
- `ct-radio` 的行为 harness 数据（adult / sleep / kids / glyph / seek）属外部项目，未纳入本仓库证据；
- `ct-pkg/hal`、`hal-posix`、`clib` 不在本仓库，无法在此核对；
- Volume 级 `/tmp` 探针仅覆盖 macOS + Apple clang，未覆盖 Linux / GCC。
