# Phase 49 — `own` 所有权转移（初始化式接工厂返回值）

> **状态：规划中**（草案，待评审；未立项；本轮只写卡，不改代码）
> **基线**：HEAD `ff1b9140`（`ct-ast v0.44.1`）；起点为 PH-48 收口提交。
> **依赖**：[phase48.md](phase48.md)（AutoDrop 与 Drop 体走同一出口）。
> **规模**：编译器 130–250；夹具 40–80；文档 30–50；合计 **200–380**（±40%）。
> **版本**：收口 bump `v0.49.0`；tag / push 需用户单独授权。
> **纪律**：不引入所有权注解 / 借用检查；不改返回类型位置 `own` 的语义（只改文案）。

## 0 背景与缺口

**事实**（[gaps](../proposals/language-capability-gaps.md) G-3 / [ct-json](../proposals/ct-json-capability-blockers.md) J-4）：

```text
g2_own_return.ct:15:1: error: 'own' requires a malloc or calloc initialiser
g6_own_in_sig.ct:7:1: error: 'own' is only allowed inside a function body
```

规约把 `own` 的初始化式限定为 `malloc` / `calloc`（`docs/language-spec.md:397` 附近，S0 复核），
返回类型位置没有任何条款，实现按「只能在函数体内」直接拒。

后果：所有「构造即托管」的工厂 API（`json_decode`、`new_xxx()`）都写不出
`own struct JsonDoc *doc = json_decode(text);`，只能退成普通指针 + 手工释放。

## 1 目标 / 非目标

### 1.1 目标

| 编号 | 内容 |
| --- | --- |
| O1 | `own struct P *p = make(3);` 可编译；离开作用域按既有 AutoDrop 释放（Drop 体 + `free`） |
| O2 | 初始化式求值为 `0` 时记为空 own，块尾不释放（失败路径不 double-free） |
| O3 | 返回类型位置 `own` 仍拒绝，文案改为可操作：指向「返回普通指针 + 调用点 `own` 绑定」 |
| O4 | 与 `defer` / `errdefer` / `?` 的清理顺序不变（own 仍最后） |

### 1.2 非目标

| 不做 | 理由 |
| --- | --- |
| `own` 写进返回类型 / 所有权转移注解 | 要定义「谁在失败路径释放」，与 `?`、errdefer 纠缠；另案 |
| 借用检查 / 生命周期 | 属 REQ-MEM-2，仓库无 CFG 承载物 |
| `own` 指向栈对象 / 非堆对象 | 自由 `free` 会 UB；只接受堆来源 |
| 任意指针表达式（`own p = &x;`、`own p = arr + 1;`） | 无法证明堆来源，保持硬错 |
| 容器的 `release` 是否跑元素 Drop | 归 [phase50.md](phase50.md) |

## 2 设计决定

| 编号 | 决定 | 为什么不用另一种 |
| --- | --- | --- |
| **D49-1** | `own p = <expr>` 的 `<expr>` 允许两类：`malloc`/`calloc` 调用；**返回 `struct X *` 的函数调用**。其余指针表达式仍硬错 | 只认「调用」可由返回类型证明堆来源；允许 `&x` 会把栈地址交给 `free` |
| **D49-2** | 失败值为 `0` 时不计账，AutoDrop 判空 | 与 `Map::get` 返回 0 的契约一致；失败路径不需要额外语法 |
| **D49-3** | 不引入 owner 注解；`own` 仍是函数体内的局部绑定 | 注解会把本相扩成类型系统相 |
| **D49-4** | 返回类型位置 `own` 维持硬错，只改文案 | 语义上「转移给调用方」需要定义失败路径与重入；本相不碰 |
| **D49-5** | 同一指针不得有两个 `own` 绑定（可静态判定的字面形态）→ 硬错 L49-2 | 双释放是最常见的误用；只在可判定时拦，不做数据流 |

## 3 诊断

