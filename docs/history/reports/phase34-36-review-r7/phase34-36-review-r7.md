# Phase 34 / 36 第六轮（r7）窄范围复核

- 复核对象：`bd1df0a`（`docs/design/phase34-draft.md`、`docs/design/phase36-draft.md`）
- 范围：只验上一轮两处修改是否真落地、是否引入新的“不存在的代码事实”。不重读全文，不评 35/roadmap。
- 方法：读 `bd1df0a` 的卡片文本 → 对照 `selfhost/ct-ast/**` 与 `selfhost/check-ast.sh` 源码 → 在 `/tmp` 用**本轮源码重建的 `ct-ast`（v0.30.0，Build: L0→L1→`selfhost/ct-ast/main.ct`）**实测发射形态。未运行 `bash selfhost/check-all.sh`。
- 工作区约束：`2026-11-11/` 未跟踪目录未提交；未改卡片、未 commit、未动 golden/版本号/门禁。

## 0 条件闭合总表

| 卡片 | 条件 | 结论 | 一句话证据 |
| --- | --- | --- | --- |
| P34 | M-1（TEST-18 钩子可跑 + 脏产物红证） | **闭合（GO 附条件）** | `tparam_residue` 签名/输出与卡片用法一致；脏文件实测输出 `T(1) `、净文件空 |
| P36 | H-1（泛型 Drop 按实例登记） | **未闭合（NO-GO）** | 三个符号都存在且签名对，但链缺 `impl_emit_one` 的 Drop vtable 抑制；post-scan 作用域与“两向回填会漏”的前提都不成立 |
| P36 | H-2（`nm` + 生成 C 断言） | **部分闭合（NO-GO）** | `nm --defined-only` + ` [tT] _?X$` 与 macOS 实测完全一致；但生成 C 的定义行 grep 与“显式泛型 impl”的发射拼写不符 |
| P36 | M-1（`.ct` 源码块 / 生成 C 块分离） | **闭合** | L111–124 源码用 `self`、C 用 `_self`、`void drop()`；L127 明说各自内联 |
| P36 | M-2（内联释放四处统一） | **闭合** | L127/L145/L204/L226 全部“各自内联”，无“共用内部函数”残留 |
| P36 | M-3（S2b 20–40 移入库预算） | **闭合** | L259 delta 说明在，且 240–430 / 240–420 的逐片求和可对上 |

结论先行：**P34 = GO（附 1 Medium + 3 Low）；P36 = NO-GO（2 High + 2 Medium + 1 Low）**。

---

## 1 实测环境与原始证据

1. 编译器：`cc selfhost/l0/ctc.c` → L1（`selfhost/l1/ctc.ct`）→ `/tmp/r7l1`；`/tmp/r7l1 build -I selfhost/ct-ast selfhost/ct-ast/main.ct` → `/tmp/r7ctast`（`ct-ast v0.30.0`）。与 `check-ast.sh:406` 的构建命令一致。
2. 现有 Drop 夹具（`test/archive/cases/22_drop.ct`）经 `/tmp/r7ctast` 发射：

```
static void __attribute__((unused)) Inner_Drop_drop(void *self);      /* 显式 impl（非泛型路径） */
static void __attribute__((unused)) Outer_Drop_drop(void *self);      /* 自动 glue */
static void __attribute__((unused)) Inner_Drop_drop(void *self) {
static void __attribute__((unused)) Outer_Drop_drop(void *self) {
    Inner_Drop_drop(&_self->in);
    if (o) { Outer_Drop_drop(o); free(o); o = 0; }                   /* delete 确实引用 drop */
```

3. 泛型**固有**方法（`impl<T> Box<T> { void f() }`）经同一编译器发射：

```
static __attribute__((unused)) void Box_int_f(void *self) {
```

   ——泛型 impl 走 `impl_emit_method`，属性在**返回类型之前**；与第 2 条的非泛型路径**拼写不同**。这条后面判定 E36-1 时是决定性的。

4. 泛型**trait** impl（`impl<T> Box<T> use Show`）发射：

```
static struct Show_vtbl Box_int_Show_vtable __attribute__((unused)) = {
```

