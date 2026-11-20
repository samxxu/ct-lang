# Phase 80 — `String` / `Str`（S5）

> **状态：规划中（未开卡；J-6 门槛）**（2026-11-20 立项；`v0.80.0` 拟）。
> **前置**：P-7.3 最小垂直切片 + P-7.4 全量；PH-79 切片表示收口。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase80.md`。
> **依据**：[提案 v2 §3/附录 C](../proposals/pointer-free-v2.md)、[D-011](../decisions/D-011.md)、
> [phase 安排](../planning/pointer-free-phase-plan.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-80（legacy 文件 `phase80.md`） |
| 目标 | UTF-8 `String` owning / `Str` 借用；UTF-16 `U16String`/`U16Str`；L1 字面量；不可变；std::str 逃生层 |
| 范围 | 内建类型、16 字节句柄 + refcount 头、字面量、转换、码点/字节/UTF-16 下标、核心方法集、std 迁移 |
| 非目标 | 正则/locale/normalize（走 shim）；借用检查；`box/new`；切片本体（PH-79） |
| 交付物 | 编译器/内建层、`test/ast/p80_*`、std/跨仓迁移、文档 |
| 任务清单 | §2（S5a/S5b） |
| 退出判据 | E80-1…E80-8（§3） |
| version-minor | 80（PH-80，`d=0`） |
| 已知风险 | R80-1…R80-6（§4） |

## 1 需求与边界

```ct
String s = "abc";                  /* UTF-8 owning；L1 immortal 字面量 */
Str v = s.as_str();                /* UTF-8 借用视图 */
u8 b = v.byte_at(0);
u32 cp = v.codepoint_at(0);
Str ch = v[0];                     /* 单码点视图，只读 */

U16String js = U16String.from_utf8("abc");
u16 c = js.char_code_at(0);
U16Str jc = js[0];                 /* UTF-16 code unit 视图，只读 */
```

- `String`/`Str` UTF-8；`U16String`/`U16Str` UTF-16；跨编码只走显式工厂。
- `String` 字面量 L1 immortal（`refs=-1`，只读区，Drop 不释放）；`Str` 字面量是借用视图。
- `String` 不可变：`s[i] = ...` 永远不合法；内容变化返回新值。
- UTF-8 用户接口用码点下标；`byte_*` 提供字节级 O(1) API。
- `String[i]` 返回单码点 `Str` 视图；`U16String[i]` 返回单 code unit `U16Str` 视图；都只读。
- `.data` 只读且不保证 NUL；`cstr()` 是 C 边界唯一出口。
- U16 首轮只做 JS 核心子集（snake_case）；`match`/locale/normalize 走包 + shim。
- `String`/`Str` 内建化，迁出 std；旧 owning `Str` 在兼容窗口内仅以 `std::str::Str` 限定名存在。

### 1.1 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S5a 内建层 | `String/Str` + `U16String/U16Str` 类型、L1 字面量、核心方法、旧 `Str` 限定名并存 | P-7.3；PH-79 收口 |
| S5b 删旧/迁移 | 删旧 `Str`、std 消费者迁移、索引/包版本、README/spec/roadmap 三处同步 | P-7.4；S5a 收口 |

## 2 任务

| 任务 | 交付 | 验收 |
| --- | --- | --- |
| S5a-1 类型/布局 | 16 字节句柄 + 8 字节头；immortal 空串/字面量 | `p80_layout` |
| S5a-2 字面量/转换 | L1 字面量；`to_string`/`as_str`；UTF-16 工厂 | `p80_literal` |
| S5a-3 方法/下标 | UTF-8 码点/字节 API；U16 核心 JS 方法；只读 `s[i]` | `p80_methods` |
| S5a-4 C 边界 | `.data` 只读、`cstr()`、printf 负例 | `p80_cstr` |
| S5b-1 迁移 | 删旧 `Str`、std 消费者、包版本/索引 | `p80_migrate` |
| S5b-2 文档 | README/spec/roadmap 三处同步 | `p80_docs` |

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E80-1 | `String`/`Str` 16 字节句柄；refcount 头对齐；`_Static_assert` 进 golden |
| E80-2 | `String s = "x"` L1 immortal；`Str v = "x"` 借用；`U16String` 仅工厂 |
| E80-3 | `String` 不可变；`s[i]` 只读单码点；`U16String[i]` 只读单 code unit；写操作硬错 |
| E80-4 | UTF-8 码点下标 + `byte_*`；`String.slice` 新 `String`，`Str.slice` 视图 |
| E80-5 | `.data` 只读不保证 NUL；`cstr()` 补 NUL；printf 子视图负例 |
| E80-6 | U16 核心 JS 方法 snake_case；`match/locale/normalize` 不在内建 |
| E80-7 | S5a 旧 `Str` 限定名并存；S5b 删旧 + std 消费者迁移 dry-run |
| E80-8 | README/spec/roadmap 三处同步；`check-all`/ASan 通过 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R80-1 | 旧 `Str`/新 `Str` 名字冲突 | 裸名新借用；旧 owning 仅 `std::str::Str`；窗口结束删除 |
| R80-2 | refcount 非原子 | 文档写死非线程安全；作者同步；lint 直接全局 |
| R80-3 | `.data` 被误当 NUL | `.data` 只读不保证；`cstr()` 唯一出口 |
| R80-4 | UTF-8 码点操作 O(n) | 文档写清；`byte_*` O(1) |
| R80-5 | S5b 外部迁移阻塞 | S5a/S5b 分期；外部迁移 dry-run 为 S5b blocking |
| R80-6 | 内建化改 std 身份 | 包版本/索引/消费者清单；不删旧 store |

回滚：S5a 可回退到旧 `Str`；S5b 与外部迁移绑定，不能整体单回滚。
