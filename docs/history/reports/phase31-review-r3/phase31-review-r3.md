# Phase 31 立项卡第三轮独立评审

- **评审对象**：`docs/history/design/phase31.md`（提交 `37b710a`，980 行；工作区与 `37b710a` 逐字节一致，`git diff 37b710a -- docs/history/design/phase31.md` 为空）
- **评审范围**：仅这张卡及其与 `docs/roadmap.md` Phase 31 行的对应关系。Phase 32–36 卡片不在范围内，未评审、未改动。
- **评审性质**：只读。未修改卡片、golden、版本号、门禁脚本；未执行 `bash selfhost/check-all.sh`；所有实测产物写在 `/tmp/p31base`、`/tmp/p31bd`，未写入仓库。
- **工作区纪律**：`docs/design/phase32-draft.md` 的他人在途改动未触碰、未 `git add`、未提交。
- **结论：NO-GO**（5 High / 5 Medium / 8 Low）

> 本轮核心任务不是重读全文找新问题，而是把第二轮五条 High 逐条压到代码事实上验证。结论是：**H-A、H-B 的代码事实成立，H-C、H-D、H-E 的文字修订到位**；但压到代码后发现三类新问题——基线提交本身不绿、链式访问方案会发射非法 C、E31-28 与 L31-21 直接互斥——外加判据计数公式与扫描器实际行为不符。

---

## 1 五条 High 的逐条核实

### 1.1 H-A 句柄拷贝 UAF 的根治 —— 事实成立，但落点表与切片顺序有缺口

| 核查点 | 卡片位置 | 代码事实 | 判定 |
| --- | --- | --- | --- |
| `ct_buf` 新增 `void *data` | §3.2.1 第 186–191 行、D31-24 第 595 行、B31-16 第 702 行 | 基线 `lib/std/Vec.h.ct:28-32` 的 `ct_buf` 只有 `refs/len/cap`，确无 `data`，卡片描述的改造方向正确 | ✅ 成立 |
| 句柄只剩 `h` | §3.2.1 第 192–193 行 | 基线 `Vec.h.ct:34-37`、`50-53` 确为 `{ struct ct_buf *h; T *data; }` / `{ .h; .entries; }` | ✅ 成立 |
| `retain` 只复制 `h` | §3.2.1 第 196 行、§3.2.2 第 237 行 | 基线 `Vec.h.ct:152-159` 复制 `r.data = self->data;`，`Map.h` 同段 `341-348` 复制 `r.entries` | ✅ 成立（UAF 前提真实） |
| `push`/`put` 经 `h->data` 扩容 | §3.2.2 第 234 行、§3.2.3 第 247 行 | 基线 `Vec.h.ct:119-131`、`189-224`、`263-295` 全部 `realloc(self->data/self->entries)` | ✅ 成立 |
| `get`/`len` 经 `h->data` | §3.2.2 第 232 行、§3.2.3 第 249/251 行 | `len` 只读 `h->len`；`get`/`entry` 读 `self->data`/`self->entries`，需改 | ⚠️ 部分：见 M1 |
| 卡内是否残留 `self->data` 设计路径 | 全文 | 仅第 181 行作为“基线现状”描述出现；`grep -n "self->data\|self->entries\|v\.data\|r\.data"` 无设计路径残留 | ✅ 无残留 |
| S27 的 100–200 行是否够 | §6 第 740 行 | `lib/std/Vec.h.ct` 内 `self->data`/`self->entries`/`v.data`/`r.data` 访问点实测 41 处（`grep -c`），加 12 处类型化局部量与结构体改动约 55–70 净行；100–200 行可信 | ✅ 规模可信，⚠️ 顺序有问题（M5） |
| E31-30 能否观测“兄弟句柄扩容后仍有效” | §7 第 784 行、§13.8 第 980 行 | 见 §1.1.1 实测：三个夹具在基线**编译即红**（`{1}` 不被 O4 支持），断言的“绿”依赖释放块里残留的旧值；纯 `rc` 断言依赖分配器是否原地扩展 | ⚠️ M3 |

**额外实证（确认 H-A 前提不是纸上推演）**：在基线 `1564938` 上用 range 初值绕开 O4（`Vec<int> a = 4..5 { $ };`），`Vec<int> b = a.retain(); a.push(2); b.get(0);`

```
$ gcc -std=c99 probe_alias2.c -o probe_alias2 && ./probe_alias2
2 4
rc=1
$ gcc -std=c99 -fsanitize=address probe_alias2.c -o probe_alias2_asan && ./probe_alias2_asan
==57250==ERROR: AddressSanitizer: heap-use-after-free ...
    #0 ... in Vec_int_get+0x1d8
```

UAF 确实存在，D31-24 的根治方向正确。但注意：**卡片 E31-30 里的夹具写成 `Vec<int> a = {1};`，基线根本不接受花括号（O4 未落地），所以“基线 ASAN 报 heap-use-after-free”这句话用它自己的夹具复现不出来**；基线上复现 UAF 必须用 range 初值（如上）。见 M3。

