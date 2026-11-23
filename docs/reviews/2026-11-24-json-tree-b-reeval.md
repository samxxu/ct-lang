# JSON 树方案 B 的 30 天重评（DOC-99 P-4 / LANG-28）

| 项 | 值 |
| --- | --- |
| 评估对象 | [LANG-28](../../issues/lang/lang-28-json-tree-b.md) 的 B1–B8 实施；设计见 [D-021](../decisions/D-021.md) |
| 触发 | [LANG-27](../../issues/lang/lang-27-container-cascade.md) 已 verified（2026-11-23）；30 天窗口截止 2026-12-23，本轮提前于 2026-11-24 完成 |
| 基线 | 本 worktree HEAD `74ed75f6`；v1.0.0 seed 编译器 `bootstrap/ct-ast`（`CTC_VERSION "1.0.0"`） |
| 方法 | 用 seed 实测五个最小探针；只读核对生成 C 与 `lib/core`；临时产物在 `.temp/p4/`（未入库）；不改代码、不改 D-021、不重开 PKG-24 |
| 结论 | **维持 A（arena + 索引）**；不切换 B（判据 1、2 不满足） |
| 角色/日期 | REV / ARCH，2026-11-24 |

> 本报告是 [DOC-99](../../issues/docs/doc-99-v11-prework-tracker.md) P-4 的交付物，回链
> [LANG-27](../../issues/lang/lang-27-container-cascade.md) /
> [LANG-28](../../issues/lang/lang-28-json-tree-b.md) /
> [D-021](../decisions/D-021.md) /
> [PKG-24](../../issues/packages/pkg-24-json-node-arena.md)。
> 结论只决定“是否现在切 B”，不改变 D-021 的设计文本，也不重开 PKG-24 的外部排期。

## 0. 五条判据总表

| # | 判据（[LANG-27](../../issues/lang/lang-27-container-cascade.md) §唤醒条件） | 判定 | 证据 |
| --- | --- | --- | --- |
| 1 | 递归 ADT 生成的 C 闭合布局（无 incomplete type / `offsetof` 失败） | **不满足** | v1.0.0 seed 对递归 `Vec`/`Map` 与非递归容器 payload 都报 `field has incomplete type`；见 §1 |
| 2 | 容器级联无泄漏、无双释放，ASan/UBSan 绿 | **不满足（按 B 树口径）**；容器字段子项满足 | `p_lang27_cascade` 17/17 绿；但 ADT payload 无 retain/release 胶水，工厂返回后出现 ASan `heap-use-after-free`；见 §2 |
| 3 | 子树跨文档语义明确 | **满足（契约层）**；实现未验证 | B 允许“retain 后跨文档”、禁止裸句柄/视图跨文档/跨线程；与 A 逐条对照见 §3 |
| 4 | `Map` 键深拷贝、`Str` owner 成本可接受 | **满足** | 16 字节键深拷贝约 14 ns；`String` owner 约 15 ns；量级见 §4 |
| 5 | 产出评估文档 | **满足** | 本文；回链见文首与 §7 |

结论三选一：**维持 A**。判据 1 与判据 2 的 B 树部分不成立；判据 3–5 即使满足也不足以
抵销前两条。

## 1. 判据 1：递归 ADT 布局闭合——不满足

### 1.1 seed 构建与最小复现

```console
$ cc -std=c99 -O2 -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o .temp/p4/ct
$ .temp/p4/ct --version
ct v1.0.0
$ printf 'enum N { Nil(), Arr(Vec<N> v) }\nint main(void) { N n = N.Nil(); return 0; }\n' > .temp/p4/p1/min.ct
$ CT_CORE_DIR=$PWD/lib/core .temp/p4/ct compile .temp/p4/p1/min.ct -o .temp/p4/p1/min.c
$ echo $?
0
$ cc -std=c99 -c .temp/p4/p1/min.c -o .temp/p4/p1/min.o
min.c:20:26: error: field has incomplete type 'struct Vec_N'
   20 |             struct Vec_N v;
      |                          ^
min.c:8:8: note: forward declaration of 'struct Vec_N'
$ echo $?
1
```

