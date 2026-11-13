# Phase 34–36 第五轮复核（`56268e2`）

> 范围：`docs/design/phase34-draft.md`、`phase35-draft.md`、`phase36-draft.md`、`docs/roadmap.md` 第 49–51 行。
> 约束：未跑 `check-all.sh`；未改卡片/golden/版本号/门禁；未 commit；未触碰 `phase32-draft.md` 的未提交改动与 `2026-11-11/` 的其他内容。实测只在 `/tmp` 下用 `/tmp/ct-ast`、`cc`、`nm`、`grep`。
> 结论：**Phase 34 = GO（附 M-1 条件）；Phase 35 = GO；Phase 36 = NO-GO**。

## 0 上轮条件闭合表

| # | 上轮条件 | 状态 | 证据 / 残留 |
| --- | --- | --- | --- |
| 1 | P36 H-1 三件事 ①`uses_drop` 复制 ②跳模板 ③按实例登记 | **部分闭合** | ①② 已写进 L77/L78；③ 只写了字段名 `has_drop_impl` 与检查点 L79，**未写字段声明位置、写入 pass 与顺序**（impl 在实例之后出现时怎么办）。E36-1 的 `nm -g`/grep 断言不可观测（见 H-2）。 |
| 2 | P36 S2b 拆编译器/库，各自 ≤150，相加等于 250–420 / 220–380 | **闭合但总额变动** | 卡内 L253/L258 已改为 **240–430 / 240–420**，逐片求和一致，roadmap 51 已同步；相对旧数有 −10/+10 与 +20/+40 的移动（S2b 重分类），卡片未解释 delta。 |
| 3 | P36 E36-8 `_self->len=-1` 与 §3.2.1 一致、参数统一 `_self` | **部分闭合** | `_self->len=-1` 已加（L227）；但 §3.2.1 的 **`.ct` 源码注释**也写 `_self`（L118），源码体应为 `self`；且“共用内部释放”与“`Str_Drop_drop` 体内含 `free`”二选一没定（见 M-2）。 |
| 4 | P36 L-1/L-2 基线措辞、S4a1/S4a2 ≤150、库求和不变 | **闭合** | L45 已改“历史量级参考…不是判据”；S4a1 50–80、S4a2 40–70（L205–206）；库 240–420 = 20+50+40+90+20+20（L260）。 |
| 5 | P34 M-1 脏夹具/扫描入口/门禁接线 | **部分闭合** | S3a/E34-2a 写了 `p34_residue_dirty` 与“加钩子”（L179/L202），但 `check-ast.sh` 的 modules 段是**逐夹具手写块**（约 L892 起），没有 `for d in test/modules` 循环；`tparam_residue` 只在 532/570 的 `test/ast` 循环调用。脏夹具作为 CT module 也不能可靠构造（见 M-1）。 |
| 6 | P34 E34-2b 从 `check-docs` 摘下、标人工项 | **闭合** | L203：门禁列“人工审查”，正文“**人工审查项，非门禁**”。 |
| 7 | P34 cache `touch -m -t` + `stat -f %m`，两目录不互命中 | **闭合** | L211：`touch -m -t 203001010000 a.h.ct` → `stat -f %m` 断言 → 重建 B；A/B 各用干净 `-o` 目录，`.ctcache` 分离。 |
| 8 | P34 C99 理由改对 | **闭合** | L116 已改为“C99 已删除隐式函数声明，clang `-std=c99` 直接 error，与 `-Werror` 无关”；实测 clang 输出一致。 |
| 9 | P34 `nm -g --defined-only`/`--undefined-only` 主判据、grep 辅助、原型钉死 | **闭合** | L205 主/辅调换；L183 S5b 钉死 `int Counter_get(struct Counter *);`。`Counter_get` 是全局符号（L116），`-g` 适用。 |
| 10 | P34 编号 215–218 全卡同步；无 211–214 残留；228 仍在 | **闭合** | L206–210 全为 215–218；L270 交付 `215–218_*`；grep 无 `211–214` 残留；L59 仍有 `228_pub_generic_fn`。 |
| 11 | P34 L-1/L-2/L-3 | **闭合** | L40 已写“6 = 6 个影响点（language-spec 两处算 1，phase29 三处算 1）”；L50 superseding 块改到 DOC-67 段之后/§2.6 之前；L179–180 拆 S3a/S3b，L239–241 合计 270–450 / 200–360 / 885–1,530，roadmap 49 同步。总额较上轮 +10/+30，属新增脏夹具与文档拆分，无隐藏增量。 |
| 12 | P35 M-1 `chk_assignable` 对 P34 基线成立 | **闭合** | L126：P32 落地后存在，但只服务 `ct check --types`，`ct build` 不调用；P35 自实现。 |
| 13 | P35 M-2 S5c 只 `Emitter.h.ct`、点名 `N_DECL`、无解析期检查并存 | **闭合** | L126 与 L197 一致：`N_ASSIGN`/`N_DECL` 发射分支；`Expr.h.ct` 只承载 AST；`Stmt.h.ct` 不改；明确“不加解析期检查”。 |
| 14 | P35 L-1/L-2/L-3、编号 219–224 全卡同步 | **闭合** | E35-16 L228 已拆 L35-5 两子例；S9c/E35-18 改“第 65 条 trait 行”并打印实际条数（L204/L230）；非法 iface 归 L35-5（L126）；E35-6 L218=`ast/223`、E35-10 L222=`ast/219`/`220`、R35-3 L268=`222`/`223`、交付 L285=`219–224`，无 215–218 残留。 |

