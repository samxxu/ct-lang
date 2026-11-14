# Phase 48 — Drop 语义闭环（指针字段胶水 + 跨单元 Drop 体）

> **状态：规划中**（定稿候选；本卡只写规格，实现由外部 harness 执行）
> **归属**：本仓库维护规格与判据；实现由外部 harness 交付（[手册](phase46-52-handoff.md)）。
> **基线**：本卡最后一次提交；与容器族正交，可与 PH-46 并行开发，门禁串行。
> **规模**：300–550 行（编译器 + 夹具 + 文档）。
> **版本**：`v0.48.0`（若采纳 U-4 A）。

## 0 一句话目标

让「指针字段递归 Drop」与「跨单元 `delete`/AutoDrop 调真实 Drop 体」同时成立，且不再有静默空桩。

## 1 本卡做 / 本卡不做

| 做 | 不做 |
| --- | --- |
| 指针字段胶水：`if (_self->f) T_Drop_drop(_self->f);`（判空、不取地址、**不 free**） | 不自动 `free` 子指针（所有权仍归显式 `impl Drop`） |
| 胶水按**类型 owner 单元**发射（不是「本单元符号表」） | 不改 Drop 顺序、不改 `self` 绑定 |
| 跨单元通过 `extern` 声明调用真实体；头文件传播「impl 存在/可见」信号 | 不把 Drop 体放进 `.abi.h` |
| 有 impl 但不可见 → 硬错 L48-2，**不再发空桩** | 不改容器的 `release` 语义 |
| 补 `Emitter.h.ct:2615-2619` 的 `static` 原型通道（改为条件发射） | 不把 `try_release_payload` 纳入「同判据」 |

## 2 前置依赖

无硬前置。**与 PH-46 共享「单元归属策略」一节**：46 的 D46-2 先冻结（条目下沉），本卡 D48-2 引用同一判定函数；不合并两相。

## 3 现状（实测）

| 形态 | rc | 输出 |
| --- | --- | --- |
| `struct Node { Leaf *leaf; } use Drop;`（单单元） | 0 | `leaf drop 22792752`（id 被读成指针低 32 位） |
| `impl Drop` 在 `.h.ct`、`delete` 在 `main.ct` | 0 | 只打印 `done`，缺 `res drop 7` |

复现：

```sh
mkdir -p /tmp/p48 && cd /tmp/p48
"$work/ct-ast" g8.ct -o g8.c && cc -std=c99 g8.c -o g8 && ./g8      # leaf drop <垃圾>
"$work/ct-ast" build d4/main.ct -o d4out && cc -std=c99 d4out/*.c -o d4 && ./d4  # 只有 done
```

代码锚点（裁决席已核）：

| 事实 | 位置 |
| --- | --- |
| 胶水只为「本单元符号表 + 非模板」发射；`has_drop_impl` 真则跳过 | `Emitter.h.ct:3101-3115` |
| 无 impl 时发函数体；无 Drop 字段则 `(void)_self`（空桩） | `Emitter.h.ct:3114-3139` |
| 本单元对所有 `uses_drop` 发 `static … _Drop_drop(void *self);` | `Emitter.h.ct:2615-2619` |
| 第二发射点 `try_release_payload` 对指针字段早退 | `Emitter.h.ct:5764-5770`、`:5800-5801` |

## 4 修法方向（两个独立决策）

### 4.1 决策一：胶水归谁发（D48-1，不依赖可见性）

| 点 | 位置 | 改法 |
| --- | --- | --- |
| 发射过滤 | `Emitter.h.ct:3101-3115` | 判据从「本单元符号表」改为「类型 owner 单元」（与 PH-46 的 `inst_elem_foreign` 同源判定） |
| 指针字段分支 | `Emitter.h.ct:3132` | `if (_self->f) <T>_Drop_drop(_self->f);` |
| 第二发射点 | `Emitter.h.ct:5764-5770`、`:5800-5801` | 明确**不在本卡断言面**；若同一指针字段形态出现，按 D48-1 判空，不做 `&` 取址 |