5. 红证复现（`impl<T> Drop for Box<T>`）：`gdrop.ct:2:14: error: unexpected token`（卡片写 `5:14`，行号差异只因夹具行数，错误点一致）。

6. 现状确认：`struct Box<T> { Inner in; } use Drop;` 今天会发射模板级 glue，且**编译失败**：

```
tdrop2.c:23:27: error: incomplete definition of type 'struct Box'
   23 |     Inner_Drop_drop(&_self->in);
```

7. 现状确认：`struct Box<T> { int n; } use Drop;` + `Box<int>` + `delete` 的产物里**没有** `Box_int_Drop_drop`，只有模板级 `Box_Drop_drop` —— `uses_drop` 确实没被复制到实例行。

---

## 2 Phase 34 — M-1 是否真能跑

### 2.1 四个核查点

**（1）`tparam_residue` 的真实形态：对得上。**
`selfhost/check-ast.sh:431-445`：

```sh
# Usage: tparam_residue <product.c> <source.ct>...
tparam_residue() {
    product="$1"; shift
    bodies=$(awk '/__ct[0-9]+\(.*\{/ { inb = 1 } inb { print } inb && /^\}/ { inb = 0 }' "$product")
    for tp in $(sed -n 's/^[A-Za-z_][A-Za-z0-9_ \t*]*<\([A-Za-z_][A-Za-z0-9_]*\)>[[:space:]]*(.*/\1/p' "$@" | sort -u); do
        ...
        if [ "$total" -gt "$tags" ]; then printf '%s(%s) ' "$tp" "$((total - tags))"; fi
    done
}
```

- 参数：`<product.c>` 在前，后面是若干 `<source.ct>`；**不是目录**。
- 输出：stdout，形如 `T(3) U(1) `；**没有返回值语义**（永远退出 0）。
- 因此卡片 L202 的 `tp="$(...)"` + `[ -z "$tp" ]` / `[ -n "$tp" ]` 用法**完全对得上**。
- `fixture_sources` 定义在 `check-ast.sh:427`，返回 `find <dir> -name '*.ct' | sort`；`mod="$work/mod"` 在 `:889`，所以 `"$mod-p34"` 是合法展开（`work/mod-p34`）。

**（2）脏 C 实测：命中，输出 `T(1) `（带尾空格）。**
把 `check-ast.sh:427-445` 原样抽到 `/tmp/p34r7/fn.sh`，用最小夹具实测：

```
dirty -> [T(1) ]
clean -> []
```

脏文件为 `static int twice__ct1(int x) { T(1); return x; }`，源文件含 `T twice<T>(T x)`。结论：卡片“输出含 `T(`（期望 `T(1)`）”**成立**，但实际串是 `T(1) `，**带一个尾空格**；若实现写成精确相等 `[ "$tp" = "T(1)" ]` 会失败，必须用 `case "$tp" in *"T("*)` / `[ -n "$tp" ]` 这类包含判断。

**（3）`test/probes/` 今天不存在；归属应写清。**
`ls test/probes` → `No such file or directory`。仓库里也没有任何脚本遍历它（`grep -rn 'test/probes' selfhost/*.sh test/run.sh` 无命中）。而：
- `docs/design/phase33-draft.md:76`：`test/probes/` 当前不存在，**由 P33 S0 交付**（`p33_check_baseline.sh`）；
- `docs/design/phase33-draft.md:254`：S0 提交 `test/probes/**`；
- `docs/design/phase35-draft.md:204`：S9c 复用 `test/probes/p35_capacity.sh`。

P33 是 P34 的硬前置，所以 P34 落地时目录已存在；P34 S3a 只是“新增一个文件”。但卡片 L179 只写“新增手写 C 脏产物”，**没有写归属**。不阻塞，但应补一句“目录由 P33 S0 创建，P34 S3a 只加文件”。

**（4）反向保证成立，但有两个前提。**
- 正常产物残留 `T(` → `tparam_residue` 非空 → `[ -z ]` 失败：成立（上面 dirty 用例就是非空）。
- 脏产物被清理 → 输出空 → `[ -n ]` 失败：成立（上面 clean 用例就是空）。
- 前提 A：脏文件的函数行必须匹配 `__ct[0-9]+\(.*\{`，否则 awk 不会进入 body 捕获。卡片写“`__ct1` 体内”满足。
- 前提 B：**源列表里必须有一条形如 `X f<T>(...)` 的声明**，否则 `sed` 抽不到任何类型参数名，扫描永远空转。见下面 P34-2。

