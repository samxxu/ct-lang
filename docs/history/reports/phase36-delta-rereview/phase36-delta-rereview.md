# Phase 36 · `4e02f31` 复核（对上一轮 2 High + 4 Medium）

> 范围：`4e02f31` 的 `docs/design/phase36-draft.md`（+53/−33 实为 84 行改动）与 `docs/roadmap.md`（+2/−2）。只读；未改卡片/roadmap/golden/版本号/门禁脚本，未碰 `stash@{0}`、`AGENTS.md`、`selfhost/`。

## 总判定：**NO-GO**（1 High + 3 Medium + 2 Low）

设计层面的 2 High + 4 Medium 已实质闭合；未闭合的是**红证纪律**：§13/T-7 仍要求提交一条红灯提交，与 2026-11-12 刚落的 `AGENTS.md` §6「失败状态不提交、实现与夹具同一提交转绿」直接冲突。改完 H-1（一行）+ M-1/M-2 的标注即可 GO。

| 项 | 结论 |
| --- | --- |
| H-1 外部依赖措辞 | **闭合**。8 处全部改为「拟由/不假定存在」，`已提供`/`已存在` 清零 |
| H-2 E36-8/零状态/契约 | **闭合**。断言、`h=0`、`cstr_release(0)` no-op、`Option<Str>::none()` 用例都在；真红点在 E36-4 的 `own Option<Probe> *` 行 |
| M-1 slice 五处 | **闭合**。D36-6 / L133 / L146 / B36-3 / D36-13 口径一致 |
| M-2 release 返回值 | **卡片闭合**；提案 L94/L108 仍有「返回剩余引用数」硬承诺，待同步 |
| M-3 红证归属 | **未闭合**（新发现 H-1 规范冲突；E36-3/E36-8/E36-10 仍把「当前无 `Str`」当红证，但夹具自带 `Str`，父提交上必绿） |
| M-4 S4b 外部依赖 | **闭合**。验收命令与「未落地不得标记完成」都在；180–300 与 b7f384e 的 240–420 分解一致 |
| S0 五项 | **可执行**，2 处要修：§14 对第 5 项的后果与 S4b 冲突；第 3 项引用的是注释块 |
| roadmap 行号 | 英文 Phase 36 = **1036**，1037 是 Phase 37（作者说得对；我上一轮写 1037 是错的） |

---

## 1 High：T-7 仍要求提交红灯提交，违反新的工程规范

