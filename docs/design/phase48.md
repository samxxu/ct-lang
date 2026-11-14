# Phase 48 — Drop 语义闭环（指针字段胶水 + 跨单元 Drop 体）

> **状态：规划中**（草案，待评审；未立项；本轮只写卡，不改代码）
> **基线**：HEAD `ff1b9140`（`ct-ast v0.44.1`）；与容器族正交，可与 PH-46 并行开发，门禁串行。
> **依赖**：无硬前置；收口后 [phase49.md](phase49.md) 才能开工（同一 AutoDrop 出口）。
> **规模**：编译器 200–350；夹具 60–120；文档 40–80；合计 **300–550**（±40%）。
> **版本**：收口 bump `v0.48.0`；tag / push 需用户单独授权。
> **纪律**：不引入「自动 free 子指针」；不改 Drop 顺序；不改 `--lib` 的 `.abi.h` 导出规则。

## 0 背景与缺口

**缺口① 指针字段胶水把 `T**` 当 `T*`**（[gaps](../proposals/language-capability-gaps.md) G-4）：

```c
/* 生成物 */
static void Node_Drop_drop(void *self) {
    struct Node *_self = (struct Node *)self;
    Leaf_Drop_drop(&_self->leaf);      /* 形参是 void *，实参是 struct Leaf ** */
}
```

实测输出 `leaf drop 22792752`（id 读成指针低 32 位），`ct` / `cc` / 运行全 rc=0、无诊断。

| 主题 | 位置 |
| --- | --- |
| 自动胶水发射（值字段递归） | `selfhost/ct-ast/backend/emit/Emitter.h.ct:3098-3139`，关键行 `:3132` |
| 清理路径的同类胶水 | `Emitter.h.ct:5800-5801` |
| 规约依据（「按字段递归生成释放胶水」） | `docs/language-spec.md:2325` 附近，S0 复核 |

**缺口② 跨单元 `delete` 调空桩**（G-2 / [ct-json](../proposals/ct-json-capability-blockers.md) J-3）：

消费单元看到 `use Drop` 但看不到 `impl Drop`，于是发一份 `(void)_self` 空桩并调用它；
真实体在定义单元且是 `static`。实测 `delete r` 只打印 `done`，`res drop 7` 不出现。
`own` 的 AutoDrop 走同一入口，因此**整套 Drop 在多单元下不可用**。

## 1 目标 / 非目标

### 1.1 目标

| 编号 | 内容 |
| --- | --- |
| O1 | 指针字段的胶水对**子对象**调用：`struct T *f` → `if (_self->f) T_Drop_drop(_self->f);`（判空、不取地址、不 free） |
| O2 | 跨单元 `delete` / AutoDrop 调用的 `<S>_Drop_drop` 是定义单元的真实体：定义单元发非 `static`，消费单元发 `extern` 声明 |
| O3 | 不可见即硬错（L48-2），**不再发空桩**；只有「无 Drop 字段」的合法空体保留 |
| O4 | 两处胶水发射点（`:3132` 与 `:5800-5801`）同判据；ASAN 夹具覆盖两级指针字段 |

### 1.2 非目标

| 不做 | 理由 |
| --- | --- |
| 自动 `free` / `delete` 子指针 | 所有权仍归显式 `impl Drop`；本相只修「递归调 Drop 体」 |
| Drop 顺序、`defer` / `errdefer` / `own` 的相对顺序 | 由 PH-38 / PH-40 冻结，不动 |
| Drop 体进 `.abi.h` 导出面 | Drop 是语言胶水，不是 C ABI；只需链接可见（D48-2） |
| 容器的 `release` 是否跑元素 Drop | 现状是不跑；归 [phase50.md](phase50.md) 的契约讨论，不塞进本相 |
| 跨单元 `use Drop` 的过渡期 warning | 直接硬错；warning 在 `ct check` 下等于 rc=1（PH-42 已确认兼容期不存在） |

## 2 设计决定

| 编号 | 决定 | 为什么不用另一种 |
| --- | --- | --- |
| **D48-1** | 指针字段只递归 Drop 体，不 free | 自动 free 需要所有权信息（谁分配、共享与否），属新语义；本相只修「传错指针」 |
| **D48-2** | Drop 胶水符号单独一档链接性：定义单元发非 `static`，消费单元发 `extern` 声明；**不经过**方法可见性判定 | PH-42 的 `pub` 管的是用户方法；把 Drop 胶水塞进同一判据会让所有未标 `pub` 的 Drop 跨单元失败，等于把修复面扩大一倍 |
| **D48-3** | 看不到 impl 就硬错，不发空桩 | 空桩是静默替代，违反「禁吞错」；诊断必须指明类型与定义单元 |
| **D48-4** | 两处胶水共用同一个「字段是否指针」判定 | 两处分别判会漏（`:5800` 是清理路径，容易只修一处） |
| **D48-5** | golden 只重生成、逐字节核对 | 仓库红线：手改 `*.expected.*` 视为失败 |