### 2.2 分级问题（P34）

**P34-2（Medium）`p34_pub_bound` 的扫描在现有抽取式下是空操作。**
L179 要求为 `p34_pub_generic` **和** `p34_pub_bound` 都加 `tparam_residue` 断言。但抽取式 `<\([A-Za-z_][A-Za-z0-9_]*\)>` 只接受 `<T>`，不接受 `<T: Show>`。实测：

```
输入：pub T id<T>(T x) / pub T pick<T: Show>(T a, T b) / struct Box<T> { T n; }
抽取结果：T        （只来自第一行；bound 行与 struct 模板行都不匹配）
```

若 `p34_pub_bound` 里唯一的泛型声明就是 `pick<T: Show>`，则扫描名单为空、`[ -z "$tp" ]` 恒真——这条“覆盖”是假的。
**可验证修法（二选一）**：
1. 在 `p34_pub_bound` 夹具里放一个**无 bound** 的 `pub T id<T>(T)`（哪怕只是被调用一次），使 `T` 进入名单；
2. 或把抽取式扩成允许 `<T[: ...]>`（但这会改 `check-ast.sh:438` 的既有语义，需单独评估，不建议夹带）。
推荐 1。

**P34-1（Low）期望串带尾空格。**
L202 “输出含 `T(`（期望 `T(1)`）”。实测 `T(1) `。修法：断言写 `[ -n "$tp" ]` + `case "$tp" in *"T(1)"*) ;; *) bad ...;; esac`，不要用 `=`。

**P34-3（Low）`test/probes/` 归属未写。**
见 2.1（3）。修法：L179 或 L270 补“`test/probes/` 由 P33 S0 创建；S3a 只新增 `p34_residue_dirty.c`”。

**P34-4（Low）`$mod-p34` 只覆盖一个夹具。**
L202 的 `for f in "$mod-p34"/*.c` 只指一个输出目录，但同段要覆盖 `p34_pub_generic` 与 `p34_pub_bound`。修法：各用各的目录（`$mod-p34g` / `$mod-p34b`），或写成两段独立块。另：若目录为空，glob 退化为字面量，`tparam_residue` 读到不存在的文件会输出空并**静默通过**；应像其他模块块一样先 `&&` 住“构建成功且 `*.c` 非空”。

### 2.3 P34 结论

**GO（附条件）**。M-1 的机制是真的、能跑：函数签名、stdout 语义、`$mod-*` 命名、正反向断言都对得上，脏/净实测均符合预期。需在实现前吸收 P34-2（Medium）与 3 条 Low。

---

## 3 Phase 36

### 3.1 H-1 三个符号逐个核（全部存在，签名对）

| 卡片用到的符号 | 真实位置/签名 | 判定 |
| --- | --- | --- |
| `emit_impls` | 声明 `Emitter.h.ct:171`，定义 `:2177` `int emit_impls(int prog)`；glue 循环在其内部 `:2331-2366` | 存在；“在 emit_impls 生成 glue 之前”是真实位置 |
| `StructDef` 的 `int uses_drop;` | `Symbols.h.ct:221` `pub struct StructDef {`，`:230` `int uses_drop;`；相邻已有 `:231 uses_handback` / `:232 has_handback_impl` | 存在；建议贴着 `has_handback_impl` 放并同步在 `add_struct`（`:834-843`）里清零 |
| `ct_impl_matches(ii, k)` | 声明 `Symbols.h.ct:368` `pub int ct_impl_matches(int ii, int inst);`，定义 `:1648`；**第一参 impl 行，第二参实例行** | 存在，参数顺序与卡片一致 |

补充核实（卡片链上其它环节）：
- `ct_insts(int *n)` 返回 `struct StructInst *`，`:333` 有 `char name[160]` —— `.name` 成立。
- `find_struct(name)`（`:808-815`）按名字线性查 `structs[]`；`inst_emit_one`（`Emitter.h.ct:1392`）已经在用 `find_struct(insts[ii].name)` 并拿到实例行，所以“按实例名查回实例行”成立。
- `N_IMPL` 节点 → `StructImpl` 行的映射是存在的：`Parser.h.ct:2767` 把 `ct_impl_add(...)` 的返回值存进 `nodes[node].num`。卡片写“取其 `StructImpl` 行 `ii`”**没写这个映射**，属于欠说明，不是不存在。