| 编号 | 触发 | 文案（草案） |
| --- | --- | --- |
| **L49-1** | `own` 初始化式既非 `malloc`/`calloc` 也非返回指针的函数调用 | `'own' needs a malloc/calloc call or a function returning a pointer` |
| **L49-2** | 同一标识符被两个 `own` 声明绑定（同作用域字面形态） | `'p' is already owned here; a second 'own' would free it twice` |
| **L49-3** | `own` 出现在返回类型位置（既有） | `'own' is a local binding; return a plain pointer and bind it with 'own' at the call site` |

## 4 任务切分

| 切片 | 内容 | 边界 |
| --- | --- | --- |
| **S0** | 只读核查：`own` 判定点、`malloc` 白名单、AutoDrop 记账、`?` / errdefer 的顺序、SH-33 相邻规则；记 `baseline: <sha>` | 不产提交 |
| **S1** | 红证：工厂返回值形态（现报 L49-1）+ 零值形态 + 返回类型位置文案 | 只含夹具与 `baseline:` |
| **S2** | 判定扩展：只放行「返回指针的函数调用」 | ≤2 文件 |
| **S3** | 零值记账 + L49-2 + L49-3 文案 | 不动 AutoDrop 顺序 |
| **S4** | 文档：`own` 一节与 `memory-guide.md` 工厂示例 | spec 冲突时记 `blocked-by` |
| **S5** | 收口：11 道门禁全绿、bump `0.49.0` | 收口 |

依赖：S0 → S1 → S2 → S3 → S4 → S5；每片 ≤150 行、≤3 文件。

## 5 完成定义（四件套）

| 面 | 交付 |
| --- | --- |
| 实现 | `own p = factory()` 可用；零值不释放；既有 `malloc` 形态不变 |
| 诊断 | L49-1 / L49-2 / L49-3 各一条负例，逐字断言 |
| 文档 | 「构造即托管」的标准写法与失败语义写清 |
| 门禁 | 新夹具进 `check-ast.sh`；ASAN 夹具本相必跑；`check-all.sh` 11 道全绿 |

## 6 验收

| ID | 断言 | 命令 / 阈值 |
| --- | --- | --- |
| **E49-1** | `own P *p = make(3);` rc=0，块尾执行 Drop 且 ASAN 无泄漏 | `p49_own_factory` + `check-sanitizers.sh` |
| **E49-2** | 工厂返回 0 时 rc=0，块尾不释放、不崩溃 | `p49_own_null` |
| **E49-3** | `own int *p = &x;` rc=1，文案 L49-1，不写 `.c` | `p49_errors.sh` |
| **E49-4** | 返回类型位置 `own` rc=1，文案 L49-3 | 同上 |
| **E49-5** | 既有 `own p = malloc(...)` 夹具产物逐字不变 | `check-goldens` 绿 |
| **E49-6** | `own` + `?` 提前返回：清理链顺序不变、无 double-free | `p49_own_try` + ASAN |
| **E49-7** | 零回归：`check-ast` / `check-warnings` 全绿；11 道门禁绿 | 收口贴原始末行 |

## 7 风险与不做项

| 编号 | 风险 / 不做项 | 触发信号 | 处置 |
| --- | --- | --- | --- |
| R49-1 | 同一指针两个 own → 双释放 | ASAN double-free | D49-5 只拦可判定形态；其余写进文档 |
| R49-2 | `?` 提前返回时 own 记账与 errdefer 交叉 | 清理链输出顺序错 | E49-6 三组合夹具；顺序以 PH-40 冻结为准 |
| R49-3 | 依赖 PH-48 的跨单元 Drop 体 | 跨单元 own 释放不执行 | 48 先收口；49 的夹具含跨单元一例 |
| R49-4 | 被要求顺手支持返回类型 `own` | 评审提出 | D49-3 / D49-4 已明写非目标；不临时扩面 |
| R49-5 | golden 漂移 | `check-goldens` 红 | 逐字节核对后重生成 |