### 4.2 决策二：跨单元怎么看见（D48-2，需裁决 U-2）

| 项 | 方案（默认 A，见 U-2） |
| --- | --- |
| 符号可见性 | Drop 胶水**单独一档**：定义单元发非 `static`，不经 PH-42 的 `pub` 判定 |
| 消费单元 | 只发 `extern void <S>_Drop_drop(void *);`，不发函数体 |
| 头文件 | 传播 `uses_drop` + `has_drop_impl`（或等价可见性位）；消费单元据此三态决策 |
| 三态 | ① impl 可见 → `extern`；② 无 impl → 本单元按字段发胶水；③ 有 impl 不可见 → 硬错 L48-2，不落 `.c` |
| 原型通道 | `Emitter.h.ct:2615-2619` 的 `static` 原型改为条件发射：仅当本单元会发函数体时发 `static`，否则发 `extern` |

## 5 任务切分

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| S0 | 只读核对上表五处 + 头文件字段传播路径；产出三态矩阵 | 无提交 |
| S1 | 红证：单单元指针字段 + 跨单元 Drop（两探针） | `test: PH-48 红` |
| S2 | 胶水 owner 过滤 + 指针字段判空（决策一） | ≤150 行 |
| S3 | 头文件信号 + 三态 + `extern`/原型通道（决策二） | ≤150 行 |
| S4 | L48-2 + 负例 | ≤2 文件 |
| S5 | 文档：跨单元 Drop 与显式释放责任 | 或 `blocked-by` |
| S6 | 收口 | §6 |

## 6 验收判据

| ID | 命令 / 比对 | 通过条件 | 失败条件 |
| --- | --- | --- | --- |
| E48-1 | `p48_ptr_field_glue` 运行，stdout `cmp` 与期望两行表 | 逐字相等 | 出现垃圾 id / 多次 drop |
| E48-2 | `p48_cross_unit_drop` 运行，stdout `cmp` `res drop 7` + `done`（锁顺序） | `cmp` rc=0 | 缺行或乱序 |
| E48-3 | `bash selfhost/check-sanitizers.sh`（`detect_leaks=0`） | rc=0，无 UAF/double-free 报告 | 任一 sanitizer 报告 |
| E48-4 | 既有 Drop 夹具（`test/ast/225_generic_drop`、`63_own_return_field`）产物快照 `cmp` | rc=0 | 任一 diff |
| E48-5 | `p48_errors.sh`：impl 不可见 → rc=1、文案 L48-2、不写 `.c` | 逐字命中 | 生成空桩或落 `.c` |
| E48-6 | 生成 C 中指针字段胶水必须含 `if (_self->f)` 且无 `&_self->f`；值字段胶水不变 | `grep` 断言通过 | 出现 `&_self->` |
| E48-7 | `bash selfhost/check-all.sh` | 11 green | 任一失败 |

## 7 范围外归属

| 项 | 归属 |
| --- | --- |
| 自动 free / 递归释放所有权 | 不做（显式 `impl Drop`） |
| 容器的 `release` 是否跑元素 Drop | PH-50 契约 |
| `Handback` 胶水 | PH-38（只保证原型通道不被本卡改坏） |
| `.abi.h` 导出 Drop 体 | 不做 |

## 8 风险与回滚

| 风险 | 信号 | 回滚 |
| --- | --- | --- |
| owner 过滤误伤 `Vec`/泛型实例 | 既有夹具红 | 回滚 S2；过滤条件限定 `uses_drop && !is_template` |
| 三态判定漏「可见但私有」 | E48-5 未命中 | 回滚 S3，先补头文件信号位 |
| 与 PH-42 可见性冲突（若 U-2 选 B） | 链接失败 | 按 U-2 结论重裁；默认 A 不受影响 |
| golden 漂移 | `check-goldens` 红 | 逐字节核对后重生成；否则回滚 |
| 把 sanitizer 当硬门禁宣传 | 报告措辞 | 卡面已写：本相必跑，不计入 11 道 |