同类：§3.2.1 第 181 行写的复现片段 `Vec<int> b = a.retain(); a.push(1); b.get(0);` 里 `a` 完全没有初始化，基线会先段错误（卡片第 112 行自己记了这一点），同样不是可复现的 ASAN 证据。

### 1.1.1 `Vec.h.ct` 方法落点表的两处缺口（M1）

`Vec` 表（§3.2.2 第 231–238 行）与 `Map` 表（§3.2.3 第 247–255 行）：

- `Map::retain`（`Vec.h.ct:341-348`）——**H-A 的核心方法，表里没有这一行**；它现在正是 `r.entries = self->entries;` 的复制源。
- `Map::len`（`Vec.h.ct:253-257`）、`Vec::len`（`Vec.h.ct:86-90`）——未列；虽然只读 `h->len` 不需改，但读者会以为“未列=已覆盖”。
- `Vec::pop` 标为“**不改**”（第 235 行），但 `pop` 体内 `return self->data[self->h->len];`（`Vec.h.ct:142`）在 D31-24 后必须改成 `h->data`。这是“残留直接读写 `self->data` 的路径”里唯一一处被卡片判成不改的地方。

修法（可验证）：§3.2.2 增加 `len`（不改）与订正 `pop`（经 `h->data` 读）；§3.2.3 增加 `retain`（只复制 `h`、递增 `refs`）与 `len`（不改）两行，并在表下注明“S27 逐方法替换，共 41 处访问点”。

### 1.2 H-B OOM 处理 —— 契约干净，两处表述需收紧

- `Vec::from`：空源/`n <= 0` 分配非零 header 且失败 `abort()`；header 失败 `abort()`；data 失败 `abort()`（第 412–436 行）。`grep -n "h = 0"` 显示 `v.h = 0;` 只作为初始化出现，失败路径无“返回 `h == 0`”。✅
- `Map::from`：header 失败 `abort()`，扩容失败 `return m`（部分表，`h` 有效）（第 506–545 行）。✅
- `Vec::push` / `Map::put`：header 失败 `abort()`，扩容失败 `return 0`（第 441–454 行）。✅
- 无“静默忽略”路径；`k == 0` 跳过是既有 `put` 规则（`Vec.h.ct:193`），不算 OOM。✅

两处问题：

1. **E31-29 的产物断言自相矛盾（M2）**：第 783 行要求“产物断言这些分支**不出现** `free(...); ...h = 0;`”，但卡片第 422 行要求 `from` 函数体第一句就是 `v.h = 0;`。按字面实现必然把合法初始化也判红。修法：把断言写成“`Vec_*_from` 中每个 `malloc(sizeof(struct ct_buf))` 后紧跟 `if (... == 0) abort();`，且 `from` 体内不存在 `free(` 调用；`Vec_*_push`/`Map_*_put` 的 header 分支同形”，避开 `h = 0` 字样。
2. **自举链一致性未说明（L1）**：用户点名核查“`abort()` 在 `l1`/`l2`/`ct-ast` 下行为一致”。卡片未写。实测风险为零：`grep -rn "Vec.h.ct\|lib/std" selfhost/l1/ctc.ct selfhost/l2/*.ct` 无命中（冻结层不消费该单元），且基线 `Vec.h.ct:169` 已经直接调用 `abort()` 且门禁全绿。修法：§3.2.1 加一句“`lib/std` 仅由 ct-ast 预解析；`abort` 为 libc 直接调用，基线 `Vec.h.ct:169` 已在用”。

### 1.3 H-C E31-9 的 19 条删除清单 —— 与 `check-ast.sh` 逐行一致

拿 `selfhost/check-ast.sh` 实际内容核对（`grep -n` 原始输出）：

- 15 条下标：`6036 6037 6044 6045 6046 6047 6050 6051 6052 6053 6054 6057 6058 6059 6062` —— 与卡片第 361 行**完全一致**，无多删、无漏删。
- 6038 `map_brace_init`、6040 `container_iface`、5759 `container_element`、5760 `container_element_map` —— 一致（第 362–365 行）。
- 保留 6039 `generic_impl_missing_method`、6041 `container_vptr_struct`、5753 `foreach_container_element` —— 三条仍在位，且都不是本相推翻的对象。✅
- `grep -n "not subscriptable"` 在 `check-ast.sh` 中只有上述 15 行命中，没有额外遗漏。✅
- `test/ast/errors/` 下对应 19 个文件均在位，`test/ast` 现有编号最大 `164_into_index`，`165–180`、`181–198` 无冲突。✅

**但计数公式错（H4）**：见 §2.1。

### 1.4 H-D `empty_row` 的类型 —— 已改为 `Vec<int>`，无混用

- S20 第 733 行：`Vec<Vec<int>>={empty_row}`；
- E31-28 第 782 行：`Vec<int> empty_row = {};`。