## 3 诊断

| 编号 | 触发 | 文案（草案） |
| --- | --- | --- |
| **L48-1** | （内部不变式）指针字段胶水必须判空且不取地址 | 由夹具断言，不作为用户文案 |
| **L48-2** | 本单元见 `use Drop` 但 impl 在另一单元且不可见 | `type 'S' uses Drop but its impl is not visible from this unit (defined in <unit>); export the impl or free it explicitly` |

## 4 任务切分

| 切片 | 内容 | 边界 |
| --- | --- | --- |
| **S0** | 只读核查：两处胶水点、`has_drop_impl` 跨单元传播、`--lib` 的 `visibility`/`static` 规则、AutoDrop 路径；记 `baseline: <sha>` | 不产提交 |
| **S1** | 红证：`p48_ptr_field_glue`（健康输出应为 `leaf drop 2`）、`p48_cross_unit_drop`（`res drop 7` + `done`）、ASAN 脚本 | 只含夹具与 `baseline:` |
| **S2** | 指针字段判定 + 两处发射修正 | ≤3 文件 |
| **S3** | 跨单元链接修正（非 static + extern 声明）+ L48-2 | 不动 `--lib` 头 |
| **S4** | 文档：spec 的 Demo/delete 段与 `memory-guide.md` 一处；spec 被文档线占用时记 `blocked-by` | 只改该相独占句 |
| **S5** | 收口：11 道门禁全绿、bump `0.48.0` | 收口 |

依赖：S0 → S1 → S2 → S3 → S4 → S5；每片 ≤150 行、≤3 文件。

## 5 完成定义（四件套）

| 面 | 交付 |
| --- | --- |
| 实现 | 指针字段胶水正确（判空、不取地址）；跨单元调用真实体；空桩不再出现在「有 impl 不可见」场景 |
| 诊断 | L48-2 命中且不落 `.c`；「无 Drop 字段」的合法空体保留 |
| 文档 | `delete` / AutoDrop 的跨单元语义与「显式释放责任」写清 |
| 门禁 | 新夹具进 `check-ast.sh`；ASAN 脚本本相必跑（不进 11 道硬门禁）；`check-all.sh` 11 道全绿 |

## 6 验收

| ID | 断言 | 命令 / 阈值 |
| --- | --- | --- |
| **E48-1** | 指针字段：输出 `leaf drop 2` 且只出现一次 | `p48_ptr_field_glue` 运行输出逐字断言 |
| **E48-2** | 跨单元：输出 `res drop 7` + `done` | `p48_cross_unit_drop` |
| **E48-3** | ASAN：无 use-after-free / double-free / leak | `p48_drop_asan.sh` rc=0 |
| **E48-4** | 无字段无 impl 的 `use Drop` 空体行为不变 | 既有 Drop 夹具继续绿 |
| **E48-5** | impl 不可见时 rc=1、文案 L48-2、不写 `.c` | `p48_errors.sh` |
| **E48-6** | 两处胶水点同判据（值字段不变、指针字段修正） | `grep` 生成 C 断言两种形态 |
| **E48-7** | 零回归：`check-ast` / `check-warnings` / `check-goldens` 全绿 | 收口贴原始末行 |

## 7 风险与不做项

| 编号 | 风险 / 不做项 | 触发信号 | 处置 |
| --- | --- | --- | --- |
| R48-1 | 跨单元符号与 PH-42 可见性判定冲突 | `drop` 判私有后链接失败 | D48-2 单独一档链接性；E48-2 锁 |
| R48-2 | `--lib` 归档的 `visibility` / `ZERO_AR_DATE` 影响 Drop 体符号 | 导出工程链接失败 | S0 先核 PH-39 的符号面；不改 `.abi.h` |
| R48-3 | 胶水 golden 大面积变化 | `check-goldens` 红 | 逐字节核对后重生成 |
| R48-4 | 把「容器 release 不跑元素 Drop」顺手改掉 | 容器夹具变化 | 明写非目标，留 PH-50 |
| R48-5 | ASAN 只在本地/nightly | 有人宣称「进了硬门禁」 | 卡面写明：本相必跑，但不计入 11 道硬门禁 |
