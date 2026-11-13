# Phase 31 立项卡第五轮窄范围复核

- **对象**：`docs/history/design/phase31.md` @ `9e4e255`（1037 行；提交只含此文件，+48/−19）
- **范围**：仅此卡，只验本轮修的 2 High + 2 Medium + Low；Phase 32–36 卡片未评审、未改动；`phase34/36-draft.md` 等他人文件未触碰、未提交。
- **方式**：只读。未改卡片、未 commit、未改 golden/版本号/门禁；未跑 `check-all.sh`；无新增仓库产物。
- **结论：GO**（0 High / 2 Medium / 5 Low；两条 High 均闭合，Medium 为落地时的排序与断言补全，不阻断开工）

---

## 0 两条 High 的闭合判定

| High | 判定 | 一句话依据 |
| --- | --- | --- |
| **H1** 链式材料化的两个落点 | **闭合** | 字段级核对通过：卡片用 `text`（接收者实例名）而不是 `text2`（方法名）去 `find_struct`，与发射分支 `3917-3921` 的现成判定完全同形；`static_ctype` 五参数签名核对无误；短路位置（`3910` / `3963`）经 aux 分支顺序验证既不漏路径也不误伤 aux 5；`text3` 复用不冲突；`static_ctype → 0` 硬错不会把可编译程序变红（详见 §1） |
| **H2** E31-15 计数公式 | **闭合** | 逐目录数过：`1073`、`−19`、`−19`、`+19`（16+3）、`+15`（181–185/187–195/199，`186` 确实不建）、`N_neg`、`N_mod` 全部对得上，`1073−19−19+19+15 = 1069`（详见 §2） |

---

## 1 H1 逐问答案

### 1.1 Q1：`N_MCALL` 各字段装什么

在 `Expr.h.ct` 的构造点逐个核对（括号为行号）：

| aux | 含义 | `a` | `b` | `text` | `text2` | `text3` |
| --- | --- | --- | --- | --- | --- | --- |
| 1 / 2 | 已解析的 trait 方法（`.` / `->`），`3440-3450` | 接收者 | 实参链 | trait 名 | 方法名 | 空 |
| 5 | 显式静态映射调用（`ns::Trait.m(...)`），`4243-4250`、`4286-4293` | **-1** | 实参链 | host 命名空间 | 方法名 | **映射实例名 `qv`** |
| 6 | 类型宿主 / 未解析方法的 recipe，`3597-3618`、`4352-4357` | 接收者 | 实参链 | 接收者静态类型 `rt2` | 方法名 | **接收者原文 `nodes[n].text2`** |
| 9 / 10 | 实例结构体固有方法（`.` / `->`），`3910-3921` 发射 | 接收者 | 实参链 | **接收者实例结构体名**（`Vec_int` 或 `struct Vec_int`） | 方法名 | 空 |
| 11 | 静态固有方法（`Vec<int>::from`），`4162-4169` | **-1** | 实参链 | 实例结构体名 | 方法名 | 空 |

- **卡片写对了**：它明确写「`N_MCALL` 的 `text2` 是方法名（`get`/`len`），`find_func` 必然 < 0」，并改用 `find_struct(<text 去掉 "struct " 前缀>)` —— 用的正是接收者实例名所在的 `text`，且注明「与发射分支 3917-3921 同一判定」。发射器现文：
  ```
  3913  snprintf(base, sizeof base, "%s", nodes[n].text);
  3916  if (strncmp(base, "struct ", 7) == 0) ... nodes[n].text + 7
  3920  si = self->sym->find_struct(base);
  3921  if (si < 0 || !self->structs[si].is_inst) fail ...
  ```
  没有「换个地方犯同一个错」。**卡片已写清「接收者类型从 `text` 取」**（第 329 行与 770 行 S21a）。
- 唯一漏提：`text3` 在 aux 6 也被占用（见 Q4）。

### 1.2 Q2：`static_ctype` 签名

声明与定义都在 `Expr.h.ct`：