两处自洽（外层是 `Vec<Vec<int>>`、元素是 `Vec<int>`），全文 `empty_row` 只出现这两次，无 `Vec<...>` 混用。✅

但 E31-28 第 4 例与 L31-21/D31-15 互斥（H3），见 §2.2。

### 1.5 H-E 批准人 —— 已改成“需求提出方授权”，但残留两处“仲裁裁定”

已改到位：§1.4 第 52 行、§3.3.4 第 357 行、D31-23 第 594 行、§13.2 第 974 行均写“需求提出方于 2026-11-11 授权本项目全权裁定（含跨相判据变更）”，第 52 行还明确“不以评审方代替判据属主签字”。✅

残留：B31-12 第 677 行、B31-13 第 683 行仍写“（采用，**仲裁裁定**）”，未具名、不可追溯。修法：统一改为“（用户 2026-11-11 裁定）”。（L5）

---

## 2 其他必查项

### 2.1 基线与判据计数（两个 High）

#### H1 — 钉死的基线提交 `1564938` 不是绿基线

§2.1（第 71–79 行）声称“在 `HEAD 1564938` 的干净工作树上实测，`check-ast 1073 passed / 0 failed`、`test/run 141 passed / 0 failed`”，E31-15（第 769 行）与 §13.1（第 973 行）把 `baseline: 1564938 (v0.30.0)` 写进 T-7 红证要求。实测：**该提交上 golden 与编译器 banner 不同步**。

`1564938` 把版本号 bump 到 `v0.30.0`（只改了五处版本常量），而 50 个 `test/cases/*.expected.*` 与 `examples/tour/17_cli/version/expected.out` 直到**其后的** `bd91bfe test(release): regenerate the goldens for v0.30.0` 才重生成。证据：

```
$ git diff --name-only 1564938..HEAD | sed 's|/[^/]*$||' | sort | uniq -c
     50 test/cases
      2 test/modules/hdr
      ...
$ git diff 1564938..HEAD -- test/cases/01_trait_basic.expected.c
-/* Generated by ct v0.26.4 from test/cases/01_trait_basic.ct ...
+/* Generated by ct v0.30.0 from test/cases/01_trait_basic.ct ...
```

在 `1564938` 的干净副本（`git archive` 解到 `/tmp/p31base`）上实际编译：

```
$ gcc -O2 -std=c99 selfhost/l0/ctc.c -o ctc && ./ctc test/cases/01_trait_basic.ct -o x.c
$ diff -u test/cases/01_trait_basic.expected.c x.c
-/* Generated by ct v0.26.4 ...
+/* Generated by ct v0.30.0 ...
```

`test/run.sh:97-136` 的 golden 比对是裸 `diff -u`（无版本归一化）→ **gate 1 在该提交上必红**；`check-ast.sh:5247-5260` 的 L0 seed 段同样裸 `diff -q`（归一化只发生在 `check-ast.sh:6343` 的 module 段）→ **check-ast 至少 1 failed**。因此“1073 passed / 0 failed”“141 passed / 0 failed”与所钉提交对不上（这两组数更像是 `bd91bfe` 之后测的，却记到了 `1564938` 头上）。

同法验证 `bd91bfe` 是可用的绿基线：

```
$ (在 /tmp/p31bd 的 bd91bfe 副本上) ./ctc test/cases/01_trait_basic.ct -o x.c && diff -q .../expected.c x.c
bd91bfe golden OK
```

修法（可验证）：把 §2.1 基线、E31-15 与 §13.1 的 `baseline:` 统一改钉 `bd91bfe`（或实现提交的父提交），在该提交上重跑四道门禁并贴原始输出；若坚持 `1564938`，必须在 §2.1 明确“该提交上 gate 1 与 L0 seed 因版本漂移为红”，且红证不得引用它。

#### H4 — E31-15 的计数公式漏掉自动负例扫描

E31-15（第 769 行）把落地后的断言数写成 ``1073 − 19 + 19 + 新增负例``。但 `check-ast.sh:3018-3033` 对 `test/ast/errors/*.ct` **每个文件产出一条 `ok "$b (rejected with a positioned diagnostic)"`**：

```
3018: echo "== negative cases (test/ast/errors/*.ct) =="
3022: for f in test/ast/errors/*.ct; do
3030:     ok "$b (rejected with a positioned diagnostic)"
```

那 19 个夹具迁到 `test/ast/165–180`、`196–198` 后，除了删掉 19 条显式 `p29_neg`/`p29_diag`，还会**再丢 19 条自动扫描计数**（`test/ast/errors` 现有 219 个 `.ct` 文件）。新增 19 个正例目录由 `check-ast.sh:502` 的 `for d in test/ast/*/` 各补 1 条。正确的对账式是：

```
1073 − 19（显式断言） − 19（自动扫描） + 19（新正例目录） + 新增负例 = 1054 + 新增负例
```

