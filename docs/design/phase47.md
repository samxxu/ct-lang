# Phase 47 — 容器键协议与键所有权（`Str` 键 + `put_owned`）

> **状态：规划中**（草案，待评审；未立项；本轮只写卡，不改代码）
> **归属**：本仓库维护规格与判据；**实现由外部 DeepSeek harness 执行**（交接见 [计划 §10](phase46-52-plan.md)）。
> **基线**：`94556f29`（规划提交，`CTC_VERSION 0.44.1`）；起点为 PH-46 收口提交。
> **依赖**：[phase46.md](phase46.md)（同一 `Map` 生成面与 `lib/std/Vec.h.ct`）。
> **规模**：编译器 150–280；`lib/std` 100–180；夹具 80–160；文档 50–80；合计 **380–700**（±40%）。
> **版本**：收口 bump `v0.47.0`；tag / push 需用户单独授权。
> **纪律**：不改 `Map` 的线性扫描与 API 面（除新增 `put_owned`）；不做任意用户类型键协议；不改 `get` 返回指针形态。

## 0 背景与缺口

**缺口① 键类型白名单**（[gaps](../proposals/language-capability-gaps.md) E-2 / [ct-json](../proposals/ct-json-capability-blockers.md) J-2）：

```text
e2b_str_key.ct:5:26: error: Map does not support key type 'struct Str' (use int, long or char *)
```

限制由编译器发出（`selfhost/ct-ast/frontend/parse/Expr.h.ct:2174`），负例固定在
`selfhost/check-ast.sh`（`:6964` / `:7128` 附近，S0 重定位），但 `language-spec.md` 里搜不到这条限制。

用 `char *` 作键时，含 `\0` 的两个不同键会撞成一个（实测 `len=1 v1=2 v2=2`）。
`Str` 本身可用（`str_from_len("a\0b",3)` 保住内嵌 NUL，实测 `len=3 3 cmp=-1`）——问题只在键。

**缺口② 键不被复制、所有权无条款**（E-4 / N-13）：

```c
char buf[8]; strcpy(buf, "key1"); m.put(buf, 1);
strcpy(buf, "key2");            /* "key1" 查不到：键只存了指针 */
```

实测 `key1=0x0 key2=0x1017d6fd8`。`Map::put` 把键指针直接赋给条目
（`lib/std/Vec.h.ct:391`），`release` 只释放值、不碰键；规约没有任何一句定义键的所有权。

**内部事实**：`Map<char *, V>` 是特化（`strcmp`，`Vec.h.ct:219-296`），通用 `Map<K, V>` 用
`memcmp(&es[i].key, &k, sizeof(k))`（`Vec.h.ct:370-376`）——对 `struct Str` 是**指针身份比较**，
不是字节内容比较。所以只放开白名单会得到一个错误实现，必须同时给 `Str` 特化。

## 1 目标 / 非目标

### 1.1 目标

| 编号 | 内容 |
| --- | --- |
| O1 | `Map<Str, V>` 可用：键按「长度 + 字节」比较，`\0` 之后不同的键不碰撞 |
| O2 | 键所有权契约落条款：`put(k, v)` 的键是**借用**（生命周期须覆盖容器）；新增 `put_owned(k, v)` **复制键**，`release` 时释放 |
| O3 | `put_owned` 对 `char *` 与 `Str` 两种键形态都成立（`Str` 复制字节，不是只复制 struct） |
| O4 | 诊断更新：其余键类型仍硬错，文案列出可用键类型并指向 `put_owned` |
| O5 | `Map<char *, V>` 既有 125 条 golden 与运行行为逐字不变（默认仍是借用） |

### 1.2 非目标

| 不做 | 理由 |
| --- | --- |
| 任意用户类型作键（`Map<struct UserKey, V>`） | 见 D47-1：内置容器实例不走普通 `T: Trait` 约束，开协议等于给内置容器加约束注入，属类型系统相 |
| 哈希表 / 改线性扫描 | `Map` 是数组线性扫描；换结构会改全部生成物与复杂度承诺 |
| 改 `get` 返回指针形态、越界/缺键语义 | 归 [phase50.md](phase50.md) |
| 键的 `foreach` 排序 | 维持插入序（PH-29 契约） |
| 自动推断键所有权 | 不做类型推断；借用是默认，复制要显式 `put_owned` |

## 2 设计决定