`ct compile` 本身退出 0；失败发生在 C 编译。后续三条 `_Static_assert(offsetof(...))` 也因
成员类型不完整而失败。错误不是笔误，而是发射顺序：生成 C 先写 `struct Vec_N;`，再写
`struct N`（内含 by-value `struct Vec_N v`），最后才写 `struct Vec_N { struct ct_buf *h; };`。

### 1.2 五种变体都失败

| 探针 | 源码 | emit | `cc -c` | 首个错误 |
| --- | --- | --- | --- | --- |
| V1 递归 Vec | `enum N { Nil(), Arr(Vec<N> v) }` | 0 | 1 | `field has incomplete type 'struct Vec_N'` |
| V2 递归 Map | `enum M { Empty(), Obj(Map<String, M> m) }` | 0 | 1 | `field has incomplete type 'struct Map_String_M'` |
| V3 非递归容器 | `enum S { A(Vec<int> v), B() }` | 0 | 1 | `field has incomplete type 'struct Vec_int'` |
| V4 嵌套 ADT | `enum T { Leaf(int v), Node(Vec<T> children) }` | 0 | 1 | `field has incomplete type 'struct Vec_T'` |
| V5 宿主 struct | `enum N { Nil(), Arr(Vec<N> v) }` + `struct W { Vec<N> v; }` | 0 | 1 | `field has incomplete type 'struct Vec_N'` |

V3 是关键：**连非递归的容器 payload 也失败**，所以这不是“递归”特有的环检测问题，而是
所有“ADT 的容器 payload 以值内嵌”都缺实例壳的提前定义。D-021 §1 的 B1 正是“ADT 之前
预发射具体实例壳”；本轮用只读的手工重排验证了这条路径：

```console
# 把 min.c 中 struct Vec_N 的三行壳移到 struct N 之前（仅 .temp 内试验）
$ cc -std=c99 -c .temp/p4/p1/min_fix.c -o .temp/p4/p1/min_fix.o; echo $?
0
$ cc -std=c99 .temp/p4/p1/min_fix.c -o .temp/p4/p1/min_fix && ./.temp/p4/p1/min_fix; echo $?
0
# 非递归 enum S 的 Vec_int 壳同样前移后通过
$ cc -std=c99 -c .temp/p4/p1/container_ok_fix.c -o .temp/p4/p1/container_ok_fix.o; echo $?
0
```

因此判据 1 的准确结论是：**v1.0.0 seed 不闭合；B1 预发射壳是可闭合路径，但尚未实现**。
按“实测通过才满足”的口径，判据 1 不满足。递归 `Map<String, M>` 的壳前移未做手工验证，
列为未覆盖项（§5）；它不改变本判据的结论。

## 2. 判据 2：级联无泄漏/双释放——容器满足，ADT payload 不满足

### 2.1 容器字段级联（LANG-27 的范围）：满足

```console
$ TMPDIR=$PWD/.temp/p4/tmp sh test/ast/p_lang27_cascade.sh .temp/p4/ct
ok   shape: Vec<T> field
ok   shape: Map<K,V> field
ok   shape: nested Vec<Vec<int>> field
ok   shape: Map<String, Vec<int>> field
ok   shape: out-of-range get zero value field
...
ok   runtime: element counts, zero handles and out-of-range get
ok   sanitizer: ASan / UBSan clean, same trace
ok   leak check: leaks --atExit reports 0 leaked bytes
OK p_lang27/cascade (glue shape, negative shapes, runtime, ASan/UBSan, leak check)
$ echo $?
0
```

17 项全绿，已覆盖嵌套 `Vec<Vec<int>>`、`Map<String, Vec<int>>`、空字段句柄、零句柄元素、
越界 `get` 零值、显式 `impl Drop` 负例、跨单元可见性负例。额外的临时探针再加深一层：