```
146   int static_ctype(int n, char *out, int cap, int *array_depth, int depth);
3130  int static_ctype(int n, char *out, int cap, int *array_depth, int depth)
3137      *array_depth = 0;
3138      if (n < 0 || depth > 8) return 0;
```

五个参数：节点号、输出缓冲、缓冲长度、**数组层数出参（`int *`）**、递归深度（`int`，`> 8` 放弃）。卡片写的
`static_ctype(hoist_calls[i], buf, sizeof buf, &depth, 0)` 与签名逐项吻合，方法确实存在（属 `struct Expr`）。✅

### 1.3 Q3：短路位置

发射器 `N_MCALL` 各分支的实际顺序（`grep -n`）：

```
3777  aux == 5      （静态映射；text3 = 映射实例名，3785 使用）
3801  aux == 6      （type-host recipe；text3 = 接收者原文，4355 写入）
3910  aux == 9/10   （实例固有方法；aux 9 在 3925 写 &）
3939  aux == 11     （静态固有方法）
3963  if (nodes[n].a < 0) fail…     ← 接收者检查
3965-3968  接收者白名单（N_VAR/N_INDEX/N_CALL/N_MEMBER/N_ARROW/N_INTO_SELF/N_INTO）
3978  aux == 4（trait 值派发在 fallback 内继续）
```

- **(a) 不漏路径**：hoist 出来的节点无论在哪儿被 `emit_expr`，都会进入它自己的 `aux` 分支——aux 9/10 在 `3910` 短路；trait 派发（aux 1/2/3/4）在 `3963` 之后的 fallback 短路。两类根都被覆盖。
- **(b) 不误伤 aux 5**：aux 5 / 6 / 11 都在 `3910` 之前 `return 0`，`3910` 与 `3963` 的短路根本到不了它们；aux 5 的 `text3`（映射实例名）不会被当临时名打印。卡片把落点定在分支入口而不是 `case N_MCALL:` 首行，判断正确。✅

### 1.4 Q4：`text3` 复用的占用情况

- 占用者只有两个：**aux 5**（映射实例名，`3785` 读取）与 **aux 6**（接收者原文，`4355` 写入）。
- aux 6 双重隔离：① `hoist_scan:1749-1750` 对**外层**调用有 `aux != 6`；② 卡片给 `N_MCALL` 根的 kind 判定限定 `aux == 9 || aux == 10`，aux 6 不可能成为被 hoist 的根；③ 两个短路点都在 aux 6 分支之后。因此不会踩。
- 卡片第 339 行的理由只写了「aux 5」，**没写 aux 6**。不构成缺陷，但理由不完整（Low L3）。

### 1.5 Q5：`static_ctype` 返回 0 就硬错，会不会把能编译的代码变红

**结论：不会**，理由三条（均已在代码里核实）：

1. hoist 只发生在**接收者位置**：`hoist_scan` 只在「当前节点是 `N_MCALL`（方法调用），其接收者链的根是调用」时记录（`1737-1738`、`1751-1766`），因此 `v.clear();` 这类普通语句调用永远不会被 hoist，不会因返回 `void` 判不出类型而硬错。
2. 会被 hoist 的 `N_MCALL` 接收者，在改动前只有两种命运：trait fallback 在 `3965-3968` 直接报「method receiver must be a variable, an element, a call or a field chain」；或走 aux 9/10 **无条件写 `&`**（`3925`）发射 `&Vec_int_get(...)`，到 `cc` 才炸。改后把 `cc` 错误提前成 `ct` 错误，没有「本来能编译」的代码被新拒。
3. 真正会被 `static_ctype` 判不出的只剩 aux 5/6 根，而它们已被 kind 判定排除在 hoist 之外。

**建议（Low）**：把第 334 行的措辞收紧为「**对已决定材料化的 `N_MCALL` 根（aux 9/10）与 trait 派发根**，`static_ctype` 返回 0 时硬错」，避免被读成「所有表达式类型判不出都硬错」。