卡片第 367 行已经知道自动扫描存在（“因文件已移走自然不再覆盖它们”），但公式没把它算进去。修法：按上式改写 E31-15，并在收口记录里分别给出“显式断言数 / 自动扫描文件数 / 目录数”三项实测值。

### 2.2 链式访问：会发射非法 C（High H2）

§3.3.1 第 320–321 行写：

> 还需要在发射器接收者白名单里加入 `N_MCALL`……产物是嵌套 C 调用 `Vec_int_len(Vec_int_get(g, 0))`。
> 临时接收者：……`N_MCALL` 结果直接作为嵌套调用的实参，**不额外落临时**。

代码事实相反。固有方法 `aux == 9`（`.` 接收者）在发射时**无条件写 `&`**：

```
$ sed -n '3909,3935p' selfhost/ct-ast/backend/emit/Emitter.h.ct
if (self->arena->nodes[n].aux == 9 || self->arena->nodes[n].aux == 10) {
    ...
    fprintf(self->out, "%s_%s(", structs[si].name, text2);
    if (self->arena->nodes[n].aux == 9) fputs("&", self->out);     /* ← 3925 */
    emit_expr(a) ...
```

而“把调用结果落成临时”的机制只认**自由函数调用**根：`hoist_scan` 在 `Emitter.h.ct:1755` 判 `root->kind == N_CALL`，`N_MCALL` 不在其中；`emit_hoists`（`1781-1793`）还用 `find_func(...)->ret` 取临时类型，对 `N_MCALL` 拿不到。于是按卡片方案：

- `g.get(0).len()` → `Vec_int_len(&Vec_int_get(&g, 0))` —— 对函数返回值取址，非法 C；
- `g[i][j]` → `Vec_int_get(&Vec_int_get(&g, 0), j)` —— 同上；
- `b.mv()[0]` 同理（`b.mv()` 是固有方法）。
- 值派发的 trait 调用也取址：`Emitter.h.ct:3992-3996` 的 `else` 分支输出 `....__<trait>_vptr-><m>(&` 接收者 `)`，所以 `v.get(0).show()`（`Vec<Show>` 的典型用法）同样会把 `&` 加到 `Vec_Show_get(...)` 上。

也就是说，只加白名单（3965-3968）不够，**必须把 `N_MCALL` 接收者材料化成 `__ct_tmpN` 再取址**；卡片偏偏写“不额外落临时”，且产物示例不带 `&`，与现状发射器不一致。

修法（可验证）：
1. `hoist_scan` 的根判定从“仅 `N_CALL`”扩到“`N_CALL` 或 `N_MCALL`（aux 9/10）”；`emit_hoists` 的类型来源改为 `static_ctype(接收者节点)`，不再依赖 `find_func`；
2. §3.3.1 的产物文本改成 `struct Vec_int __ct_tmp0 = Vec_int_get(&g, 0); Vec_int_len(&__ct_tmp0)`；`g[i][j]` 同形；
3. E31-24 增加产物断言：链式夹具产物中**不出现** `&Vec_`/`&Map_` 紧贴调用的形态，且出现 `__ct_tmp`；否则这条判据在 `cc` 之前没有守卫。

### 2.3 E31-28 第 4 例与 L31-21 互斥（High H3）

- D31-15（第 586 行）与 L31-21（第 814 行）规定：有生命周期元素的表项若是**拥有型临时**（`mk()`、`{}`、`from`、`retain`、`pop`）必须具名，否则硬错 L31-21。
- E31-28（第 782 行）第 4 例却要求 `Vec<Vec<int>> g2 = {outer.get(0), outer.pop()};` 编译运行 `rc=0`。

`outer.pop()` 正是 D31-15 点名的拥有型临时，`Vec<Vec<int>>` 的花括号表项又是“有生命周期元素”，按卡片自己的规则这里必须报 L31-21。两条判据不可能同时绿。

裁定：**规则对、夹具错**。修法：把第 4 例改成先绑具名局部再入场，验证点不变：

```c
Vec<Vec<int>> outer = {};
Vec<int> z1 = outer.get(0);        /* 借用，越界零值 */
Vec<int> z2 = outer.pop();         /* 拥有，但为零句柄，不单独 release */
Vec<Vec<int>> g2 = {z1, z2};
g2.release();
outer.release();
```

（`from` 对零句柄 retain 是 no-op、级联 release 有守卫，仍然验证“零句柄入容器后级联不 abort”。）

### 2.4 估算与切片（High H5）

求和本身**完全正确**：实现 S1、S2、S4–S11、S13、S14、S16、S19、S21、S23、S27 逐项相加 = 1,595–2,750；夹具 S3、S12、S15、S17、S18、S20、S22、S24、S26、S28 = 530–920；文档 S25 = 280–470；合计 2,405–4,140，与 §10.2 第 890–892 行逐字一致。✅

但**单片上限不满足 ≤150 行**（按区间上限计 10 片超限，其中 7 片 ≥200）：

