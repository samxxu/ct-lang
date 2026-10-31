# 检查表：`.m.ct` 零成本静态映射（第三十八批）

按 `spec.md` 逐条核对；每项以**运行结果**为准，不以读码代替。

## 文件类型与构建

- [x] `foo.m.ct` 被 `import` 后单元基名为 `foo`、`is_map = 1`、`is_hdr = 0`。
- [x] `ct build` 对 `.m.ct` 不产 `foo.c` / `foo.h`，不写缓存 artifact，末尾 `cc` 行不含 `foo.c`。
- [x] 命令行直接 `ct build foo.m.ct` 与 `ct foo.m.ct -o x.c` 均报
      `a .m.ct unit produces no output; import it from a .ct unit`。
- [x] 同一 root 下 `foo.h.ct` 与 `foo.m.ct` 并存 → 歧义消息含两个路径。
- [x] 修改 `foo.m.ct` 后消费者重建（缓存 key 折叠 `.m` 依赖）；不改时消费者命中缓存。
- [x] `.m.ct` 目录与 `namespace` 不符时报既有的 `namespace '…' does not match the directory '…'`。

## 内容白名单

- [x] `#include` / `#define` / `import` / `pub trait` / `map` / `_Static_assert` 能编过。
- [x] 函数定义、函数原型、全局（含 `extern`）、`struct`/`union`/`enum`/`typedef`、`impl`、
      `for instance`、`#pragma` 逐一报 spec §7 的消息。
- [x] 非 `pub` 的 trait、带默认体的 trait 报对应消息。
- [x] `.m.ct` 只能 `import` 其它 `.m.ct`（import `.h.ct` 报错）。

## 静态 trait

- [x] 生成物里没有 `<T>_iface`、`<T>_vtbl`、`<T>_vtable`、任何 `static … (void *self` 包装函数。
- [x] `impl <静态 trait>`、`use <静态 trait>`、把静态 trait 写成类型、`T::host` 装箱，各自报对应消息。
- [x] `Trait::host(...)` 这类限定调用不受影响（只有静态 trait 才被拦截）。

## 命名空间静态调用

- [x] `libc::Env.get("HOME")` → `getenv("HOME")`。
- [x] trait 不在宿主命名空间时报
      `a static trait for a namespace host must be declared in that namespace`。
- [x] 找不到 map 时报 `no map binds trait '…' to namespace '…'`，位置是调用行。

## 类型宿主

- [x] `map trait CStr for type char *` 能编过；`for type char[]` 报错。
- [x] `char a[] = "42"; a.toInt()` 命中（数组 decay），生成 `atoi(a)`。
- [x] `b.fill('z', 3)` → `memset(b, 'z', 3)`。
- [x] `a.scanInto(&scanned)` → `sscanf(a, "%d", &scanned)`（recipe 里 `out` 原位替换）。
- [x] 接收者类型不匹配（如 `int *`）不命中，报 `no method '<m>' for type '<type>'`。
- [x] 同一类型同一方法被两个 `.m.ct` 提供时，报歧义并列出两个 `.m.ct`。
- [x] 普通 struct / 接口方法优先于类型宿主（同一名字两者都存在时走普通方法）。

## recipe 替换

- [x] 值参数 → `(<actual>)`；`&p` → `&(<TP>){<actual>}`；`sizeof p` → `sizeof(<TP>)`；
      `p.field` / `p->field` / `p[i]` 的括号正确。
- [x] 未使用参数在调用表达式前生成 `(void)(<actual>),`，实参副作用保留。
- [x] `p++` / `p = …` 报 `map recipe modifies binding parameter '<p>'`。
- [x] 多次求值 + 函数调用/赋值实参报
      `map recipe uses '<p>' more than once; bind the argument to a local first`；
      简单变量/字面量/稳定成员链的重复使用不报错，且语义等价。
- [x] 非单次顶层调用报 `a map recipe must be a single call`。
- [x] 动态 map 的 `check_call` 严格度不变（既有负例仍报原消息）。

## prologue

- [x] 消费者 `.c` 顶部出现被 import 的 `.m.ct` 的 `#include` / `#define`，且按整行去重。
- [x] 消费者不写这些 `#include` 也能编译通过。
- [x] 消费者 `.h` **不**含 prologue。
- [x] `ct <file>.m.ct -o <file>.c` 报 `a .m.ct unit produces no output; import it from a .ct unit`（不产出文件）。

## `--emit-map`

- [x] 静态映射条目带 `"static": true`、`"host": "namespace"|"type"`、`"type"`（仅 type host）。
- [x] binding 带 `"inline": true`、`"wrapper": false`、`"symbol": <callee>`。
- [x] 动态 mapping 的 JSON 字段与取值逐字不变。

## 质量与回归

- [x] 正例 1/2/3 的生成物 `cc -Wall -Wextra -std=c99` 零告警，运行输出与 `expected.out` 一致。
- [x] `-O2` 反汇编无 `blr`（aarch64）/ `call *…`（x86-64）指向映射调用。
- [x] 生成物没有 `_iface` / `_vtable` / `vt->` / `(void *)0`（对照 `test/modules/map_unit/main.c`）。
- [x] 既有动态 `map` 用例（`26_ns_host`、`modules/ns_host`、`modules/map_ns`、`ast/14/15/22`）
      产物逐字节不变。
- [x] `test/cases/**` 与 `test/modules/**` 既有 golden 只有版本 token 变化（v0.15.0）
- [x] `bash selfhost/check-ast.sh`、`bash selfhost/check-warnings.sh`、
      `bash selfhost/check-all.sh` 全绿。
- [x] `CTC_VERSION` 五处同步 bump 到 v0.15.0（用户授权），L0 / L1 / L2 只动这一行

## 文档

- [x] `docs/language-spec.md` §4.10 中英对称新增静态映射小节（文件类型、静态 trait、
      `host::Trait.method`、`for type`、替换规则、prologue、JSON、诊断）。
- [x] `docs/tutorial.md` 有可运行的最小例子。
- [x] `bindings/README.md` 写明 `.m.ct` 与 `.h.ct` 的分层与 C shim 的适用形状。
- [x] `docs/glossary.md` 补术语；`docs/roadmap.md` 批次列表（中英）指向本目录。