---

## 2 H2 逐数核对

| 项 | 值 | 逐目录/逐行核对结果 |
| --- | --- | --- |
| 基线总数 | `1073` | `bd91bfe` 上 `check-ast.sh` 末行 `1073 passed, 0 failed`（R4 已实跑）✅ |
| 迁出负例显式断言 | `−19` | 15 条 `not subscriptable`（6036/6037/6044–6047/6050–6054/6057–6059/6062）+ 6038 + 6040 + 5759 + 5760，逐行在位 ✅ |
| 迁出负例自动扫描 | `−19` | `test/ast/errors/*.ct` 实测 **219** 个，`check-ast.sh:3022-3030` 每文件一条 `ok`；迁出 19 个后 219→200 ✅ |
| 迁入正例目录 | `+19` | `165–180` = **16** 个（15 下标 + `map_brace_init`）+ `196–198` = **3** 个（`container_element` / `container_element_map` / `container_iface`）= 19；正例循环每目录恰好一条 `ok "$name"` ✅ |
| 本相新增正例目录 | `+15` | 卡片列 `181`、`182`、`183`、`184`、`185`、`187`、`188`、`189`、`190`、`191`、`192`、`193`、`194`、`195`、`199` = **15**；全文 `grep -o 'ast/[0-9]*'` 只出现这些编号（另有一条既有 `ast/142`），**无 `186`**，与卡片「186 不建目录」一致 ✅ |
| 新增负例 | `N_neg` | §8 的 23 条 `L31-*` + E31-18 的 `L29_8_map_literal*` 护栏，排除基线既有 `L29_*` 与迁出文件 ✅ |
| 新增 module 夹具 | `N_mod` | `test/modules/p31_cross_unit_*` + `p31_mapentry_param`，至少 2 ✅ |

算术：`1073 − 19 − 19 + 19 + 15 = 1069`，即 `1069 + N_neg + N_mod`，与卡片第 811 行逐字一致 ✅

**「两个 −19 为什么不能合并」的判断成立**：这 19 个 `.ct` 在门禁里贡献的是**两条独立计数**——`check-ast.sh` 里一条显式 `p29_neg`/`p29_diag` 断言，以及 `errors/*.ct` 自动扫描的一条 `ok`。文件迁走时两条同时消失（38 条），合并成 `−19` 会把丢失的断言数少算一半；`+19` 是同一批文件作为正例目录后的新增计数，与两个减项不是同一计量单位。卡片第 830 段的解释站得住。

---

## 3 Medium / Low

### 3.1 第 6 项（E31-29，Medium M1 + Low L5）

- **`-A2` 窗口与真实排版吻合**：现有产物 `probe_alias.c:27-30` 是
  ```
  v.h = (struct ct_buf *)(malloc(sizeof(struct ct_buf)));
  if (v.h == 0) {
      return v;          → 改后为 abort();
  }
  ```
  `-A2` 正好覆盖 `abort();`；`-A1` 只会看到 `if (...)` 那一行。
- **三次 `malloc` 成立**：新 `Vec::from` 的三个分支是「空表 header / 非空 header / data」，前两条参数为 `sizeof(struct ct_buf)`，第三条为 `sizeof(v.data[0])`，与「第三条 `malloc(` 唯一不以 `sizeof(struct ct_buf)` 为参数」吻合；`abort();` 恰 3 处成立。`from` 体内无 `free(` 也有现实对照：基线 `Vec.h.ct:71-75` 现在正是 `free(v.h); v.h = 0;`。
- **M1（新增）**：E31-29 的①②③④全部只覆盖 `Vec_*_from` / `Vec_*_push` / `Map_*_put`，**`Map::from` 的 header 失败没有产物断言**。D31-21 把 `Map::from` 的 header 失败列为 `abort()` 契约，但 `Map::from` 是全新代码（基线不存在），既没有运行时夹具能制造 OOM，也没有 grep 断言，属于不可观察项。修法：加一条 ⑤「`Map_*_from`（两个 impl 块各一）体内 `malloc(` 行 `-A2` 含 `abort()`，且每个函数体内 `abort();` 恰 1 处（data 增长走 realloc 失败 `return m`）」。
- **L5**：「`Vec_*_from` 体内」的提取方式没写。`grep` 不能限定函数体，建议给出可复制的切分命令（如 `awk '/^static .*Vec_.*_from\\(/,/^}/'`）后再做 `-A2` 与 `abort();` 计数。