| 切片 | 估行（上限） | 超出量 |
| --- | --- | --- |
| S5 | 140–220 | +70 |
| S11 | 150–250 | +100 |
| S13 | 100–160 | +10 |
| S14 | 110–180 | +30 |
| S16 | 150–260 | +110 |
| S21 | 200–400 | +250 |
| S23 | 140–220 | +70 |
| S25 | 280–470 | +320 |
| S26 | 110–180 | +30 |
| S27 | 100–200 | +50 |

卡片 §6 结尾（第 745 行）与 §13.3（第 975 行）用的是“净增**尽量** ≤150 行”，与用户已裁定的“单切片上限 ≤150 行、超量必须拆分”不一致。修法：至少把 S21 拆成“S21a 发射器接收者材料化 + 白名单”与“S21b 二级下标重写 + 临时接收者”，S11、S16、S23、S25、S27 各拆两片；拆分后 §10.2 的总计保持不变（仍 2,405–4,140），只增加行。

### 2.5 代码锚点核对

| 锚点 | 实测 | 判定 |
| --- | --- | --- |
| `Expr.h.ct:1905-1908`（L29-11 守卫） | 守卫在 1904–1908，`fail` 在 1907–1908 | ✅ 落在正确代码上 |
| `Expr.h.ct:1912-1915`（L29-13 守卫） | 条件 1911–1913、`fail` 1914–1915 | ✅ |
| `Expr.h.ct:1976-2004`（`inst_register_nested`，深度 4） | 函数起 1976，`if (depth > 4) return 0;` 在 1987 | ✅ |
| `Expr.h.ct:3230-3252`（`static_ctype` 的 `N_MCALL`） | `case N_MCALL` 3231，块止于 3252 | ✅ |
| `Expr.h.ct:3253-3254`（`default: return 0;`） | 一致 | ✅ |
| `Expr.h.ct:3261-3273`（`container_index_check`） | 函数 3261–3274 | ✅ |
| `Expr.h.ct:3278-3286`（`container_init_check`） | 注释 3276–3278，函数体 3279+，两条 `fail` 在 3281–3286 | ✅ 覆盖 |
| `Expr.h.ct:4482-4495`（自由函数实参装箱） | `iface_ref_type` / `maybe_box` 循环 4484–4496 | ✅ |
| `Expr.h.ct:3514-3520`（固有方法只做 arity） | `arity_check` 3517–3520 | ✅ |
| `Emitter.h.ct:3965-3968`（接收者白名单） | 一致（但它是 **trait 派发**分支的，固有方法分支 3909 无白名单） | ✅ 行号对，⚠️ 语义归属需补（见 H2） |
| `Emitter.h.ct:1666-1706`（`lib/std` 单元发射实例方法） | `via_hdr` / `impl_emit_method` 循环 | ✅ |
| `Symbols.h.ct:1659-1687`（`ct_impl_matches`） | 函数实际 1648–1678，1680 起已是 `ct_is_container_type` | ⚠️ 漂移（L2） |
| `Vec.h.ct` 全部 18 个锚点 | 61/93/102/109/136/146/152/164/192/227/236/263/299/311/327/333/341/350/68 逐一核对 | ✅ 全对 |
| `check-ast.sh` 19 行 | 见 §1.3 | ✅ |
| `Stmt.h.ct:2180-2250`、`2201-2202` | range 初值入口与 1024 上限均在位 | ✅ |
| `Parser.h.ct:1997` | `declare_const(mname, cname, nsbuf, 0)` 正在 1997 | ✅ |
| roadmap 英文 Phase 31 行 `#L1019` | 实际 1024（中文行 46 ✅） | ⚠️ 漂移（L3） |

### 2.6 是否把“不存在的设施”当既有能力

- `CtInst.owner`、`StructTmpl.owner`、`Trait.path`：`Symbols.h.ct:343 / 327 / 328` 均在，✅。
- `__ct_recv`、`MAX_HOISTS`、`inst_register_nested`、`container_vptr_type`、`ct_is_container_type`、`ct check`（`tool/driver/Driver.h.ct:172-173`）、`examples/*/*.ct` glob（`test/run.sh:193`）、`test/modules/p29_builtin_std` 均存在，✅。
- `test/ast` 的 `p03/p04_iface_array_elem_*`：**不在 `test/ast`**，而是 `test/acceptance/run.sh:197/207` 的探针（`BASELINE` 列表第 92 行）。位置写错（L4），能力本身存在。
- “原有自动负例扫描”确实存在（`check-ast.sh:3018-3033`），✅ —— 但正因为存在，H4 的公式才错。
- “`check-sanitizers.sh` 既有 10 项失败”（第 697、786、976 行）：脚本内只有 `ASAN_OPTIONS="detect_leaks=0"`（第 34 行）可核实，未找到任何“10 项”清单或锚点；该数字不可复现（L6）。
- `detect_leaks=0` 的说法核实为真 ✅。
- §3.2.1 第 202 行与 §13.2 第 974 行要求“`ct_buf` 布局变动导致的 golden 文本同步”：实测 `grep -rl "struct ct_buf" test/` = **0 个文件**，`test/ast/142_vec_api` 只有 `prog.ct` + `prog.expected.out`。这条要求是空转（L8）。