### 3.2 H-1 断在哪（这是本轮 High 的主体）

**P36-H1-a（High）泛型 Drop impl 会在 `impl_emit_one` 里发射一个不存在的 `struct Drop_vtbl`。**
卡片 ③ 要求把 `impl<T> Drop for Box<T>` 注册进 `ct_impls`（否则 `ct_impl_matches(ii,k)` 无从谈起）。但 `emit_struct_impls` → `impl_emit_one`（`Emitter.h.ct:1618-1640`）对 `im[ki].use[0]` 是**无条件**发 vtable 的：

```c
if (im[ki].use[0]) {
    fprintf(self->out, "static struct %s_vtbl %s_%s_vtable __attribute__((unused)) = {\n",
            im[ki].use, ins[ii].name, im[ki].use);
```

`Drop` 是内建，不在 `traits[]`（`Parser.h.ct:2177-2180` 明说它不加入 `use` 列表，`Emitter.h.ct:2194` 也把 `Drop`/`Handback` 当特例），所以会生成 `static struct Drop_vtbl Box_int_Drop_vtable = {...}`，而 `struct Drop_vtbl` 从未定义 → **C 编译期硬错**。实测同路径的 `Show` 版本确实发射 `static struct Show_vtbl Box_int_Show_vtable ...`（见 §1.4）。
**修法**：在 `impl_emit_one` 的 vtable 块加 `if (!strcmp(im[ki].use, "Drop") || !strcmp(im[ki].use, "Handback")) return 0;`（方法体已经发完，只跳过 vtable）；并在 S1a/S2a2 的切片说明里写明这一步与行数。

**P36-H1-b（Medium）post-scan 的作用域只覆盖“当前 unit 的 `nodes[prog]`”，而 glue 循环覆盖全局 `nstructs`。**
`emit_impls(prog)` 在 `:1295` 与 `:1885` 都是**逐 unit** 调用；glue 循环 `for si < self->sym->nstructs` 用的是**单例** `Symbols`（`main.ct:65 symbols_get()`），即 build-wide 全部 struct。后果：在一个不含该 `N_IMPL` 的 unit 里，`has_drop_impl` 没被置位，glue 照样发射 `Box_int_Drop_drop`；而显式 impl 的定义只在 owner unit 发一份（`emit_struct_impls:1659 owned`）。若模板是 `pub`（P34 之后 `lib/std` 正是如此），其他 unit 会同时看到头里的非 static 原型和本地的 static glue 定义 → “static declaration follows non-static” 或语义走错。即便不谈 `pub`，发射顺序也变成“谁先 emit 谁发 glue”，与卡片 L79 的“与解析顺序无关”相矛盾。
**修法（更短且不新增字段）**：glue 循环里直接按实例查全局 `ct_impls()`：

```c
/* has_drop_impl 的等价判定，build-wide，无 unit 作用域 */
int has_g = 0, ij, nij;
struct StructImpl *imj = frontend::sym::ct_impls(&nij);
for (ij = 0; imj && ij < nij; ij++)
    if (!strcmp(imj[ij].use, "Drop")
        && frontend::sym::ct_impl_matches(ij, ct_inst_index_of(si))) { has_g = 1; break; }
```

若仍保留 `has_drop_impl` 字段，post-scan 必须遍历 `ct_impls()`（或所有 `units[*].prog`），**不能**遍历单个 `nodes[prog]`。

**P36-H1-c（Medium）卡片否掉“两向回填”的前提与代码不符。**
L79 写“不能在 `add_struct_inst` 或 `ct_impl_add` 单侧登记……两向回填仍会漏”。但仓库**今天就有两处对称回填**，且都是 build-wide 单例：
- 实例晚于 impl：`Expr.h.ct:1963-1970`（`ct_impls()` 扫一遍，`ct_impl_matches(ii3,k)` 命中就 `adopt_use`）；
- impl 晚于实例：`Parser.h.ct:2770-2779`（`ct_insts()` 扫一遍，命中同样 `ct_impl_matches` 就 `adopt_use`）。

