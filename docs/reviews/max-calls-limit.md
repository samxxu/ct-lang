# `MAX_CALLS` 1024 的来源与可修性（只读核对，2026-11-15）

> 回答负责人提问：「1024 个调用点是从哪里来的？限制可不可以修复掉」。
> 基线 `v0.53.1` 工作树（`5df13013` 之后）。**本文件只给结论与证据，不改实现、不改门禁。**

## 结论

1. **常数**：`#define MAX_CALLS 1024` 在 [Expr.h.ct:55](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L55)；
   真正的存储是 `static struct Call g_calls[1024];`，在 [Parser.h.ct:3759](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L3759)。
   两处数字必须一致，**没有任何编译期断言把它们绑在一起**。
2. **记的是什么**：**每条「指向已解析自由函数的调用表达式」一条**，在函数体内才记。
   - 同名函数调 100 次 = 100 条（**不是**按被调符号去重）；
   - 前置声明 / 原型**不占槽**（声明不是表达式）；
   - 方法调用（`o.m()`）、静态方法调用（`T.make()`）、函数指针调用（`fp(x)`）**都不占槽**
     （分别走 `N_MCALL` / `aux` 分支或 `find_func < 0`）；
   - libc / 未声明函数不占槽（`printf(...)` 默认不在符号表里）。
3. **为什么是固定表**：**找不到「解析阶段刻意不做动态分配」的代码或文档证据**。
   相反，同一对象在 [Parser.h.ct:3792](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L3792) 用
   `g_maps = calloc(64, sizeof(*g_maps))`（SH-42）**堆分配**。固定表的真实成因是**单元边界**：
   生成的头文件不带 `#include`，数组必须由属主单元（`Parser`）定义、其它单元持指针
   （[Parser.h.ct:140-147](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L140-L147) 的注释），
   容量只能是编译期常量，和 `MAX_FUNCS 512`（Phase 54 S0 前为 256）/ `MAX_VARS 4096` / `MAX_TYPES 256` 是同一族做法。
4. **可修性**：**可以修，属于「小改动、低风险」**——约 40–80 行（4 个文件 + 1 处签名），
   不影响 L0/L1/L2 自举链，性能影响可忽略。不需要另立相，可作为 P1 单独立项。
5. **不改代码的绕法**有三个可用、一个无效：分层出库（有效）、函数指针（有效但难看）、
   控制单次构建的闭包规模（有效）、「把热点函数拆到独立单元」（**实测无效**）。
6. **外部包余量**：实测最紧的是 rill-dsl（约 410 / 1024，余量 614）。其余都远未接近。

---

## 证据

### E1 上限是「整次构建累计」