```console
$ ./.temp/p4/p1/deep.san        # 3 层 Vec、零句柄元素、越界 get(99)、缺失 Map 键
vvv 2 picked 0 hit -1
done
$ echo $?                        # ASan/UBSan stderr 为空
0
$ leaks --atExit -- ./.temp/p4/p1/deep.plain | grep 'total leaked'
Process ...: 0 leaks for 0 total leaked bytes.
```

### 2.2 ADT payload 级联：不满足（B3 未实现）

B 的树是 `Vec<JsonNode>` / `Map<String,JsonNode>`，元素是 ADT。当前 ADT 不生成
retain/release/drop 胶水，容器元素协议对 ADT 退化为空：

```c
enum P { S(String s), E() }
static P make_p(void) { String s = str_dup_len("...", 16); return P.S(s); }
```

生成 C 的关键片段（`.temp/p4/p1/adt_glue2.c`）：

```c
static struct P make_p(void) {
    struct String s = str_dup_len("abcdefghijklmnop", 16);
    struct P __ct_sret51 = ((struct P){ .tag = 0, .u = { .S = { .s = (s) } } });
    String_release(&s);            /* 先释放，返回值仍持旧句柄 */
    return __ct_sret51;
}
static void Vec_P__elem_retain(struct P *e) { (void)e; }
static void Vec_P__elem_release(struct P *e) { (void)e; }
```

`match` 绑定读该 payload 时 ASan 直接报 use-after-free：

```console
$ ASAN_OPTIONS=detect_leaks=0 ./.temp/p4/p1/adt_glue3
=================================================================
==...==ERROR: AddressSanitizer: heap-use-after-free ...
    #0 ... in String_cstr ...
freed by thread T0 here:
    #1 ... in String_release ...
    #2 ... in make_p ...
$ echo $?
134
```

这条不是 LANG-27 容器胶水的缺陷（容器字段部分 17/17 绿），而是 B 树必需的 **B3（ADT
retain/release/drop glue）缺失**：ADT 拷贝/返回不 retain，容器元素释放不递归，结果不是
泄漏就是悬空/双释放。判据 2 若按“B 树整树零泄漏、零双释放”判，**不满足**；只有按
“LANG-27 容器字段”判才满足。本报告采用前者，并明确记录后者已绿。

## 3. 判据 3：子树跨文档语义——契约层满足

### 3.1 B 的允许/禁止（建议契约，B7 实施时落为条款）

| # | 条款 | 允许 / 禁止 |
| --- | --- | --- |
| B-C1 | 同文档内拷贝、`match` 绑定、容器插入 | **允许**；按 D-021 §3 插入 retain，浅共享 |
| B-C2 | 把子树 retain 后存入另一文档 | **允许**；编译器在声明初始化、赋值、实参、`return`、容器插入、字段初始化处插入 retain |
| B-C3 | 源文档 `root` 释放后继续持有已 retain 的子树 | **允许**；refcount 保活，最后一次 release 才递归释放 |
| B-C4 | 不 retain 的裸句柄 / 借用视图跨文档保存 | **禁止**；离开作用域即失效，视图不延长生命周期 |
| B-C5 | 通过只读视图（`JsonArray` / `JsonObject`）写共享子树 | **禁止**；写只能走原文档的构造/替换 API |
| B-C6 | 用 release 后仍使用、或对同一句柄二次 release | **禁止**；二次 release 是硬错，不是 no-op |
| B-C7 | 引用环 | **禁止 / 作者责任**；refcount 不回收环，必须显式断环 |
| B-C8 | 跨线程 retain/release | **禁止无同步**；refcount 非原子，作者自负同步 |
| B-C9 | 共享子树序列化 | **允许但浅共享**：输出按引用展开；不自动深拷贝，需要独立副本时显式 `copy` |
| B-C10 | 失败形态 | 漏 retain → UAF；漏 release → 泄漏；多 release → 双释放；三种都必须在 ASan 夹具里有负例 |

一句话：**B 允许“retain 后跨文档”，禁止“裸共享、跨文档写、跨线程、环、release 后使用”。**

### 3.2 与 A 的逐条对照