### 3.2 第 7 项（§2.1，Low L1）

- 卡片第 56、63 行与第 1020 行写 `roadmap.md:1025`。**当前 1024 才是英文 Phase 31 行，1025 是英文 Phase 32 行**（并行会话增删行导致漂移；上一轮评审时确实在 1025）。中文行 46 正确。
- 两个「旧范围」判断本身为真：`docs/roadmap.md:46` 与 `:1024` 里确实还是 `D31-1–D31-17` / `E31-1–E31-23` / `L31-1–L31-21`；两行的收尾也确为「落地时窗口不扩张、无需归档」。
- 卡内已无「已完成」类表述（`grep -n "已完成"` 为空），§2.1 与 §1.5 口径一致。
- **修法**：三处 `:1025` 改 `:1024`；更稳的写法是不钉行号，改用 `grep -n "| 31 | \*\*Container capability close-out" docs/roadmap.md`（并行会话每动一次表就漂一次）。

### 3.3 Low 清单（其余）

| 编号 | 位置 | 问题 | 修法 |
| --- | --- | --- | --- |
| **L2** | 卡 S27b（748） | 写「**3 处**数据元素尺寸写法」，随后列出 `from 71/79`、`push 124`、`Map 215/285` 共 **5 处** | 改为「Vec 3 处（71/79/124）+ Map 2 处（215/285）」，或直接「5 处」 |
| **L3** | 卡第 339 行 | 不能放 `case N_MCALL` 首行的理由只写了 aux 5；`text3` 还被 aux 6 占用（`4355` 写接收者原文） | 理由补一句「aux 6 的 `text3` 是接收者原文，且 aux 6 被 `aux != 6` 与「根仅 aux 9/10」双重排除」 |
| **L4** | 卡 §3.3.1（327–351） | 链式访问受既有 `top` 限制：只在语句 / 赋值 / 声明 / `return` 起首可用（`hoist_rval` 调用点 `2838`、`3057`），嵌在别的表达式里会报「a method call on a temporary is only allowed at the start of a statement or of an assignment」。卡片未写明，用户可能以为 `if (g.get(0).len() == 1)` 也可用 | §3.3.1 末尾补一句限制，并在落地时同步 `docs/language-spec.md` |
| **L5** | 卡 E31-29（825） | 「体内」无切分命令 | 见 §3.1 |

### 3.4 Medium M2：S21a 的类型来源依赖 S21b 的实例绑定

- S21a（卡第 770 行）要求 `emit_hoists` 对 `N_MCALL` 用 `static_ctype` 取临时类型；而 `static_ctype` 的 `N_MCALL` 分支（`Expr.h.ct:3230-3252`）现在只 `ctype_expand` 模板声明的返回类型，**把 `T` 实例化成 `int` / `struct Vec_int` 属于 S21b**（卡第 771 行）。
- 切片顺序是 S21a → S21b。S21a 单独落地时，链式访问的模板类型还拿不到实例绑定，产物会是 `T __ct_tmp0 = Vec_int_get(&g, 0);` —— 编译不过。因为链式夹具（S22、`ast/199`）在 S21b 之后才落，仓库在那一段仍可构建、门禁仍绿，所以不是阻断；但卡片的切片边界与「每片可独立验证」的口径不一致。
- 修法（任选一）：① 把「`static_ctype` 的 `N_MCALL` 实例绑定」从 S21b 前移到 S21a（S21a 上限 140→按实际调，S21b 相应减）；② 在 S21a 行注明「临时类型在 S21b 落地前对 `Vec<T>` 仍是模板名，S21a 不得单独配链式夹具；S21a→S21b 之间不插入可运行链式样例」。