---

## 1 Phase 36 — **NO-GO**

### H-1（High）③ 的“按实例登记”没有落到写入点与顺序
**行号**：L79（§3.1.1 ③）、L198（S1a）、L201（S2a2）、L221（E36-2）。  
**事实**：

- `impl<T> Drop for Box<T>` 走 trait impl 路径，`N_IMPL.aux` 指向 `find_struct("Box")` 的**模板行**；`Box_int` 是另一行（`Symbols.h.ct:861-864`，`is_inst=1`）。
- 实例在 `Expr.h.ct:1931` 的 `add_struct_inst` 创建；该函数在 1933–1962 只复制字段与 `use`，不复制 `uses_drop`，也没有任何 Drop impl 登记。
- 模板行在 `Parser.h.ct:2179-2180` 置 `uses_drop=1`；`Emitter.h.ct:2333-2339` 的 glue 循环只查 `uses_drop` 与 `N_IMPL.aux == si`，不跳 `is_template`。
- 因此“实例行置 `has_drop_impl=1`”必须回答：字段加在 `Struct` 的哪里、由哪个 pass 在什么时机置位。若在 `add_struct_inst` 里置位，`impl` 在实例之后解析就会漏；若在 `impl` 解析时置位，已存在的实例会漏。卡片两者都没写。
**可验证修法**：在 `Symbols.h.ct` 的 `Struct` 新增 `int has_drop_impl;`；在 `emit_defs` 生成 glue 前做一次 **post-scan**：遍历 `N_IMPL` 中 `text2=="Drop"` 的节点，对每个 `StructInst` 用 `ct_impl_matches` 判断并置位（与解析顺序无关）；或在 `ct_impl_add` 回填已存在实例 + 在 `add_struct_inst` 检查已注册 impl（两向都覆盖）。S2a2 的说明必须写出这个 pass 的落点，E36-2 增加“impl 写在实例之后”的顺序夹具。

### H-2（High，新引入的代码事实错误）E36-1 的 `nm -g`/grep 断言在真实产物上不可观测
**行号**：L220（E36-1）、L221（E36-2）。  
**事实**（实测，`/tmp`）：

- 现有 Drop glue 的发射形态是 `static void __attribute__((unused)) Box_Drop_drop(void *self);`（前向声明）加同名定义，见 `test/modules/autodrop/prog.expected.c:3/63`。
- 我在 `/tmp` 用一个最小 `impl Drop for Box` 复现：生成 C 中 `grep -c 'Box_Drop_drop'` = **2**（声明 + 定义；有调用时更多）。
- `cc -c` 后 `nm -g --defined-only` 对 `Box_Drop_drop` 计数 = **0**：静态函数是局部符号（`t`），`-g` 看不到；若夹具没有实际 `delete`，函数还可能被优化掉。
**影响**：E36-1 的“grep 与 `nm -g --defined-only` 各恰 1 条”按现状**永远过不了**；这不是判据宽严问题，是断言写错了对象。
**可验证修法**：E36-1 改为 `nm --defined-only` 并匹配 ` [tT] Box_int_Drop_drop`/` [tT] Box_Str_Drop_drop`；grep 只数**定义行**：`grep -cE '^static void (__attribute__\(\(unused\)\) )?Box_int_Drop_drop\(void \*self\) \{' == 1`（原型行以 `);` 结尾，不要混入）；夹具必须 `delete` 一次以保证 glue 被发射。E36-2 把 `Box_*_Drop_drop` 展开成 `Box_int_Drop_drop`/`Box_Str_Drop_drop` 两条具体断言，不要用 glob。

