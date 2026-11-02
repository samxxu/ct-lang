# 决策草案：容量上限策略与第三十三批方向

> 基线：`249447a`（第三十二批收口），工作树干净。
> 关卡实测：`check-ast.sh` 300 passed、`check-warnings.sh` 145 ok、`check-all.sh` 九关全绿。
> 本文只列取舍与建议，不含实现改动；确认后再按既有流程写 `docs/design/batch33-*/{spec,tasks,checklist}.md`。

## 一、容量上限策略

### 现状

- 策略是**固定上限 + 越界硬报错**，绝不静默截断（language-spec §7）。
- L0（冻结种子）的上限表在 §7；ct-ast 把用户可见的一批整体抬高：`MAX_NODES` 65536、
  `MAX_TRAITS` 64、`MAX_STRUCTS` 128、`MAX_METHODS` 64、`MAX_FIELDS` 64、`MAX_FUNCS` 256、
  `MAX_PARAMS` 16、`MAX_VARS` 4096、`MAX_TYPES` 256、`MAX_CALLS` 1024；`MAX_TEXT` / `MAX_PATH` /
  `MAX_SCOPE` / `MAX_UNITS` / `MAX_IMPORTS` / `MAX_MAPS` 不变。
- `MAX_NODES` 65536 是自举前置：ct-ast 解析自身已需要超过 32768 个节点。
- 另有一处独立上限：`selfhost/l2/core.ct` 的 `MAX_MAP_IMPLS` 256（`--emit-map` 的反向 impl 表），
  构建 ct-ast 时余量已极少；下批若新增 impl 方法，必须先扩它（会动 `selfhost/l2/**`）。

### 选项

| 方案 | 做法 | 优点 | 缺点 |
| --- | --- | --- | --- |
| **A. 维持现状**（推荐） | 固定上限 + 硬报错，不改 | 内存可预测、无分配失败路径、与 L0 口径一致、自举不动点稳定、`--emit-map` 的固定数组不变 | 真实项目撞顶只能改编译器重发版；上限是编译期常量，用户不可调 |
| B. 定点抬高 / 可配置 | 只把撞顶的那几项做成编译期常量或 `--max-*` 选项 | 语义不变，解决个别撞顶；改动面小 | CLI 与新常量面扩大，文档 / golden 成本；只对少数人生效 |
| C. 全面动态分配 | arena 与各表改堆分配，容量只受内存限制 | 去掉所有人上限 | 跨单元改动（arena / 符号表 / 模块表 / 缓存），失败路径与泄漏分析复杂化；自举依赖 `malloc`；确定性下降；`--emit-map` 结构变化；需重生成大量 golden |

### 建议

**选 A**，并把「回访触发条件」写进 roadmap：

1. 某个真实项目 / 官方 binding 撞到某个上限；
2. 或者自举本身再次逼近 `MAX_NODES`。

触发时先做 **B（定点抬高）**，只有「抬到多大都会撞」且确有外部需求时才评估 C。
理由：C 的收益是「理论上不再撞顶」，成本却落在编译器最敏感的三处（自举、确定性、泄漏分析），
而目前没有任何实测项目撞顶的证据；B 在触发前没有收益，提前做等于无谓扩张。

## 二、第三十三批方向

### 实测缺口（当前 HEAD，逐条跑过 ct-ast）

| 构造 | 结果 |
| --- | --- |
| `_Atomic(int) a;` | `error: expected a name` |
| `__attribute__((unused)) static int g;` | `error: expected a name` |
| 局部变量属性 `__attribute__((unused)) int x = 1;` | `error: expected an expression` |
| `_Alignas(16) static int g;`（对齐在存储类之前） | `error: unexpected token` |
| `impl` 方法上的属性 | `error: unexpected token`（文档已列为子集外） |
| C23 后缀 `1z` | `error: unexpected token` |
| 十六进制浮点 `0x1p3` | `error: unexpected token` |
| `_BitInt(32)` | `error: unexpected token` |

已可用、无需再动：`_Atomic int` / `_Thread_local int`（作为未知类型名透传）、整数字面量后缀、
`static_assert`、`_Noreturn`、`__restrict`。

### 候选与取舍

| 主题 | 内容 | 改动面 | 价值 | 风险 |
| --- | --- | --- | --- | --- |
| **H. 真实头文件兼容**（推荐） | `_Atomic(type)`、声明符之前的属性、局部变量属性、`_Alignas` 在存储类之前 | 中：集中在 `parse_type` / `parse_func` / 局部声明入口；`_Atomic(type)` 可复用 `_Alignas` 的括号透传写法 | 高：真实头文件与 GNU 风格代码最常撞的四种写法 | 中：属性位置多，需逐个入口接线；可能要新增 1 个 impl 方法（受 `MAX_MAP_IMPLS` 约束） |
| C. C23 残余 | `1z` 后缀、`_BitInt(N)`、十六进制浮点 | 小到中：词法器 + `parse_primary` / 类型拼写 | 低：少见 | 低：`_BitInt` 与十六进制浮点都要按拼写透传，边界要写清 |
| E. 生态 | 更多官方 binding、方言文档 | 不在编译器内 | 取决于需求 | 低 |
| T. 类型检查 / 泛型 | — | 极大 | — | 改变编译器性质，不建议 |

### 建议

**第三十三批选 H（真实头文件兼容）**，把 C 主题留作后续小批（或在 H 收口时一并处理 `1z`）。
理由：H 解决的是「拿真实头文件写 ct 代码时的第一道墙」，而 C23 残余的四个构造在日常代码里出现频率明显更低；
H 的四个子项共享同一套「类型 / 声明拼写透传」机制，放一批做比分两批更省接线。

H 的实施顺序建议：`_Atomic(type)`（最小、无新方法）→ `_Alignas` 顺序 → 声明符前属性 → 局部变量属性
（最后一项若必须新增 impl 方法，先单独扩 `MAX_MAP_IMPLS` 并等你确认）。

## 三、外部事项（不占批次）

- `ct-pkg` 的 GitHub 组织名 / registry 命名空间建议尽早占位（2026-10-17 检索时仍可用，尚未注册）。
  **2026-11-02 更新**：组织已创建（`github.com/ct-pkg`，与 `PkgOps` 的默认 registry 一致）；包的组织方式与
  首批清单留在 **Phase 18**，本阶段只承接重叠的 `std` / index / CI / 构建元数据，见
  [roadmap](../../roadmap.md) 的 Phase 18 行。

## 四、需要你确认的两点

1. 容量上限：选 **A（维持现状 + 回访触发条件）**，还是 B / C？
2. 第三十三批：按 **H（真实头文件兼容）** 开，还是先做 C23 残余 / 生态？

确认后我按既有流程先写 `docs/design/batch33-*/` 三件套，再落码。