- [phase36-draft.md:327](file:///Users/samxx/trae-ws/ct-lang/docs/design/phase36-draft.md#L327)：「S0 在实现提交的父提交上复跑探针并**提交 `test(ownership): P36 红`**（含 `baseline: <sha>` 与原始输出）」。
- `AGENTS.md` §6（本轮新增）：「**失败状态不提交**。实现落地后，夹具与实现**同一次提交**成绿，主干在每个提交上都必须是绿的」「提交正文必须带一行 `red: rc=<N>, "<失败文案>"`」。

照 T-7 执行会：(a) 在 `main` 上留下红灯提交；(b) 与「不许用一次全局回放代替逐片红证」同源的旧 Phase 31 做法（先红提交、后统一转绿）复活。这不是措辞问题，是判据与硬规范冲突。

**可验证修法**（一行）：

> `- **T-7 先红后绿**：S0 在实现提交的父提交上**本地**跑红并记录 `rc` 与原文（不提交失败状态）；实现与夹具在同一提交转绿，提交正文逐条写 `red: rc=<N>, "<原文>"`，E36-6/E36-7 写 `red: n/a (库回归，父提交已绿)`。`

---

## 2 H-1 / H-2 逐项核对

**H-1（闭合）**：`grep -n '由 ct-pkg\|ct-pkg.*提供\|supplied by'` 的 8 处全部带限定词——L20 O2「拟由该包提供」、L112「拟由该包提供…不假定该包已存在」、L128「**拟由** `.shim.h` 提供（本环境未检出，签名来自提案契约）」、L139 标题、L177 D36-12「拟由该包提供」、L207 B36-7 方案 3「拟由该包提供」、roadmap L51「**拟**由…（待 S0 核对）」、L1036「**intended to be** supplied…pending S0 verification」。`已提供`/`已存在的 shim`/`shim 所在包` 已全部清零（最后一次 grep 无命中）。

§2.2 第 55 行的实测方式可复现，但输出随 shell 变：zsh 对 `ls -d ~/*ct-pkg* ~/trae-ws/*ct-pkg*` 报 `no matches found` 且 rc=1；`sh` 下是 `No such file or directory`。结论都能得到「无检出」。建议写成 `ls -d … 2>/dev/null || echo "no ct-pkg checkout"`（Low-1），别让读者以为必须看到空行。

**H-2（闭合）**：

- L257 E36-8：只断 `cstr_release(_self->h)` + **不含 `free(`** + `Probe` 计数 1→0 ✓。
- L131：`cstr_release(0)` no-op（返回 0）+ `Option<Str>::none()` 的 `delete` 必须无害 ✓。
- L95：零状态 `h = 0`，`Str_Drop_drop` 对 `h == 0` 调 `cstr_release(0)` ✓。
- L236 S4a、L253 E36-4：`Option<Str>::none()` + `delete` 都在 ✓。

**红点在哪一行**：不在 E36-8（本地 `Str` 自带 `use Drop` + 显式 `impl Drop`，`own Str *` + `delete` 在父提交上就是绿的）。真红点在 E36-4 的 `own Option<Probe> *p = malloc(...);`：父提交 `Option_Probe` 不 `use Drop`，`mark_owned` 在 [Memory.h.ct:102](file:///Users/samxx/trae-ws/ct-lang/selfhost/ct-ast/backend/mem/Memory.h.ct#L102) 报 `struct 'Option_Probe' does not use trait 'Drop'`，rc=1；S4c1 落地后转绿。E36-1/E36-2 的红点照旧（`impl<T> Drop for …` 的 `5:14 unexpected token`）。

---

## 3 M-1 / M-2 / M-4（闭合）

- **M-1**：L171 D36-6、L133 §3.2.1、L146 表、L189 B36-3、L178 D36-13 五处统一为「可独立 `release` 的独立句柄；深拷贝或 refcount 视图由适配层决定」；B36-3 另保留「T36-3 零拷贝**借用**视图」作为未来项，与 refcount 视图不是一回事（Low-2：建议在 B36-3 加半句「借用视图仍归 T36-3；refcount 视图只是实现选择」，避免读者把两者并成一条）。
- **M-2**：卡片内 `grep '剩余引用数'` 已无命中；L119/L130/L151/D36-13 统一为「返回所属 buffer 剩余计数，门禁只断言 0/非 0，不断言 >1」。**残留只在提案**（见 §6）。
- **M-4**：S4b（L237）写明「外部依赖（非本相交付）+ 验收 = S0 的 `ct get std` + 最小 `import std::string` + 未落地则 E36-6/E36-7/E36-10 不得标记完成」；L290 脚注「60–120 不含 ct-pkg 侧 180–300 行」与 `b7f384e` 的库分解（50+40+90 = 180 / 80+70+150 = 300）完全对得上，不冲突。

---

## 4 M-3 未闭合（Medium × 2）

**M-3a：E36-3 / E36-8 / E36-10 的「红证」列是假红**。三行仍写「当前无 `Str`」（[L252](file:///Users/samxx/trae-ws/ct-lang/docs/design/phase36-draft.md#L252)、[L257](file:///Users/samxx/trae-ws/ct-lang/docs/design/phase36-draft.md#L257)、[L259](file:///Users/samxx/trae-ws/ct-lang/docs/design/phase36-draft.md#L259)）。但夹具自带本地 `Str`（S4a 的 `test/modules/p36_str_shim`、E36-8 的 `ast/232` 内联），`Vec` 元素协议（P31）、非泛型固有方法（P34）、`own`/`delete`（既有）都不依赖 P36 → 父提交上一旦把夹具写出来就是绿的。这与 E36-6/E36-7 已标「库行为回归、非红证」的处理自相矛盾。

修法：把 E36-3/E36-8/E36-10 的红证列改为「机制/库回归，**非红证**（父提交上绿；夹具自带 `Str`）」；或者给 E36-3 改成依赖 P36 机制的形态（如 `Vec<Box<Str>>` 的级联释放，但那已属 S3），二选一，不能继续写「当前无 `Str`」。

**M-3b：E36-4 的 `Option<Str>` 用例落点不明**。E36-4 的夹具列是 `ast/229_option_probe_drop`，但本地 `Str` 定义在 `test/modules/p36_str_shim`（S4a）。跨夹具引用没有写清。修法：在 E36-4 行注明「`ast/229` 内联最小 `Str`」，或拆成 `ast/229`（Probe）+ `test/modules/p36_str_shim`（Str 零状态）两行，二选一。

---

## 5 S0 五项与回退规则

五项均可执行、判定可证伪，但有 2 处要修：

| # | 判定 | 备注 |
| --- | --- | --- |
| 1 | ✅ 可执行 | `ct get std` + `find vendor` + `ct.lock`；记录版本/sha 可证伪 |
| 2 | ✅ 可执行 | 读 `*.shim.h`，逐项对 `CStr` typedef 与 7 个 `cstr_*`；`cstr_release` 返回 int 且 `0` no-op 是硬判定 |
| 3 | ⚠️ 引用要改 | 「参照 `check-ast.sh:1879-1884`」落在**注释块**（177-186 也是同一段注释）；真正的断言在 [check-ast.sh:1886-1892](file:///Users/samxx/trae-ws/ct-lang/selfhost/check-ast.sh#L1886-L1892)（`grep -qF '#include "lib.shim.h"'` 与 `grep -qF -- "-I …/lib"`）。另外 `.h.ct` 的 raw `#include` + `-I` 传播是**未验证机制**（现有 shim 只对 `.m.ct` 生效），建议在判定标准里加一句「若 `ct build` 不给 `.h.ct` 的 shim 加 `-I`，本条不成立」 |
| 4 | ⚠️ 需点名 | 「P34 跨单元固有方法」没有夹具编号；改成 P34 卡里的具体 E34-n 或 `test/modules/**` 路径，才算可证伪 |
| 5 | ✅ 可执行 | 最小 `import std::string;` 程序；失败则 O2 不能验收，标准明确 |

**§14 回退规则**：可照做——`b7f384e` 的旧卡可 `git show` 取回（`:docs/design/phase36-draft.md` 的 L20 O2 内联 `lib/std/Str.h.ct`、L205-207 S4a1/S4a2/S4b、L258 库 240–420），旧 roadmap 两行也在（中文 L51、英文 L1036）。但有一处**后果冲突**（Medium-3）：

- §14 写「5 项**任一**不成立 → 自动回退」，S4b 又写「未落地则 E36-6/E36-7/E36-10 **不得标记完成**」。对第 5 项（真实 `Str` 取不到）给出两种不同处置：回退 vs 挂起等待。
- 第 5 项失败通常只是**时序**（ct-pkg 还没发版），自动回退会把一个刚 GO 的设计整体推翻，且要改 roadmap。
- 修法：§14 分两级——第 2/3 项（契约不兼容、`CStr` 声明进不来）→ 自动回退；第 1/4/5 项 → **阻塞相位、不自动回退**，等依赖落地后重跑 S0；S4b 的「不得标记完成」与后者一致。

---

## 6 提案文件需补的契约（不回写提案）

**必须补**：`cstr_release(0)` 的 no-op。理由不是风格：`Option<Str>::none()` 的 payload 是 `h == 0`，glue 无条件调 `Str_Drop_drop` → `cstr_release(0)`；没有这条就是 UB，而 E36-4 正是拿它当退出判据。

建议改两处（行号已核）：

1. [ct-pkg-agent-runtime.md:108](file:///Users/samxx/trae-ws/ct-lang/docs/proposals/ct-pkg-agent-runtime.md#L108) 表格行：
   `| `cstr_release(CStr *)` | 释放一个句柄并返回所属 buffer 的剩余计数（0 表示已释放；深拷贝实现只有 1→0）；**`p == 0` 为 no-op 并返回 0** |`
2. 同文件 L94 的注释同步：`int release(); /* 释放本句柄并返回所属 buffer 剩余计数；p == 0 为 no-op */`。
3. 可选但推荐：在表格后（新 L111）加一条 bullet「`cstr_release(0)` 必须无害；`Option<Str>::none()` 依赖这一点」，让 `Option` 零状态路径在提案里也有锚点。

**roadmap 行号**：英文 Phase 36 是 **L1036**，L1037 是 Phase 37。中文 Phase 36 是 L51。我上一轮报告写的 `:1037` 有误，以本次为准。

---

## 7 证据

```text
git show --stat 4e02f31            → 2 files, +53/−35（卡片 +51/−33、roadmap +2/−2）
grep -n '由 ct-pkg|ct-pkg.*提供|supplied by'  → 8 处，均带「拟/intended to be/pending S0」
grep -n '已提供|已存在的 shim|shim 所在包'      → 无命中
grep -n '剩余引用数' 卡片                       → 无命中（提案 L94/L108 仍有）
grep -n '^| 36 |' docs/roadmap.md               → 1036；^| 37 | → 1037
git show b7f384e:docs/design/phase36-draft.md   → L20 O2 内联 Str、L205-207 S4a1/S4a2/S4b、L258 240–420
git show b7f384e:docs/roadmap.md                → 中文 L51、英文 L1036 旧行均在
Memory.h.ct:102                                 → own 的 use Drop 校验（E36-4 红点）
check-ast.sh:1886-1892                          → shim 的 #include 与 -I 实际断言
```

未执行 `bash selfhost/check-all.sh`（只读评审，主工作区有并行会话在写 `selfhost/`）。