### M-1（Medium）§3.2.1 的 `.ct` 源码体写了 `_self`
**行号**：L118。  
**事实**：仓库现有写法是 `impl Drop for Box { void drop() { … self->n … } }`（`check-ast.sh:4983/5034`、`issues/selfhost/sh28-own-in-braceless-branch.md:28`）；`_self` 是发射器的 C 接收者（`Emitter.h.ct:380`、2342），不是源码标识符。`void drop(void)` 本身可解析（实测 `ct check` rc=0），但源码体写 `_self->data` 会误导夹具作者。  
**可验证修法**：L118 的源码体改为 `self->data`/`self.data`，注释注明“生成 C 中为 `_self->data`”；E36-8 的 grep 保持在**生成 C** 上。`void drop(void)` 与现有 `void drop()` 都可解析，建议统一成仓库既有 `void drop()`，减少无谓差异。

### M-2（Medium）“共用内部释放”与 E36-8 的 `Str_Drop_drop` 体内 `free` 断言冲突
**行号**：L118、L227（E36-8）、L205（S4a1）。  
**事实**：L118/L205 说 `drop` 与 `release` **共用内部释放**；E36-8 却要求 `Str_Drop_drop` **体内**含 `free(_self->data)`。若共用的是一个 `Str_free_fields(struct Str *)` 辅助函数，`free` 在辅助函数里，`Str_Drop_drop` 只调用它，E36-8 会失败。  
**可验证修法**：二选一——A) `drop` 与 `release` 各自内联 `free(self->data); self->data=0; self->len=-1;`，E36-8 的体内断言成立；B) 抽出 `Str_free_fields(struct Str *)`，E36-8 改为“`Str_Drop_drop` 调用 `Str_free_fields`”，并在 `Str_free_fields` 体内断言 `free`/`len=-1`。卡片现在两句话各说一半。

### M-3（Medium）预算总额从 250–420 / 220–380 变为 240–430 / 240–420，delta 未解释
**行号**：L253、L258、L260；roadmap 51。  
**事实**：S2b（60–100）拆成 S2b1 30–60（编译器）+ S2b2 20–40（库）；S2a（90–140）拆成 S2a1 60–100 + S2a2 50–90（110–190）。逐片求和：编译器 240–430 = 60+40+60+50+30 / 100+80+100+90+60；库 240–420 = 20+50+40+90+20+20 / 40+80+70+150+40+40；每片 ≤150，roadmap 51 已同步。数字自洽，但相对旧数并非“不变”。  
**可验证修法**：在 §10 加一句“相对第四轮 250–420/220–380：S2b 的 20–40 行库侧工作移入库预算，S2a 拆成 60–100+50–90；编译器 240–430、库 240–420 是同一批工作的重新分类，不是新增 20–40 行”。若“总和不变”是硬约束，则应把 S2a1/S2a2 的边界调回让编译器仍为 250–420，并同步 roadmap 51。

### L-1（Low）E36-2 的 `Box_*_Drop_drop` 不是可执行的 `nm` 模式
**行号**：L221。`nm` 不做 glob；改为两条 `Box_int_Drop_drop`/`Box_Str_Drop_drop` 的具体断言即可（与 H-2 一并改）。

### Phase 36 已闭合项
① `uses_drop` 复制（L77，字段与函数锚点齐全）；② `if (is_template) continue;`（L78，明确）；E36-8 的 `_self->len=-1` 与 §3.2.1 零状态一致（L227）；基线措辞（L45）；S4a1/S4a2 ≤150 且库求和 240–420（L205–206、L260）；E36-14 的 `225–232` 跳过 `228`（L233）；`228_pub_generic_fn` 仍在 P34 L59。

---

## 2 Phase 34 — **GO（附 M-1 条件）**

### M-1（Medium，残留条件）脏夹具的扫描入口与可构造性
**行号**：L179（S3a）、L202（E34-2a）。  
**事实**：

- `check-ast.sh` 的 modules 段是**逐夹具手写块**（`if "$work/ct-ast" build … test/modules/split/main.ct` 起，约 L892 起），**没有** `for d in test/modules` 循环。
- `tparam_residue` 只在 L532、L570 的 `test/ast` 循环里被调用（L488–497 是自测），modules 段没有调用点。
- E34-2a 说“`test/modules/p34_residue_dirty/` 受控脏夹具（产物故意留一个 `T`）”。一个**正确的编译器**不会在合法 CT 源的产物里留下 `T`；这个脏产物无法用 CT module 可靠构造。现有 TEST-18 的负例是手写 `selftest/dirty.c`。
**可验证修法**：① 在 modules 段为 `p34_pub_generic`/`p34_pub_bound` 的 build 成功后加显式调用：`tp="$(tparam_residue "$out" $(fixture_sources ...))"`，`[ -z "$tp" ]` 才通过；② 脏夹具改为手写 `test/probes/p34_residue_dirty.c`（或复用 `test/probes/.../selftest/dirty.c`），单独调用 `tparam_residue` 并断言**非空**，不要把它放进正常 modules 成功循环。这样“钩子不是空操作”才是可证伪的。