### 2.7 roadmap 与卡片的一致性（Medium M4）

`docs/roadmap.md:46`（中）与 `:1024`（英）当前写：

- `D31-1–D31-17`、`E31-1–E31-23`、`L31-1–L31-21`。

卡片已是 `D31-1–D31-24`、`E31-1–E31-30`、`L31-1–L31-23`。§1.5 第 63 行与 §12 第 963 行**只承诺同步 D31 编号**，没提 E/L 两个区间。这是“文档数字漂移”红线里最容易漏的一项。

修法：把 §1.5 与 §12 的落地清单写成三条（`E31-23→30`、`L31-21→23`、`D31-17→24`），并在收口时用 `grep -n "Phase 31 |" docs/roadmap.md` 贴原始输出。

### 2.8 其他

- **S27 的排序（M5）**：S5–S7 落在 S27 之前，三者都要写 `lib/std` 的方法体；S27 再把同一批 41 处 `self->data/self->entries` 迁移到 `h->data`，等于同一批访问点改两遍，E31-8/E31-27 的产物断言也要重验。修法：把 S27 提到 S5 之前（“先改布局，再落生命周期”），或在 S27 行注明“重写 S5–S7 已落的方法体，重跑其产物断言”。
- **用户协议类型的零值（L7）**：第 223 行只说内置 `Vec_*`/`Map_*` 生成 `if (e->h == 0) return;` 守卫，用户 `Box<T>` 的零值级联无守卫、且“零值语义由该类型自己定义”。E31-7/E31-28 都只覆盖内置容器，`Vec<Box<int>>` 越界 `get` 后再级联 release 的行为没有任何判据。建议在 §3.2.1 明写“用户协议类型的零值必须可安全 release”，并加一条 L 级夹具或在 T31-5 里登记。
- §3.2.4 的 L31-23（借用视图被后续变更失效）只做同 block 线性扫描，与 `Map::get` 返回内部指针的既有语义一致；未发现与 E31-26 冲突。✅

---

## 3 分级问题清单

### High（5）

| 编号 | 位置 | 问题 | 可验证修法 |
| --- | --- | --- | --- |
| **H1** | 卡 §2.1（71–79）、E31-15（769）、§13.1（973） | 基线 `1564938` 上 50 个 `test/cases` golden 仍是 `v0.26.4`，而 banner 已是 `v0.30.0`：`test/run.sh:97-136` 与 `check-ast.sh:5247-5260` 都是裸 diff → 该提交 gate 1 与 L0 seed 必红，“1073/0、141/0”不可复现；`baseline: 1564938` 的 T-7 红证无效 | 改钉 `bd91bfe`（已实测 `bd91bfe golden OK`），在其上重跑四道并贴原始输出；或明确标注 `1564938` 的已知红项并从红证里剔除 |
| **H2** | 卡 §3.3.1（320–322）、D31-18（589）、S21（734）、E31-24（778） | 固有方法 `aux==9` 发射时无条件写 `&`（`Emitter.h.ct:3925`），trait 值派发也写 `&`（`3994`）；而材料化只认 `N_CALL` 根（`1755`）。按卡片“`N_MCALL` 不落临时”会生成 `Vec_int_len(&Vec_int_get(&g,0))`、`&Vec_Show_get(...)` 等非法 C | 把 `N_MCALL` 根纳入 `hoist_scan`，`emit_hoists` 用 `static_ctype` 取临时类型；改 §3.3.1 产物文本为 `__ct_tmp` 形态；E31-24 增产物断言（无 `&Vec_*_`，含 `__ct_tmp`） |
| **H3** | 卡 E31-28（782）vs L31-21（814）、D31-15（586）、§3.4.2（478） | 第 4 例 `{outer.get(0), outer.pop()}` 中 `pop()` 是 L31-21 明确禁止的拥有型临时，判据要求 rc=0 与规则互斥 | 改为具名局部：`Vec<int> z1 = outer.get(0); Vec<int> z2 = outer.pop(); Vec<Vec<int>> g2 = {z1, z2};`，验证点不变 |
| **H4** | 卡 E31-15（769） | 公式 `1073 − 19 + 19 + 新增负例` 漏掉 `test/ast/errors/*.ct` 每文件一条的自动扫描（`check-ast.sh:3018-3033`）；19 个夹具迁出 errors/ 再减 19 | 改为 `1073 − 19 − 19 + 19 + 新增负例`（=1054+新增），收口分别给显式断言数、errors 文件数、正例目录数 |
| **H5** | 卡 §6（712–741）、§10.2（885–892）、§13.3（975） | 按区间上限，10 片超 150 行（S5 220、S11 250、S13 160、S14 180、S16 260、S21 400、S23 220、S25 470、S26 180、S27 200），其中 7 片 ≥200 | 拆分 S21/S11/S16/S23/S25/S27 等；拆分不改变 §10.2 总计 2,405–4,140，只增行号 |