| 编号 | 决定 | 为什么不用另一种 |
| --- | --- | --- |
| **D47-1** | 本期只加 `Str` 内建键，不做任意类型键协议 | 内置容器的实例化不经过普通 trait 约束；开协议要先给 `Map` 加 `K: Key` 注入，是独立类型系统相。触发条件：出现第二个必须自定义键的真实包 |
| **D47-2** | `Str` 键比较 = 先比 `len`、再 `memcmp` 字节；照抄 `Map<char *, V>` 特化的写法，不新增模板参数 | 与既有特化同形，生成物可预测；不引入 `hash`/`eq` 钩子 |
| **D47-3** | 默认所有权保持**借用**（零迁移），复制走显式 `put_owned` | 改默认会改所有 `Map` 生成物与性能，且要同时定义释放 |
| **D47-4** | `put_owned(Str k, V v)` 复制 `k` 的字节；`release` 释放复制品；`Str` 的 Drop/引用语义不动 | 只复制 struct 会让字节仍归调用方，等于没复制 |
| **D47-5** | 白名单只增 `Str` 一项；其余类型仍硬错 | 放开任意类型会得到「指针身份比较」的错误实现（见 §0） |

## 3 诊断

文案在 S1 冻结前可改，冻结后逐字断言；位置指向键类型表达式起点，一次只报一条。

| 编号 | 触发 | 文案（草案） |
| --- | --- | --- |
| **L47-1** | 键类型不在白名单 | `Map does not support key type '<T>' (key types: int, long, char *, Str; use put_owned to copy a borrowed key)` |
| **L47-2** | `put_owned` 用在非 `char *` / `Str` 键上 | `'put_owned' needs a char * or Str key`（若该形态在解析期不可见，则 S0 改为不提供该入口，不报错） |

## 4 任务切分

| 切片 | 内容 | 边界 |
| --- | --- | --- |
| **S0** | 只读核查：白名单判定点、两条既有负例断言行、`Str` 的 `str_from_len` / `str_compare` 契约、`Map` 两个特化的差异、`release` 现状；记 `baseline: <sha>` | 不产提交 |
| **S1** | 红证：`Map<Str, int>` 含 `\0` 键、`put_owned` 后改源缓冲仍可查、`release` 无泄漏 | 只含夹具与 `baseline:` |
| **S2** | `lib/std/Vec.h.ct` 的 `Str` 键特化 + 白名单放行 | 不改 `char *` 分支 |
| **S3** | `put_owned`（两种键形态）+ `release` 释放复制键 | 只加入口，不改 `put` |
| **S4** | 诊断文案 L47-1 与既有负例断言同步更新（本相允许的冻结面变更，卡上记录） | 只改该两条断言 |
| **S5** | 文档：键契约（借用 / 复制 / 释放时机）与 `put_owned`；spec 段等文档线落定 | 记 `blocked-by: docs-correction` 若冲突 |
| **S6** | 收口：11 道门禁全绿、bump `0.47.0` | 收口 |

依赖：S0 → S1 → S2 → S3 → S4 → S5 → S6；每片 ≤150 行、≤3 文件。

## 5 完成定义（四件套）

| 面 | 交付 |
| --- | --- |
| 实现 | `Map<Str, V>` 比较正确（含内嵌 `\0`）；`put_owned` 两形态可用；默认借用不变 |
| 诊断 | L47-1 文案更新并逐字断言；非白名单键仍 rc=1 且不落 `.c` |
| 文档 | 键契约（谁复制、谁释放、何时失效）写进容器章节与 `package-guide.md` |
| 门禁 | 新夹具进 `check-ast.sh`；`Map<char*,V>` 125 条 golden 不变；`check-all.sh` 11 道全绿 |

## 6 验收

| ID | 断言 | 命令 / 阈值 |
| --- | --- | --- |
| **E47-1** | `m.put(str_from_len("a\0b",3),1); m.put(str_from_len("a\0c",3),2);` → `len()==2`，两次 `get` 各得其值 | `p47_str_key` 运行输出逐字断言 |
| **E47-2** | `put_owned(buf, v)` 后改 `buf`，原键仍可查；`release` 后 ASAN 无 leak / double-free | `p47_put_owned` + `check-sanitizers.sh` |
| **E47-3** | `Map<char *, V>` 既有夹具与产物逐字不变 | `check-goldens` 绿，`p47_charptr_regression` 输出相等 |
| **E47-4** | `Map<struct X, V>` 仍 rc=1，文案 = L47-1，且不写 `.c` | `p47_errors.sh` 两条负例 |
| **E47-5** | 键插入序与 `foreach` 行为不变 | 既有 `Map` 遍历夹具继续绿 |
| **E47-6** | 零回归：`check-ast` / `check-warnings` 全绿；11 道门禁绿 | 收口贴原始末行 |
| **E47-7** | 红证链完整（`baseline: <sha>` + 原始输出，test 提交为父提交） | `git log --oneline -2` |

