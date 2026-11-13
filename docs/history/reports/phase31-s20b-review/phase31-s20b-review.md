# Phase 31 · S20b 独立复核（`35f63fd`）

> 范围：只审 `35f63fd`（S20b：Map 字面量嵌套容器值的实例编码规范化）及其连带改动。
> 未改实现、未改卡片、未 commit；所有实测产物在 `/tmp`，未写主工作区 `selfhost/`。
> 复核时 HEAD 为 `a693dca`（含 `35f63fd`），对照基线为 `bd1980c`（S20 前）。

## 0. 四问结论

| # | 问题 | 结论 | 级别 |
| --- | --- | --- | --- |
| 1 | `D31-4` 是否真的解冻 L29-15；删负例是否获授权 | D31-4 **确实**写了「L29-15 解冻：允许」（`phase31.md:43`），但同卡 `:385` **明确要求保留** `foreach_container_element`；被删夹具是 `Vec<MapEntry<char*,int>>`，属 L29-15 的「条目类型」分支，不在 D31-4 的「接口/容器元素」表述内。删除未进变更记录，守卫变死代码 | **High** |
| 2 | 删 `p29_diag` 断言是否等于删门禁判据、有无等价替代 | 是。原断言含位置 7:5、冻结文案、恰好一条 error 三条精确约束；通用扫描只验「任意 positioned diagnostic」。新正例 201 只覆盖 `Vec<Vec<int>>`，不覆盖 `MapEntry` 元素，全仓已无该语义用例 | **Medium** |
| 3 | E29-3 改名是否只改名字 | 是。只改 grep 字符串（`check-ast.sh:5987-5988`），139 夹具与期望输出未动，实测四个层级的 tag 全在，语义未放宽 | **通过**（附 1 Low） |
| 4 | `Vec_Vec__int` 是否新规范；碰撞与哈希 | 编码一致性成立；但与用户同名 struct 的 `carg` 完全相同，`ct_inst_add` 会把两个**布局不同**的实例静默合并（旧方案不会）。今日靠 C 层 `redefinition` 暴露，编译器自身无诊断。哈希分支条件/算法未变，输入只变短 | **Medium**（附 2 Low） |

---

## 1. High：删掉的是一条被卡片点名保留的门禁判据

**证据**

- `phase31.md:43`：「**L29-15** | `foreach` 不迭代接口/容器元素 | **解冻**：允许；`item` 是借用视图 | D31-4」。所以「D31-4 没解冻 L29-15」不成立。
- `phase31.md:385`：「**保留**（不被本相推翻，删了会丢覆盖）：`generic_impl_missing_method`（6039）、`container_vptr_struct`（6041）、`foreach_container_element`（5753）。」——同一张卡要求保留。
- `phase29.md:437`：L29-15 的原文是「`foreach` **元素/条目**类型不可值拷贝」；被删夹具正是「条目」分支。D31-4 的解冻理由（借用视图）没点名条目。
- 变更记录 `phase31.md:1040` 声明「只增不改正文判据」，`:1045` 的 S20b 记录只写了编码根治与 `Map<char *, Map<char *, int>>` 转正，**未记录**删除负例、删除断言、E29-3 改名。

**删了什么**

- `selfhost/check-ast.sh`（原第 5783 行）：`p29_diag foreach_container_element 7:5 "foreach cannot iterate a container of 'struct MapEntry_char_p_int' (interface, vptr-bearing or container element)"`。
- `test/ast/errors/foreach_container_element.ct` 整个文件（`Vec<MapEntry<char *, int> > edges; foreach (edges) …`）。

**为什么删得掉：守卫被这条改动弄成死代码**