`ncalls` 只在两处归零：`Module` 的整次 `build` 入口
（[Module.h.ct:1503](../../selfhost/ct-ast/frontend/module/Module.h.ct#L1503)）与单文件编译
（[Driver.h.ct:438](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L438)）。各单元只记录
`call_start` / `call_end` 区间（`Module.h.ct:740`、`:759`），**不重置计数**。

实测（`ct-ast build`，v0.53.1）：

```sh
# 单文件：n 条 f(i)
$ ct-ast build n1024.ct -o out1024     # rc=0（链接阶段才因 _f 未定义失败）
$ ct-ast build n1025.ct -o out1025
n1025.ct:1028:11: error: too many calls
$ echo rc=$?    # 1

# 两个单元：lib/lib.h.ct 内 500 条 g(i) + 入口 600 条 f(i)
$ ct-ast build -I . main.ct -o out
main.ct:529:11: error: too many calls      # 500 + 524 时耗尽
$ echo rc=$?    # 1
# 把 lib 改成 400 条 → rc=0（400 + 600 = 1000）
```

### E2 只记「已解析的自由函数调用表达式」

[Expr.h.ct:5732](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L5732) 是唯一的记录点：
在 `N_CALL` 后缀解析里，只有 `find_func(...) >= 0` 且 `cur_func` 非空时才 `record_call`。
上限检查在 [Expr.h.ct:6227](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L6227)。

证据（同一份 1100 次调用，改走函数指针即可通过）：

```sh
$ ct-ast build fp1100.ct -o ofp        # int (*fp)(int) = f; 之后 fp(0..1099)
# rc=0（仅链接阶段因 _f 未定义失败），没有 too many calls
```

### E3 为什么是固定表

- 表结构：`struct Call { char caller[160]; char callee[160]; int line; }` → 每条 324 字节；
  `1024 × 324 ≈ 332 KB` 常驻 `.bss`。
- 单元边界证据：`Parser.h.ct:140-147` 明说「object keeps a pointer（`ct_emit_bind_tables` 已有的安排）」——
  数组只能由属主单元定义；生成的头文件不带 `#include`，无法让别的单元直接看到 `struct Call`。
- **反证「不做动态分配」**：`g_maps` 用 `calloc`（SH-42），且同一文件里 `sym_alloc()` 也有堆路径。
  检索 `docs/`（`动态分配` / `MAX_CALLS` / `too many calls`）没有「解析阶段禁止分配」的规则；
  规范 §7 只把 `MAX_CALLS 1024` 列为固定容量上限之一
  （[language-spec.md:2135](../language-spec.md#7-容量上限)）。
- 结论：**固定是「单元边界 + 编译期常量容量」的工程选择，不是刻意的无分配策略。**
  找不到支持「刻意不做动态分配」的证据，这一条如实记录为「找不到」。

### E4 改成按需增长要动的地方

| 文件 | 锚点 | 改动 |
| --- | --- | --- |
| `frontend/parse/Expr.h.ct` | `:55`、`:5732`、`:6227` | 上限检查改为「容量满 → 扩容」；`record_call` 需要容量指针 |
| `frontend/parse/Parser.h.ct` | `:144`（`struct Call *calls`）、`:3759`（`g_calls`）、`:3790`（绑定） | `g_calls` 改指针 + `int g_callcap`；`calloc` 初始容量；扩容时 `realloc` 并回写 |
| `backend/emit/Emitter.h.ct` | `:240`（字段）、`:6110-6112`（`ct_emit_bind_tables` 签名） | 加一个 `int *callcap`（或让 `calls` 由 `Parser` 直接持有，emitter 只读 `ncalls`） |
| `main.ct` | `:103` | 绑定处补新参数 |
| `docs/language-spec.md` | `:2135` | 容量表去掉 `MAX_CALLS`（或标注「不再有上限」） |

连带影响：

- **内存模型**：从 332 KB 静态常驻改为按需增长（翻倍扩容，峰值 ≈ 2× 实际）。多一次
  `realloc` 拷贝（324 KB 量级），单次 < 1 ms，构建期不可感知。
- **自举引导**：**不受影响**。改动只落在 `ct-ast`（`selfhost/ct-ast/**`），L0 种子、L1、L2 不动，
  `check-goldens` 的 fixpoint 仍只比较它们自己的产物；`ct-ast` 必须仍能编译自己（`calloc`/`realloc`
  已是既有能力，`g_maps` 先例）。
- **绑定顺序**：`ct_emit_bind_tables` 在解析全部完成之后调用（`main.ct:103`），因此解析期扩容后
  换指针对 emitter 不可见——这是把扩容做在解析期、不需要改 emitter 读侧的关键前提。
- **诊断**：`--emit-map` 的 `calls` 数组是这张表的唯一消费者
  （[Emitter.h.ct:5730-5742](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5730-L5742)）；
  扩容不改变 JSON 形状。

量级判断：**小改动**。不需要新相，可作为 P1 缺陷/需求单直接排进当前或下一相的空档。

### E5 不改代码的绕法

| 绕法 | 有效性 | 上限 / 代价 |
| --- | --- | --- |
| 分层出库（`ct build --lib` 产 `.a`，消费方链接） | 有效 | 依赖单元不再进消费方的解析闭包，其调用点不计；代价是多一层构建产物与 ABI/符号管理 |
| 函数指针间接（`int (*fp)( )= f; fp(x)`） | 有效（实测 1100 条通过） | 调用点不再被记录；代价是可读性差、跨翻译单元时挡住内联 |
| 控制单次构建的闭包规模（拆成多个独立可执行/库） | 有效 | 上限就是「每次构建 ≤ 1024」；拆分粒度要按**闭包**算，不是按文件 |
| 把热点函数拆到独立单元 | **无效** | 实测：`lib` 单元 500 条 + 入口 600 条仍在**同一次构建**里 → 报错；独立单元只换了解析顺序，不减少累计 |

### E6 外部包实测余量

方法：在被测包的**入口文件副本**末尾追加一个探针函数，函数体含 N 条对已声明函数的调用，
二分查找「`too many calls`」边界；余量 = 1024 − N。全部在 `/tmp` 的仓库副本上做，未改任何包。

| 包 | 入口 | 余量（可再加的调用点） | 已用 ≈ | 占比 |
| --- | --- | --- | --- | --- |
| ct-json | `json.ct` | 753 | 271 | 26% |
| rill-dsl | `ct/src/main.ct` | **614** | **410** | **40%** |
| ct-fsguard | `test/fsguard/r09_check.ct` | 946 | 78 | 8% |
| ct-sse | `test/fixtures/s7_integration.ct` | 998 | 26 | 3% |
| ct-http | `test/fixtures/p3-chain.ct` | 1024（无计数） | ≈0 | — |

读数注意：

- 数字是**该入口闭包**的占用，不是包的完整实现面。`ct-http` 的入口只拉 `.h.ct`，
  实现单元不在闭包里，所以计数为 0——这**不代表**包本身零调用点，换真实入口需重测。
- 只统计「已声明自由函数」的调用；libc 与未声明函数免费，所以这里的占比不等于源码里 `(` 的密度。
- 结论：当前**没有任何下游包接近 1024**，最紧的 rill-dsl 还剩 60% 余量；
  该上限目前是「潜在的、会在包长大时突然出现」的问题，而不是正在阻塞谁的问题。

---

## 建议（不实施）

- 优先级 **P1**：不阻塞任何当前工作，但属于「会在某次无害提交后突然报错」的悬崖型限制。
- 修法取**解析期扩容**：`Parser` 持有 `(calls, ncalls, callcap)`，满则翻倍 `realloc`；
  emitter 仍只读 `ncalls`（绑定发生在解析完成后），把改动面压到 2 个文件即可。
- 若暂不修，把 §E5 的三条有效绕法写进 `docs/package-guide.md` 与规范 §7，
  并给 `too many calls` 的文案补一句「本上限按单次构建累计；可分层出库绕开」。