`Drop` 不加入 `use[]`，但完全可以在同样两处改成置 `has_drop_impl = 1`，即可得到与解析顺序无关的登记，且**不需要** emit 期 post-scan。卡片当前的论证基于一个不成立的代码事实，会把实现引向更重且有作用域坑的方案。

**P36-H1-d（Low）字段初始化/位置。**
`add_struct`（`Symbols.h.ct:834-843`）逐个显式清零每个字段；新增 `has_drop_impl` 要在那里补 `= 0`，并建议与 `has_handback_impl` 相邻，而不是插在 `uses_drop` 与 `uses_handback` 之间。

### 3.3 顺序夹具“impl 写在 `Box<int>` 首次使用之后”是否写得出来

**写得出来**，但前提是 S1a 真的把 `for` 形式加进 `parse_impl_inst`。今天 `impl<T> Drop for Box<T>` 在 `for` 处报 `unexpected token`（§1.5），而现有 `parse_impl_inst`（`Parser.h.ct:2748-2756`）只认 `use`，且 `use` 分支要求 `find_trait(use) >= 0`，`Drop` 必然失败——P36 必须在 S1a 里同时处理“`for` 语法”和“`Drop`/`Handback` 内建旁路”，否则夹具连解析都过不去。

只要上述解析到位，顺序就不是问题：`ct_impl_matches` 是在**发射期**对全局 `ct_impls()`/`ct_insts()` 求值的（`emit_struct_impls:1676-1678`），晚出现的 impl 会自动覆盖早已登记的实例；夹具形态可以是：

```ct
struct Box<T> { int n; } use Drop;
int main(void) { Box<int> b; b.n = 1; delete (&b); return 0; }
impl<T> Drop for Box<T> { void drop() { self->n = 0; } }   /* 写在首次使用之后 */
```

不需要改成“另一单元、晚编译”。

### 3.4 H-2 断言核实

**（a）`nm --defined-only` + ` [tT] _?X$`：与 macOS 实测完全一致。**
最小 C（`static`、`__attribute__((unused))`、`-O0 -c`）实测：

```
000000000000003c t _Box_int_Drop_drop
000000000000005c t _Box_Str_Drop_drop
grep -cE ' [tT] _?Box_int_Drop_drop$' -> 1
grep -cE ' [tT] _?Box_Str_Drop_drop$' -> 1
grep -cE ' [tT] _?Box_Drop_drop$'     -> 0
```

macOS 的 `_` 前缀、静态符号小写 `t`、` [tT]` 前的空格都吻合，`--defined-only` 不加 `-g` 也是对的（`-g` 看不到本地 `t`）。

**（b）`delete` 一次是否“足以保证 glue 被发射”：不仅要，而且必须。**
实测：一个**未被引用**的 `static void Box_Drop_drop(...)` 在 `-O0` 下也会被 clang 丢弃，`nm` 里没有；被 `main` 引用后才出现。所以卡片“夹具 `delete` 一次（保证 glue 被发射、不被优化掉）”的动机是正确的。

**P36-H2-a（High）生成 C 的定义行 grep 与“显式泛型 impl”的发射拼写不符，E36-1 按现文无法通过。**
E36-1（L219）夹具明确含 `impl<T> Drop for Box<T>`；此时 `Box_int_Drop_drop` 来自泛型显式 impl（`impl_emit_method`），实测拼写是：

```
static __attribute__((unused)) void Box_int_Drop_drop(void *self) {
```

而卡片的 grep 是：

```
grep -cE '^static void (__attribute__\(\(unused\)\) )?Box_int_Drop_drop\(void \*self\) \{' == 1
```

两个可选分支都要求 `static void ...`；显式泛型路径是 `static <attr> void ...`，**计数为 0**（glue 又被 `has_drop_impl` 跳掉，也不会补上）。所以这条断言必挂。
**修法（择一）**：
1. 改成同时接受两种顺序：`^static (void __attribute__\(\(unused\)\) |__attribute__\(\(unused\)\) void )?Box_int_Drop_drop\(void \*self\) \{`；
2. 或把 E36-1 的夹具改成**无显式 impl**（只有 `use Drop`），让定义来自 glue（此时卡片原 grep 正确），把“有显式 impl → 无第二份”完全交给 E36-2。