### Medium（5）

| 编号 | 位置 | 问题 | 可验证修法 |
| --- | --- | --- | --- |
| **M1** | 卡 §3.2.2（231–238）、§3.2.3（245–255） | H-A 的关键方法 `Map::retain`（`Vec.h.ct:341`）与两个 `len` 未列入落点表；`Vec::pop` 标“不改”，但其体内 `self->data[...]`（`Vec.h.ct:142`）必须改 | §3.2.2 订正 `pop`、补 `len`；§3.2.3 补 `retain`/`len` 两行，表下注明 41 处访问点由 S27 统一替换 |
| **M2** | 卡 E31-29（783）vs §3.4.1（422、430） | 产物断言“不出现 `free(...); ...h = 0;`”与要求必写的 `v.h = 0;` 初始化自相矛盾 | 断言改写为“每个 `malloc(sizeof(struct ct_buf))` 后紧跟 `== 0 → abort()`，`from` 体内无 `free(`”，避开 `h = 0` 字样 |
| **M3** | 卡 E31-30（784）、§3.2.1（181）、§13.8（980） | 夹具用 `{1}`，基线不接受花括号 → “基线 ASAN 报 UAF”用它自己的夹具复现不出（实测需 range 初值）；纯 `rc` 断言依赖分配器是否原地扩展，被称“硬性回归”但只有人工 ASAN | 红证改用 `Vec<int> a = 4..5 { $ };` 形态（实测已复现 heap-use-after-free）；补产物 grep 硬断言（`struct Vec_int` 只有 `h`；`Vec_int_get` 体内访问 `h->data`） |
| **M4** | 卡 §1.5（63）、§12（963）；`docs/roadmap.md:46`、`:1024` | roadmap 仍写 `E31-1–E31-23`、`L31-1–L31-21`、`D31-1–D31-17`，卡片只承诺同步 D31 | 三条区间同步写进落地清单，收口贴 `grep` 输出 |
| **M5** | 卡 §6 S5–S7（718–720）与 S27（740） | S27 排在生命周期切片之后，同一批 41 处访问点被改两遍，E31-8/E31-27 产物断言需重验 | 把 S27 前置到 S5 之前，或在 S27 行声明“重写 S5–S7 方法体并重跑其断言” |

### Low（8）

| 编号 | 位置 | 问题 | 可验证修法 |
| --- | --- | --- | --- |
| **L1** | 卡 §3.2.1（183–200） | 未说明 `abort()` 在自举链下的一致性（用户点名核查项） | 加一句：`lib/std` 仅由 ct-ast 预解析，`l1/l2` 不消费（实测 grep 无命中），`abort` 为 libc 直调，基线 `Vec.h.ct:169` 已在用 |
| **L2** | 卡 §2.3（118） | `Symbols.h.ct:1659-1687` 实际应为 1648–1678，1680 起是 `ct_is_container_type` | 改为 `Symbols.h.ct:1648-1678` |
| **L3** | 卡 §1.5（56） | roadmap 英文行 `#L1019` 实际在 1024 | 改为 `#L1024` |
| **L4** | 卡 §3.1.1（132） | `test/ast` 的 `p03/p04_iface_array_elem_*` 实际是 `test/acceptance/run.sh:197/207` 的探针 | 改写成 acceptance 探针位置 |
| **L5** | 卡 B31-12（677）、B31-13（683） | 残留“（采用，仲裁裁定）”未具名，与 H-E 口径不一致 | 改为“（用户 2026-11-11 裁定）” |
| **L6** | 卡 B31-15（697）、§7 注（786）、§13.4（976） | “`check-sanitizers.sh` 既有 10 项失败”无脚本内锚点或清单 | 改为一组可复现命令与失败项清单，或指向 issues 条目 |
| **L7** | 卡 §3.2.1（223） | 用户协议类型（`Box<T>`）的零值级联无守卫，契约未写进 language-spec，也无夹具 | 明写“用户协议类型零值必须可安全 release”，或登记 T31-5 并补 L 级负例 |
| **L8** | 卡 §3.2.1（202）、§13.2（974） | 要求“`ct_buf` 布局变动的 golden 文本同步”，实测 `test/` 下 0 个文件含 `struct ct_buf`，该要求空转 | 改为“无 golden 含该布局，S27 不产生 golden diff” |

---

## 4 Battle 裁定（可争论点，自行裁定，不征询）