## 7 风险与不做项

| 编号 | 风险 / 不做项 | 触发信号 | 处置 |
| --- | --- | --- | --- |
| R47-1 | 改 `lib/std/Vec.h.ct` 引起所有 `Map` 实例 golden 漂移 | `check-goldens` 红 | 逐字节核对后重生成；`char *` 分支输出必须零 diff |
| R47-2 | `Str` 键的复制与 PH-36 `Str` Drop 双释放 | ASAN double-free | `put_owned` 用独立字节缓冲，不复用 `Str` 的 Drop 路径 |
| R47-3 | 负例文案是冻结面（既有两条断言） | 既有 `L29-*` 夹具红 | 本相明确记录「文案变更」并同步断言，不加新限制 |
| R47-4 | 与文档线并发改 `language-spec.md` | 同一行两条修补线 | 按 [phase46-52-plan.md](phase46-52-plan.md) §3.1：按句切片、等落定 |
| R47-5 | 用户期待「任意类型键」而本相只给 `Str` | 评审提出 | D47-1 已写明触发条件；不临时扩面 |

## 8 交接：复现与验收锚点

### 8.1 现状复现（基线 `94556f29`，全部在 `/tmp`，不入仓）

前置：按 [计划 §10.2](phase46-52-plan.md) 构建 `$work/ct-ast`。

```sh
mkdir -p /tmp/p47 && cd /tmp/p47
# e2b.ct: Map<struct Str, int> m;              —— 期望编译期硬错
# e5.ct : char buf[]; m.put(buf,1); 改 buf；  —— 期望 rc=0 但查不到旧键
"$work/ct-ast" e2b.ct -o e2b.c ; echo "type rc=$?"
"$work/ct-ast" e5.ct -o e5.c && cc -std=c99 e5.c -o e5 && ./e5 ; echo "copy rc=$?"
```

| 探针 | 期望 rc | 原始输出（引自提案 E-2 / E-4，2026-11-15 实测） |
| --- | --- | --- |
| `e2b.ct` | 1 | `e2b_str_key.ct:5:26: error: Map does not support key type 'struct Str' (use int, long or char *)` |
| `e5.ct` | 0 | `key1=0x0 key2=0x1017d6fd8`（键未复制，改缓冲即失效） |

### 8.2 验收锚点（外部可见证据）

| 证据 | 判据 | 允许变化 | 不允许 |
| --- | --- | --- | --- |
| 键语义 | `p47_str_key`：`len==2`，两个含 `\0` 的键各取回原值 | 新增夹具 | 用 `strcmp` 语义掩盖碰撞 |
| 复制语义 | `p47_put_owned`：改源缓冲后仍可查；释放后不崩溃 | 新增 API 与夹具 | 默认 `put` 改成复制（破坏零迁移） |
| 生成物 | `Map<char *, V>` 既有 125 条 golden 逐字节不变 | 仅新增 `Str` 键产物 | 既有 `Map` 产物任何 diff |
| 文案 | `p47_errors.sh` 命中 L47-1，rc=1，不落 `.c` | 只允许更新既有两条键类型断言文案（本相登记） | 放宽为 warning 或删除负例 |
| 内存 | `bash selfhost/check-sanitizers.sh` rc=0（`detect_leaks=0`，**不宣称泄漏检测**） | — | 以 sanitizer 通过代替泄漏判据 |
| 泄漏 | `check-warnings.sh` 的编译期分析无新增告警 + 运行期计数器 | — | 声称 LeakSanitizer 已跑 |
| fixpoint 与全量 | `check-goldens.sh` fixpoint 段 rc=0；`check-all.sh` 末行 `OK (11 hard gates green)` | — | 改门禁/版本 |

撞上 §11：本相是 #3 的正题；#1（共享头）由 PH-46 先关闭，若 46 未收口则本相夹具改用指针元素。