**P36-H2-b（Medium）“模板 `Box_Drop_drop` 在 `nm` 中 0 条”是空转断言。**
模板 glue 是 `static` 且无人引用，clang 会直接丢弃（实测 `Box_Drop_drop` 在 nm 中为 0，即使我确实在 C 里写了它）。所以 ② 的 `is_template` 跳过**无论是否落地**，这条 `nm` 断言都恒真，无法证明 ② 生效。
**修法**：改成对生成 C 计数：`grep -cE '^static void __attribute__\(\(unused\)\) Box_Drop_drop\(void \*self\) \{' == 0`（必要时把 `static <attr> void` 变体一并计入）。

**P36-H2-c（Low）`Box_Str_Drop_drop` 的基线表述。**
今天 `lib/std` 没有 `Str`（§2.2 也这么写），`Box_Str_Drop_drop` 只可能在 P36 落地后出现；E36-1 的红证列写“当前 `5:14: unexpected token`”对“泛型 Drop 语法”成立，但对 `Box_Str` 这一半应补“P36 落地后”。

### 3.5 M-1 / M-2 / M-3

- **M-1 闭合。** L111–122 是 `.ct` 源码块（`void drop() { free(self->data); ... }`），L124 单独给生成 C（`_self`），L127 再次点明源码 `self` / 生成 C `_self`。实测非泛型 Drop 生成体确实是 `_self->...`（§1.2）。不再混写。
- **M-2 闭合。** L127、L145、L204、L226 四处统一为“各自内联”；`grep` 全文没有“共用/内部函数/helper”残留。
- **M-3 闭合。** L259 明写“S2b 的 20–40 行库侧工作移入库预算，S2a 拆成 60–100+50–90，240–430/240–420 是同一批工作的重新分类”。逐片求和核对：编译器 60+40+60+50+30=240 / 100+80+100+90+60=430；库 20+50+40+90+20+20=240 / 40+80+70+150+40+40=420，与 §6 表一致。

### 3.6 P36 结论

**NO-GO。** 三个符号全部存在、签名正确（这一点比上一轮好），但 H-1 的落地链仍有两处会直接产出坏代码/坏测试的缺口：

1. **High** — `impl_emit_one` 对 `use == "Drop"` 无条件发 `struct Drop_vtbl`，生成 C 无法编译（P36-H1-a）。
2. **High** — E36-1 的生成 C 定义行 grep 与显式泛型 impl 的真实拼写不符，断言必挂（P36-H2-a）。
3. **Medium** — post-scan 作用域是单 unit，与全局 glue 循环不匹配，“与解析顺序无关”在跨单元不成立（P36-H1-b）。
4. **Medium** — “两向回填仍会漏”的论据与 `Expr.h.ct:1963-1970` / `Parser.h.ct:2770-2779` 的既有实现冲突（P36-H1-c）。
5. **Medium** — 模板 `Box_Drop_drop` 的 `nm` 断言恒真，无法验证 ②（P36-H2-b）。
6. **Low** — `has_drop_impl` 的 `add_struct` 清零与字段位置（P36-H1-d）；`Box_Str` 基线措辞（P36-H2-c）。

修法都不需要改判据、golden 或版本号；1/3/4 可以合并成一次 S2a2 的返工：优先采用“glue 循环里直接对 `ct_impls()` 求值”的方案，既消掉 `has_drop_impl` 的跨 unit 坑，也免掉 post-scan；同时补 `impl_emit_one` 的 Drop/Handback vtable 跳过。

---

## 4 终态

- **Phase 34：GO（附条件）** — M-1 真落地、可跑；实现前吸收 P34-2（Medium，bound 夹具扫描空转）与 P34-1/3/4（Low）。
- **Phase 36：NO-GO** — 符号层已对上，但 H-1 缺 `struct Drop_vtbl` 抑制、post-scan 作用域不成立，H-2 的生成 C grep 与显式 impl 拼写不符；需按 §3.6 的 1–4 返工后再评。