| 维度 | A（现行：arena + 索引） | B（D-021） |
| --- | --- | --- |
| 所有权 | 节点属于唯一 arena，`(arena, index)` 不持有生命周期 | 每个 ADT 持有 refcount 句柄 |
| 子树跨文档 | **禁止**；要跨文档须重解析或按 schema 深拷贝 | **允许**（retain 后）；D-021 §7 明确取代 A 的“不跨文档” |
| 源文档释放后 | 子树 index 失效，访问是 UAF | 已 retain 的子树仍有效 |
| 拷贝语义 | index 拷贝，无所有权动作 | retain（浅共享），不递归复制 |
| 释放 | arena 一次性释放，无节点级 release | 逐节点 release，归零递归释放 payload |
| 环 | 无环问题 | 作者责任，refcount 不回收 |
| 字符串 owner | arena 持有 `String`，视图随 arena | 每个 `String` payload 自有 refcount；`Str` 只作临时视图 |
| 失败模式 | 越界 index、arena 释放后访问 | 漏 retain（UAF）、漏 release（泄漏）、多 release（双释放） |
| 成本 | 无 refcount；节点是整数 | 每节点 refcount + glue 调用；跨文档更灵活 |

判定：**契约层满足**——B 的允许/禁止已可写清，且与 A 的差异逐条有对应。**实现层未验证**：
B-C1/C2/C3/C6 都依赖 B3 的 retain/release 胶水，而 §2.2 已证明当前 seed 没有该胶水；因此
本轮没有“跨文档 retain 后 root 释放仍可读”的可执行探针，只有设计契约。

## 4. 判据 4：`Map` 键深拷贝 / `Str` owner 成本——满足

### 4.1 最小基准