### Low
- E34-2a（L202）仍把 language-spec/gap 的文档改动挂在 `check-ast` 下；文档部分实际由 E34-14 的 `check-docs` 覆盖。建议在 E34-2a 的断言行里注明“文档部分见 S3b/E34-14”，避免误以为 `check-ast` 能验文档。

### Phase 34 已闭合项
M-2（L203 人工审查、非门禁）；M-3（L211 `touch -m -t 203001010000` + `stat -f %m`，两干净 `-o` 目录）；M-4（L116 C99 clang error、与 `-Werror` 无关；实测一致）；M-5（L205 `nm -g --defined-only`/`--undefined-only` 主判据，grep 辅助，L183 钉死原型拼写）；M-6（L206–210 全 215–218、L270 交付、L59 保留 228、无 211–214 残留）；L-1（L40 “6 = 6 个影响点”）；L-2（L50 DOC-67 段之后/§2.6 之前）；L-3（L179–180 S3a/S3b；L239–241 270–450 / 200–360 / 885–1,530；roadmap 49 同步）。

---

## 3 Phase 35 — **GO**

上轮 5 条全部闭合，无新增 High/Medium/Low。

- **M-1**（L126）：已改为“P32 落地后 `chk_assignable` 存在，但只服务 `ct check --types`，`ct build` 不调用；P35 在 `ct build` 自实现 `iface_upcast_ok`/`emit_upcast`”。对 P34 基线成立。
- **M-2**（L126、L197）：`N_ASSIGN` 与 `N_DECL` 两个发射分支都点名；S5c 只列 `Emitter.h.ct`；`Expr.h.ct` 只承载 AST，`Stmt.h.ct` 不改，明确“不加解析期检查”，不存在两种描述并存。
- **L-1**（L228）：E35-16 已拆成“L35-1/3/4/8 同文案；L35-5 两个子例各自同文案同位置”。
- **L-2**（L204、L230）：容量脚本改为“先打印实际 trait 条数，断言第 65 条 trait 行报 `too many traits`”。
- **L-3**（L126）：其余 iface 互赋归 L35-5 的非法 upcast（`only a supertrait upcast is allowed`），由 E35-7/E35-16 覆盖。
- **编号**：E35-6 L218=`ast/223`；E35-10 L222=`ast/219`/`220`；R35-3 L268=`222`/`223`；S9a/S9b L202–203=`219–222`/`223–224`；交付 L285=`219–224`；无 215–218 残留。
- **预算**：编译器 900–1,690、夹具 210–340、样例 80–150、文档 100–160、合计 1,290–2,340；与 roadmap 50 一致，逐片 ≤150。

---

## 4 结论

| 卡片 | 结论 | 阻塞项 |
| --- | --- | --- |
| Phase 34 | **GO（附 M-1 条件）** | M-1：modules 段的 `tparam_residue` 显式调用点 + 手写脏 `.c`；其余 9 条已闭合。 |
| Phase 35 | **GO** | 无。 |
| Phase 36 | **NO-GO** | H-1：③ 的字段声明/写入 pass/顺序未落地；H-2：E36-1 的 `nm -g` 与 `grep -c` 在真实静态产物上不可观测；M-1：源码体 `_self`；M-2：共用释放与体内断言冲突；M-3：预算 delta 未解释。 |

---

## 5 实测证据（/tmp）

```text
# 现有 Drop glue 形态（test/modules/autodrop/prog.expected.c）
3:static void Box_Drop_drop(void *self);
63:static void Box_Drop_drop(void *self) {

# 最小 impl Drop for Box 的生成 C
static void __attribute__((unused)) Box_Drop_drop(void *self);
static void __attribute__((unused)) Box_Drop_drop(void *self) { ... }
grep -c 'Box_Drop_drop' = 2

# 对象文件
nm -g --defined-only p36_empty.o | grep -c 'Box_Drop_drop' = 0
（静态符号是局部 t；未被调用时还可能被优化掉）

# C99 隐式声明（P34 M-4）
clang -std=c99: error: call to undeclared function 'Counter_get';
ISO C99 and later do not support implicit function declarations

# drop 签名（P36 M-1）
void drop(void)  -> ct check rc=0
void drop()      -> ct check rc=0
现有源码体使用 self->n（check-ast.sh:5034、issues/selfhost/sh28-...md:28）
```

**未做**：未跑 `bash selfhost/check-all.sh`；未改卡片、golden、版本号、门禁；未 commit；未触碰 `docs/design/phase32-draft.md` 与 `2026-11-11/` 的其他内容。