---

## 4 Battle 裁定

1. **两个 `−19` 是否重复计数**：不是，不能合并。每个夹具在 check-ast 里同时被显式断言行与 `errors/*.ct` 自动循环各断言一次；迁走一个文件丢两条断言，合并会把少掉的 19 条藏起来。
2. **`find_struct(text)` 是否又一次把方法名当类型名查**：不是。`text2` 才是方法名；卡片明确用了 `text`（接收者实例结构体名），并引用 `3917-3921` 的现成判定，与发射器一致。
3. **`static_ctype → 0` 硬错是否会误杀**：不会，hoist 仅在接收者位置且根限定 aux 9/10 或 trait 派发；原先这些形态要么在接收者白名单被拒、要么发射 `&调用` 到 `cc` 才炸。该硬错是把错误提前，不是新增拒绝。
4. **`text3` 复用是否安全**：安全。aux 5 在短路点之前 `return`；aux 6 既不满足「根 aux 9/10」也被外层 `aux != 6` 排除；aux 11 的 `text3` 为空。
5. **`roadmap.md:1025` 是否要改成 1024**：要。当前 1025 是英文 Phase 32 行；但并行会话反复增删会继续漂移，建议改用 grep 锚点而不是钉行号。

---

## 5 附录：关键核对输出

```text
# N_MCALL 字段（Expr.h.ct）
3440-3450  aux = arrow ? 2 : 1；text2 = 方法名；text = trait 名
3597-3618  未解析方法 → aux 6；text = 接收者静态类型；text3 = 接收者原文（4355）
4243-4250 / 4286-4293  aux 5；text = host；text2 = 方法名；text3 = 实例名 qv；a = -1
4162-4169  aux 11；text = 实例结构体名；a = -1

# 发射分支顺序（Emitter.h.ct）
3777 aux 5   3801 aux 6   3910 aux 9/10（3925 写 &）   3939 aux 11
3963 接收者检查   3965-3968 白名单   3978 aux 4
3913-3921  snprintf(base, nodes[n].text); strip "struct "; find_struct(base); is_inst

# static_ctype（Expr.h.ct）
146 / 3130  int static_ctype(int n, char *out, int cap, int *array_depth, int depth)
3138         if (n < 0 || depth > 8) return 0;

# hoist 入口与调用点
1749-1757  n 为 N_MCALL、aux != 6；root=接收者去 N_MEMBER/N_ARROW；root 须 N_CALL && !text3 && find_func>=0
1762-1765  写 text3=__ct_tmpN、记入 hoist_calls
1781-1793  按 find_func 取 ret、raw_call=root 发声明、复位
2838 / 3057  hoist_rvalue → emit_hoists → emit_expr（语句/声明/赋值/返回入口）

# H2 计数来源
ls test/ast/errors/*.ct | wc -l  → 219
grep -o 'ast/[0-9]*' phase31.md  → 165/181-185/187-195/196-198/199/142（无 186）

# 41 的构成（lib/std/Vec.h.ct）
grep -c "self->data"    → 10
grep -c "self->entries" → 27
from 的 4 行 v.data：67、71、78、79；push 的 sizeof 在 124；Map put 的 sizeof 在 215/285

# roadmap
46   | Phase 31 | … D31-1–D31-17） | E31-1–E31-23 与 L31-1–L31-21 …
1024 | 31 | **Container capability close-out** … D31-1–D31-17 …
1025 | 32 | **Type-safety net (tier B)** …            ← 卡片引用的 1025 已不是 Phase 31
```

> 工作区：只新增 `2026-11-11/phase31-review-r5/outputs/phase31-review-r5.md`；未跑 `check-all.sh`，未产生构建产物，未触碰他人草稿。