探针（`.temp/p4/bench/bench.ct`，未入库）：16 字节键、`Map<String,int>` 与
`Map<char *,int>` 对照、10000 次重复；`cc -O2`、macOS arm64、clang；每格取 5 次运行的中位数，
单位 ns/操作。`String` 键走 `impl<V> Map<String,V>` 的深拷贝
（[Str.h.ct:1021](../../lib/core/Str.h.ct#L1021)）；`char *` 键是借用、不拷贝。

| 操作 | n=64 | n=256 | 说明 |
| --- | --- | --- | --- |
| `Map<String,int>` 构造（含线性扫描） | 53.8 | 153.2 | 每键；O(n) 扫描 |
| `Map<String,int>` 查找 | 46.5 | 170.3 | 每键；O(n) 扫描 |
| `Map<String,int>` 释放 | 4.6 | 4.3 | 每键 free |
| 新表单键（`String`） | 38.5 | 38.9 | 含表头分配 + 键深拷贝 |
| 新表单键（`char *`） | 24.9 | 25.0 | 无键拷贝 |
| `Str.to_string()` | 14.8 | 14.6 | 16 字节 owner |

### 4.2 量级结论

- **键深拷贝 ≈ 13.6–13.9 ns/键**（新表单键差：38.5−24.9、38.9−25.0），与
  `Str.to_string()` 的 14.6–14.8 ns 一致；主要是 `malloc(header+len+1)` + 拷贝，成本
  随键长线性、常数在 10 ns 量级，不是瓶颈。
- `Str` 本身是 16 字节借用视图（`char *` + `int`），无分配；`String` owner 才分配。
- **释放**：带 `String` 键的 Map 每键约 4.3–4.6 ns；借用 `char *` 键几乎为 0。
- **构造/查找是 O(K²)**：每键约 `25 + 0.95 × K/2` ns（由 n=64/256 拟合），K=1000 的对象约
  0.5 ms/对象。这是 `Map` 既有的“插入序数组 + 线性扫描”设计，**A 的
  `Map<String,int>` 同样承担**，不是 B 独有成本。
- 可接受性：常用 JSON 对象 K≤64（约 3.4 µs/对象）可接受；K 在千级时要意识到 0.5 ms
  量级。若将来把 Map 换哈希，A/B 都受益，与本判据的 B 专属成本无关。

## 5. 判据 5 与未覆盖项

判据 5 满足：本文即评估文档，回链 LANG-27 / LANG-28 / D-021 / PKG-24 / DOC-99。未覆盖：

1. 递归 `Map<String, M>` 的“壳前移”只做了 emit+错误记录，没有手工重排验证（递归 `Vec`
   已验证）；B1 若实现，应对 Vec/Map/嵌套 ADT 三类各跑一次。
2. B2（ADT 方法/下标链）、B4（`map binding`）、B5（表达式 `match`）、B6（ct-gen）、B7
   （只读视图/深度/基准）不在 P-4 五项内，本轮未评。
3. 跨文档 retain/release 没有可执行探针：依赖 B3；§3 的契约是设计层结论。
4. 基准只在一台 macOS arm64 上跑，键固定 16 字节，未接真实 JSON parser；数值只作量级。
5. `Map` 的 O(K²) 是既有实现，不在本轮提优化建议；与 A 共用，不构成 B 的否决项。

## 6. 结论与去向

**维持 A（arena + 索引），不切 B。** “B 限定子集”也不作为结论：只读树/单文档子集仍要判据 1 的布局闭合，`incomplete type` 不因子集而消失。理由按判据：

1. 判据 1 不满足：v1.0.0 seed 对所有“ADT 容器 payload”都报 incomplete type；B1 预发射壳
   是已证实的闭合路径，但未实现，不能按“已通过”计。
2. 判据 2 的 B 树部分不满足：ADT payload 没有 retain/release/drop 胶水，`Vec<P>` 元素
   释放是 no-op，工厂返回后 ASan 报 UAF；B3 未实现前，“整树自动释放”不成立。
3. 判据 3 的契约可写清，但 B-C1/C2/C3 依赖 B3；判据 4 的成本可接受且 A/B 同等，判据 5 完成。
   因此不满足“五条缺一不可”的切换条件。

去向与边界：

- **A 不变**：继续 arena + 索引；PKG-24 的 rejected 结论不重开、不排期；D-021 的设计文本
  不改（本轮只评实现条件）。
- **LANG-28 不批准实现**：`blocked-by` 改为“B1 + B3 未落地；重提条件 = B1 预发射壳与
  B3 ADT glue 落地后，用 `p_lang27_cascade` + 递归 ADT/工厂返回探针复跑判据 1、2 全绿”。
  按 LANG-28 §验收，“维持 A”应转 `rejected`；`status` 词按 [AGENTS §5.4](../../AGENTS.md) 归 REQ/USER，
  本轮不改状态字段，留所有者落。
- **若将来重提**：先 B1（实例壳预发射，Vec/Map/嵌套三类探针）→ 再 B3（ADT retain/release/
  drop glue，覆盖声明初始化、赋值、实参、`return`、容器插入、`match` 绑定、字段初始化）
  → 复跑本报告五条；A 作为回滚点保留，回滚只回 B1/B3，不碰 A 的包。
- **不自动切换**：即使 B1/B3 落地，也要新的评审结论与独立卡，不在本轮预授权。

## 7. 回链

- [LANG-27 容器级联](../../issues/lang/lang-27-container-cascade.md)（已 verified；本轮的
  `p_lang27_cascade` 基线）
- [LANG-28 JSON 树方案 B](../../issues/lang/lang-28-json-tree-b.md)（本报告更新其 `blocked-by`）
- [D-021 JSON 树方案 B 设计](../decisions/D-021.md)（B1–B8；本轮不改）
- [PKG-24 arena + 索引](../../issues/packages/pkg-24-json-node-arena.md)（rejected，外部仓；不重开）
- [DOC-99 P-4](../../issues/docs/doc-99-v11-prework-tracker.md)（本报告的跟踪卡）
- [JSON v1.1 提案评估](2026-11-23-json-v11-proposal-eval.md)（B 方案的前置评估）
- [LANG-26 绑定点转换](../../issues/lang/lang-26-binding-site-conversion.md)（D-020，与 B4 相关但不在本轮）