- 守卫在 [Stmt.h.ct](file:///Users/samxx/trae-ws/ct-lang/selfhost/ct-ast/frontend/parse/Stmt.h.ct#L2337-L2355)：用 `ct_inst_split(ins[inst].carg[kk], …)` 取模板名，只有取到 `"MapEntry"` 才报错。
- [Symbols.h.ct:1815-1828](file:///Users/samxx/trae-ws/ct-lang/selfhost/ct-ast/frontend/sym/Symbols.h.ct#L1815-L1828) 要求 `carg` 里含 `<`；S20b 后 `carg` 是 `struct MapEntry_char_p_int`（无 `<`），`ct_inst_split` 直接返回 -1。
- 实测（同一夹具，`/tmp/p31del.ct`）：
  - `bd1980c` 编译器：`/tmp/p31del.ct:6:5: error: foreach cannot iterate a container of 'struct MapEntry_char_p_int' (interface, vptr-bearing or container element)`，rc=1。
  - 当前编译器：rc=0。
- 结论：不是「判据该合法了」，而是「守卫不再可命中」。提交只删测试、不删守卫、不记变更，等于用实现改了判据。

**可验证修法（二选一，均须进 `phase31.md:1040` 变更记录）**

- (a) 保留判据：恢复夹具与 `p29_diag` 行；把守卫改为按元素类型身份判定，例如对 `ins[inst].ctype[kk]` 取 tag 后 `ct_inst_find`，判 `tmpl == "MapEntry"`，不要从 `carg` 里 `split`。
- (b) 判据演进：在 `:1040` 明确写「L29-15 对条目元素一并解冻」，同步删 `:385` 的保留项，删掉 `Stmt.h.ct:2337-2355` 的死守卫，并补 `Vec<MapEntry<char*,int>>` 的 foreach 正例。

---

## 2. Medium：被删断言无等价替代，`MapEntry` 语义零覆盖

- `p29_diag`（[check-ast.sh:5764-5778](file:///Users/samxx/trae-ws/ct-lang/selfhost/check-ast.sh#L5764-L5778)）是三条精确约束：非零退出、`file:line:col: error: <冻结文案>`、`error: ` 计数为 1。
- 通用负例扫描（[check-ast.sh:3048-3063](file:///Users/samxx/trae-ws/ct-lang/selfhost/check-ast.sh#L3048-L3063)）只要求「有一个 positioned diagnostic」，不校文案；文件已删，扫描也不再覆盖。
- 新增正例 [201_foreach_container_view/prog.ct:7-16](file:///Users/samxx/trae-ws/ct-lang/test/ast/201_foreach_container_view/prog.ct#L7-L16) 只覆盖 `Vec<Vec<int>>`；全仓 `grep 'Vec<MapEntry' test/` 无匹配 —— 该语义现在正负两侧都没有测试。
- 修法：随第 1 节选择，(a) 恢复原断言即等价；(b) 新增 `Vec<MapEntry<char*,int>>` 的 foreach 正例与期望输出，并在 `check-ast.sh` 加一条产物/运行断言。不得只删不加。

---

## 3. 通过：E29-3 只改名，未放宽语义

- diff 仅 `check-ast.sh:5987-5988`：`struct Box_Box_lBox_lint_r_r {` → `struct Box_Box__Box____int {`（含 `{`，仍验定义而非前向声明）。
- 139 夹具与 `prog.expected.out` 未在本提交内（commit stat 无该路径）。
- 实测当前编译器：`Box_int`、`Box_Box__int`、`Box_Box__Box____int`、`Box_Box__Box____Box________int` 四个定义都在，rc=0，运行输出匹配。
- Low（非本次引入）：该断言原本只查 tag 名，不查字段/实例数，因此两种拼写下都检测不到布局回归；如需加强可再加 4 层 tag（现由运行时输出覆盖）。

---

## 4. Medium：`Vec_Vec__int` 与用户 `struct Vec_int` 的实例键完全相同

- 编码链成立：`inst_enc_one` 剥 `struct `（[Symbols.h.ct:1739-1753](file:///Users/samxx/trae-ws/ct-lang/selfhost/ct-ast/frontend/sym/Symbols.h.ct#L1739-L1753)）→ `struct Vec_int` 编成 `Vec__int` → 外层 `Vec_Vec__int`（[Expr.h.ct:1782-1794](file:///Users/samxx/trae-ws/ct-lang/selfhost/ct-ast/frontend/parse/Expr.h.ct#L1782-L1794)、`:1862-1873`）。
- 碰撞：`Vec<Vec_int>`（用户 struct）与 `Vec<Vec<int>>` 的 `(nargs, carg[0])` 都是 `1, "struct Vec_int"`，[ct_inst_add:1564-1571](file:///Users/samxx/trae-ws/ct-lang/selfhost/ct-ast/frontend/sym/Symbols.h.ct#L1564-L1571) 判为同一实例。旧方案是 `Vec_Vec__int` 对 `Vec_Vec_lint_r`，永不合并。
- 实测（`/tmp/p31coll.ct`：`struct Vec_int { int x; };` + `Vec<Vec_int>` + `Vec<Vec<int>>`）：
  - 产物只有一份 `struct Vec_Vec__int`（第 23 行），函数签名 `Vec_Vec__int_from(struct Vec_int *items, int n)`；
  - 但有两处 `struct Vec_int {`（16、19 行），`cc` 报 `redefinition of 'Vec_int'`。
  - 即：今天靠 C 层重定义暴露；合并后元素到底是 `{int x;}` 还是句柄结构取决于 cc 选中哪个定义，跨单元没有任何一致性保证。内层 tag 碰撞是既有的，**外层静默合并是 S20b 新引入的**。
- 修法：实例注册时若生成的 tag 与本单元已声明的 struct 同名则报诊断（或在 `ct_inst_add` 发现 `enc` 相同但 `ctype` 不同时报内部错），并加 `struct Vec_int` + `Vec<int>` 的负例。不要把 `carg` 当纯字符串键。
- Low A（哈希）：条件与算法未变（[Symbols.h.ct:1798-1803](file:///Users/samxx/trae-ws/ct-lang/selfhost/ct-ast/frontend/sym/Symbols.h.ct#L1798-L1803)，仍 `n >= 64` + `%.40s_h%08x`）。新输入只会变短（`struct ` 被剥、`<`/`>`/`,` 的两个字符展开消失），故不会让原本字面量化的名字改走哈希；实测 4 层 `Box` 链 30 字符。仅需注意 `phase33-draft` / `phase35-draft` 里钉的旧拼写，落地时同步（不在本次范围）。
- Low B（陈旧注释与诊断拼写）：[Expr.h.ct:279-283](file:///Users/samxx/trae-ws/ct-lang/selfhost/ct-ast/frontend/parse/Expr.h.ct#L279-L283) 仍写「in source form (`Vec<int>`) … `Vec_Vec_l_int_r`」，与 S20b 后行为不符；`Map` 键诊断（`Expr.h.ct:1853-1860`）对嵌套键会输出 `'struct Vec_int'` 而非 `'Vec<int>'`，现无门禁钉该文案（`check-ast.sh:6227` 只钉 `char`）。

---

## 5. 复核方法与证据

- `git show 35f63fd` 全量 diff；对照 `bd1980c` 建 `/tmp/pre35ctast`，当前树建 `/tmp/r9ctast`（均从仓库根运行）。
- 实测项：被删夹具 pre/post（rc=1 报 `6:5` 冻结文案 / rc=0）；139 产物四个层级 tag；200 产物 `MapEntry_char_p_int`、`MapEntry_char_p_Vec__int`、`MapEntry_char_p_Map__char__p__int` 均有定义且 `_lint_r` 计数 0；碰撞夹具的合并与 cc 重定义。
- 未执行 `bash selfhost/check-all.sh`（未改实现，且主工作区有并行会话）。