1. **基线能否继续写 `1564938`**：不能。`test/run.sh` 与 `check-ast.sh` 的 golden 比对都不做版本归一化，实测分歧在第一个字节（`/* Generated by ct v0.26.4` vs `v0.30.0`）。“这个提交是 release 提交所以应该绿”是意图，不是证据；已用 `git archive` + 本地编译给出反证。
2. **E31-28 冲突是改判据还是改规则**：改夹具。L31-21（拥有型临时必须具名）防的是“临时句柄那份引用无人释放”，语义正确；若为迁就 E31-28 放宽，会把 O2 的泄漏口重新打开。
3. **链式访问能否“不落临时”**：不能。`&` 是既有发射器对 `aux==9` 与值派发 trait 调用的固定形态（`Emitter.h.ct:3925`、`3994`），C 不允许对函数返回值取址。这不是“实现时顺手处理”的细节，而是 S21 必须显式包含的切片内容（因此 S21 的 200–400 行估计本身是合理的，只是描述写反了）。
4. **“尽量 ≤150 行”能否豁免上限**：不能。用户已裁定“单切片上限不得超过 150 行、超量必须拆分”；卡片自己把硬约束写成“尽量”，属于自我降级。拆分不改总估算，成本为零。
5. **人工 ASAN 能否被称作“硬性回归”**：不能。ASAN 不进 11 道门禁，`check-sanitizers.sh` 又 `detect_leaks=0`；要么补一条确定性的产物 grep 断言，要么把它改称“人工证据”。当前 §13.8 的“E31-30 的两个 ASAN 夹具是硬性回归”名不副实。

---

## 5 附录：本轮实测命令与关键原始输出

```text
# 1) 基线提交并非绿基线
$ git diff 1564938..HEAD -- test/modules/split/impl_dog.expected.h
-/* Generated by ct v0.26.4 ...
+/* Generated by ct v0.30.0 ...

$ cd /tmp/p31base            # git archive 1564938 | tar -x -C /tmp/p31base
$ gcc -O2 -std=c99 selfhost/l0/ctc.c -o ctc && ./ctc test/cases/01_trait_basic.ct -o x.c
$ diff -u test/cases/01_trait_basic.expected.c x.c
-/* Generated by ct v0.26.4 ...
+/* Generated by ct v0.30.0 ...

# 2) bd91bfe 是可用的绿基线
$ cd /tmp/p31bd              # git archive bd91bfe
$ ./ctc test/cases/01_trait_basic.ct -o x.c && diff -q test/cases/01_trait_basic.expected.c x.c
bd91bfe golden OK

# 3) H-A：句柄拷贝 UAF 在基线上可复现（range 初值绕开 O4）
$ ./ct-ast-base probe_alias2.ct -o probe_alias2.c && gcc -std=c99 probe_alias2.c -o probe_alias2 && ./probe_alias2
2 4
rc=1
$ gcc -std=c99 -fsanitize=address probe_alias2.c -o probe_alias2_asan && ./probe_alias2_asan
==57250==ERROR: AddressSanitizer: heap-use-after-free ... in Vec_int_get+0x1d8

# 4) H-C：19 条断言与 check-ast.sh 逐行一致
$ grep -n "not subscriptable" selfhost/check-ast.sh
6036 6037 6044 6045 6046 6047 6050 6051 6052 6053 6054 6057 6058 6059 6062
$ grep -n "container_element\|map_brace_init\|container_iface\|container_vptr_struct\|generic_impl_missing_method\|foreach_container_element" selfhost/check-ast.sh
5753 5759 5760 6038 6039 6040 6041

# 5) H4：errors 目录逐文件计数
$ sed -n '3018,3033p' selfhost/check-ast.sh
for f in test/ast/errors/*.ct; do ... ok "$b (rejected with a positioned diagnostic)" ...
$ ls test/ast/errors/*.ct | wc -l
219
$ grep -n "for d in test/ast" selfhost/check-ast.sh
502:for d in test/ast/*/; do

# 6) H2：发射器对 aux==9 与值派发 trait 调用写 &
$ sed -n '3925p;3994p' selfhost/ct-ast/backend/emit/Emitter.h.ct
                if (self->arena->nodes[n].aux == 9) fputs("&", self->out);
                fprintf(self->out, ".__%s_vptr->%s(&", low, self->arena->nodes[n].text2);
$ sed -n '1755,1757p' selfhost/ct-ast/backend/emit/Emitter.h.ct
            if (root >= 0 && self->arena->nodes[root].kind == N_CALL
                && !self->arena->nodes[root].text3[0]
                && self->sym->find_func(self->arena->nodes[root].text2) >= 0) {

# 7) 基线 docs 计数（1564938，独立副本）
$ python3 test/docs/check-docs.py
check-docs: OK (1021 relative links in 180 files, v0.30.0, 11 hard gates, 12 phase status, 3 适用版本 header(s))
design window: ok (12/12)
```

> 说明：本轮未运行 `bash selfhost/check-all.sh`（避免与并行会话的文档改动冲突），也未在该仓库工作树内构建任何产物；`ct-ast` 基线与 `bd91bfe` 副本均在 `/tmp` 下独立构建。
