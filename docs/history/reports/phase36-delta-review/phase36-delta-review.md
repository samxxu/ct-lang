# Phase 36 · `c735ff6` delta 独立复核

> 范围：`c735ff6`（`docs/design/phase36-draft.md` 88 行 + `docs/proposals/ct-pkg-agent-runtime.md` 54 行）及配套 `a72e4ff`（roadmap 两行）。只读；未改卡片、golden、版本号、门禁脚本，未碰 `stash@{0}` 与 `AGENTS.md`。
> 对照：`git show c735ff6`、`git diff b7f384e..HEAD -- docs/design/phase36-draft.md`（`b7f384e` 之前该卡已 GO 冻结）。

## 总判定：**NO-GO**

2 条 High（外部契约被写成既成事实；E36-8/零状态仍钉已删除的 `data`/`len` 布局且缺少 `cstr_release(NULL)` 契约），4 条 Medium。改完 High 即可复核，不需要重写整卡。

| 问 | 结论 | 级别 |
| --- | --- | --- |
| 1 外部依赖写成既定事实 | 是。`CStr`/`cstr_*` 全仓无实现、本机无 ct-pkg 检出；提案文档自称「提案」，卡片却用「由…提供」「已存在的 shim」 | **High** |
| 2 `Str` 句柄契约自洽性 | `retain`/按值拷贝与 D36-13 自洽；但 `release()`「返回剩余引用数」在深拷贝适配层下退化，且与 D36-13「两种都成立」冲突；`slice` 与 D36-6 直接矛盾 | **Medium** |
| 3 估算 60–120 | 逐片求和与 §10 三行完全对得上（240–430 / 320–510 / 500–800 / 60–120）；S4b=0 是本仓库交付缺口的真实存在处 | **Medium**（数字本身通过） |
| 4 S4a 可构造性与红证 | 技术上可构造（shim 机制已被 `153`/`154` 与 `map_unit_shim` 覆盖）；**按现范围跑不出红**，因为没有依赖任何 P36 新机制 | **Medium** |
| 5 roadmap 一致性 | 数字、D36-14、E/L 编号两行一致，无对不上的数；措辞共享同一处「由 ct-pkg 提供」的事实断言 | **通过**（措辞随 High-1 一并改） |
| 6 加 S0 前置核对 | 应加；建议 5 条事实 + 失败回退版本，见 §7 | **Medium** |

---

## 1 High-1：未证实的 ct-pkg API 被写成「已提供」

**判据行（卡片）**

- L20：`Str` **由 ct-pkg `std/string` 提供**，是 shim 的不透明句柄（`pub struct Str { CStr *h; }`）。
- L111：`Str` 的规范位置是 ct-pkg `std/string`（**shim 所在包**）。
- L127：`CStr` 是 shim 的不透明类型；`cstr_retain` / … / `cstr_c_str` **由 `std/string` 的 `.shim.h` 提供**。
- L175-176（D36-12/13）：理由写「避免与**已存在的** shim 实现重复」。
- L203 / L205（B36-7）：方案 1 被否的理由是「与**已存在的** shim 重复实现」；方案 3「`retain` 委托 shim」。
- 同句也进了 `docs/roadmap.md:51`（中文）与 `:1037`（英文）。

**实测**

```text
$ grep -rn 'cstr_\|CStr' --include='*.md' --include='*.ct' --include='*.h' --include='*.sh' . | grep -v 2026-11-12/
./test/modules/map_unit/libc/libc.m.ct:7:pub trait CStr { ... }          # 用户自定义 trait，与字符串无关
./test/modules/map_unit_type/ctypes/ctypes.m.ct:7:pub trait CStr { ... }
./test/modules/map_unit_cross/text/text.m.ct:5:pub trait CStr { ... }
# 其余命中全部是 phase36-draft.md 与 proposals/ct-pkg-agent-runtime.md 自身
$ ls -d /Users/samxx/trae-ws/*        # 只有 ct-lang 与 sam-utils
$ ls -d /Users/samxx/*ct-pkg*          # no matches
```

提案文档自己的状态是 L5「**提案**（2026-11-12；供 ct-pkg 维护者评审，非 ct 仓库立项）」，L103 写的是「适配层契约（`.shim.h` **必须提供**）」——这是正确的规范语气；L87 的「对**既有** shim 的不透明句柄」仍越界。`AGENTS.md:51` 明确 `ct-pkg/std`「❌ 不在本仓库维护」。

**可验证修法**

1. 卡片 L20/L111/L127 改为：「`Str` 的**目标位置**是 ct-pkg `std/string`；本相只冻结它与适配层的**契约**（见 `docs/proposals/ct-pkg-agent-runtime.md` §2.4），不假定该包已存在。」
2. D36-12 理由改「避免与规划中的 shim 重复」；D36-13 与 B36-7 的「已存在」全部改「拟由 ct-pkg 提供（见提案）」。
3. `roadmap.md:51`/`:1037` 同步为「**拟**由 ct-pkg `std/string` 提供（待 S0 核对）」。
4. 在 §2.2 增加一行基线事实：「ct-pkg `std/string` 未在本环境检出（`ls -d ~/*ct-pkg*` 无结果）」——把「未观测」写出来，而不是留空让人误读为已证。

---

## 2 High-2：E36-8 与 §3.1.3 仍钉旧 `{char *data; int len}`

**判据行**

- L243（E36-8）：`Str_Drop_drop` 体内含 `free(_self->data)`、`_self->data = 0` 与 `_self->len = -1`（或夹具分配计数归零）。
- L94：`Str` 零状态为 `data=0, len=0`（drop 只 `free(NULL)` 并置 `len=-1`）。
- 新表示见 L114：`pub struct Str { CStr *h; } use Drop;`，L129 又说 `Drop` 只做 `cstr_release(self->h)`。

按 L114/L129，`Str_Drop_drop` 体内不可能出现 `_self->data`/`_self->len`；E36-8 的主断言**不可满足**。括号里的「或夹具分配计数归零」没有给出计数器、命令与期望值，不能作为判据替代。

**同一个洞还漏了零状态契约**：L94 依赖「glue 无条件 drop payload」，`Option<Str>::none()` 的 `delete` 会对 `h == 0` 调 `Str_Drop_drop` → `cstr_release(0)`。旧布局靠 `free(NULL)` 安全；新布局必须在 shim 契约里明确 **`cstr_release(0)` 是 no-op**，否则 `Option<Str>` 的 `none()` 路径是未定义行为。提案的契约表（L107-110）没有这一条。

**可验证修法**

1. E36-8 改为：`Str_Drop_drop` 的生成体包含 `cstr_release(_self->h)` 且不含 `free(`；`delete` 后 `p = 0` 仍由产物 grep；分配计数用夹具 `Probe` 形态显式定义（计一次构造、一次释放，期望 1→0）。
2. L94 改为：`Str` 零状态为 `h = 0`，`Str_Drop_drop` 对 `h == 0` 调用 `cstr_release(0)`。
3. 提案契约表加一行：`cstr_release(CStr *p)`：`p == 0` 时为 no-op，返回 0。
4. 在 S4a 夹具里加一条 `Option<Str>::none()` + `delete` 的用例，锁住零状态路径（这条同时可作为 S4a 的红证，见 §5）。

---

## 3 Medium-1：`slice` 语义两处互斥

- D36-6（L169）：`slice` 返回**深拷贝**；B36-3（L188）同口径。
- L131：`slice` v1 返回独立 `Str`（**复制或引用计数视图由适配层决定**）；L144 表格同样写「复制或引用计数视图，由适配层定」。

这是同一张卡里两条互斥的决策。修法二选一：

- (a) 保留深拷贝：L131/L144 删掉「或引用计数视图」，统一为「深拷贝，不借用」；
- (b) 允许视图：D36-6 改为「`slice` 返回可独立 `release` 的独立句柄；深拷贝或 refcount 视图由适配层决定，CT 不假设」，B36-3 同步。
建议 (b)，与 D36-13 的「不规定实现」保持一致。

## 4 Medium-2：`release()` 返回值在深拷贝适配层下退化

- L118/L129/L149：`release()` 返回剩余引用数；L129 还说「与 `Vec.release()` 的形态一致」。
- D36-13（L176）：「引用计数或深拷贝由适配层决定；CT 层不假设」。

`Vec<T>::release()` 确实返回剩余计数并从 `self->h->refs` 读取（[Vec.h.ct:187-207](file:///Users/samxx/trae-ws/ct-lang/lib/std/Vec.h.ct#L187-L207)），但 `Vec` 的 `retain` 是真实 refcount（`:176-183`）。若 `Str` 适配层是深拷贝，`retain()` 产生的是**独立 buffer**，`release()` 的返回值只能是「本句柄 1→0」，不可能回报共享计数——「剩余引用数」在不同适配层下含义不同，不能作为稳定契约。

**推荐写法**

- 契约句改为：「`release()` 释放本句柄并返回**该句柄所属 buffer** 的剩余计数；引用计数适配层给出真实共享计数，深拷贝适配层只会返回 0（释放前为 1）。门禁只断言 **0/非 0**，不断言 `> 1`。」
- 若坚持「返回共享剩余数」是契约，则 D36-13 必须收紧为「shim **必须**实现引用计数，`cstr_release` 返回 int」——不能同时写「两种都成立」。
- 「与 `Vec.release()` 形态一致」保留，但要补一句「形态一致 ≠ 计数语义一致」。

`Str b = a;`（L132）本身与 D36-13 自洽：拷贝是别名、不 retain；`a.release()` 后 `b` 悬垂。建议在 L132 后补「`b` 是别名而非所有权副本；`a.release()` 后不得再用 `b`」，并纳入 S5 的一个运行期用例（或明确写成文档警告，不进判据）。

## 5 Medium-3：S4a 按现范围跑不出红

技术可行性：有先例。`153_into_type_host`/`154_into_shim` 与 `test/modules/map_unit_shim` 证明 `.shim.h`/`.shim.c` 会被拼进 `cc` 行（[check-ast.sh:513-520](file:///Users/samxx/trae-ws/ct-lang/selfhost/check-ast.sh#L513-L520) 的 `-I` 扫描、`:550` 的 `*.shim.c`），`test/modules/**` 是显式接线（`:892` 起逐块），所以「本地 `Str` + 伪 `CStr`」写得出来。

但它**不依赖任何 P36 新机制**：`Vec<Str>` 元素协议是 P31 已有，非泛型固有方法与跨单元是 P34 前置，`own Str *` + `delete` 是既有 AutoDrop（要求 struct `use Drop`，也已有）。P36 父提交上这份夹具会直接绿，违反新规范 `AGENTS.md` §6「逐片红证」——新夹具不在三类豁免里（纯重构/纯文档/无关实现改动）。

同一问题波及 E36-6/E36-7/E36-10：它们测的是本地库函数的 `len/slice/concat/compare/内嵌 \0`，都是既有语言能力 + 普通 C 代码，同样在父提交上就是绿。

**可执行替代（推荐 a）**

- (a) 把 S4a 并入 S4c1/E36-4：夹具改为 `own Option<Str> *` + `delete` 触发 shim 释放；在 `Option` 加 `use Drop` 之前，这条必然失败（`delete` 不释放 payload，计数停在 1）——真红；`use Drop` 落地后转绿。
- (b) 把 E36-6/E36-7 从「退出判据」降为「库行为回归（非红证）」，并在 §6 切片表里与 S4a 合并；判据列表只保留有编译器侧红证的 E36-1…E36-5/E36-8/E36-9。
- 无论哪种，S0 必须记录「每个 E 在父提交上的红证命令与原文」，不能只在 §13 写一句「复跑探针」。

## 6 Medium-4：S4b 记 0 行，交付物缺一块且无责任人

§6 L223 把正式 `Str` 放在 ct-pkg 且计 0 行；§10 L276 同口径。数字上诚实（本仓库确实不产出这 180–300 行），但：

- 「谁保证 ct-pkg 那边真有人做」：仓库内没有任何指针——`AGENTS.md:51` 说 `ct-pkg/std` 不在本仓库维护；`docs/proposals/ct-pkg-agent-runtime.md:5` 是「提案，供 ct-pkg 维护者评审」，还带 3 个未决问题（L169-171 区域），没有 owner、版本、验收。
- 结果：Phase 36 可以在「只有伪 `CStr` 夹具」的情况下收口，而用户拿不到任何可用的 `Str`；E36-6/E36-7 若按本地伪实现变绿，会把「契约已验证」误读为「库已交付」。

**修法**

1. S4b 行改为「**外部依赖（非本相交付）**：ct-pkg `std/string` ≥ 某 commit/版本；验收 = S0 的 `ct get std` + 最小 `import std::string` 程序；未落地则本相 E36-6/E36-7/E36-10 不计入完成」。
2. §10 的 60–120 行脚注加一句「不含 ct-pkg 侧 180–300 行；那部分由 ct-pkg 的验收承担，不在本仓库计数」。
3. 提案 §7 增加一行 owner/版本占位，避免「提案即事实」。

## 7 Medium-5（Q6）：应加 S0 前置核对

**S0 必须验证的 5 条事实**

| # | 事实 | 验证方法（拿到什么 / 跑什么 / 看什么） |
| --- | --- | --- |
| 1 | ct-pkg `std` 包含 `string` 模块，且本环境可取 | 临时目录跑 `ct get std`；`find vendor -path '*string*'`；记录 `ct.lock` 里的版本与 git commit sha |
| 2 | shim 契约逐项可核对 | 读 `std/string` 的 `.shim.h` 原文：`CStr` 的 typedef、`cstr_retain/release/len/slice/concat/compare/c_str` 的声明与返回类型（重点 `cstr_release` 是否返回 int、是否对 `0` no-op） |
| 3 | `Str` 单元能看见 `CStr` 声明 | 看该包 `.h.ct` 是否用 raw `#include` 引入 shim 头；`ct build` 产物里 `#include` 与 `-I` 是否齐（参考 `map_unit_shim` 的断言形态） |
| 4 | 依赖机制已在父提交落地 | 父提交跑 `check-ast`：P31 元素协议夹具、P34 非泛型固有方法跨单元夹具、既有 `own`/`delete` 夹具全绿；记录 `baseline: <sha>` |
| 5 | 真实 `Str` 能被本仓库夹具消费 | 最小程序：`import std::string;` + 构造 + `retain`/`release`；若跨包 import 不可用，O2 不能验收 |

**失败回退**：任一条失败，退回 `b7f384e` 时的 Phase 36 方案——即恢复 `lib/std/Str.h.ct`（显式 `impl Drop for Str` + 内联释放）+ S4a1/S4a2/S4b 三片 + 库预算 240–420 + roadmap 两行原值；按变更记录写「2026-11-12 的 shim 方案在 S0 核对失败，回退到 b7f384e 版本」，而不是直接 `git checkout` 掩盖历史。

## 8 其余小节与逐条回答

**Q3 求和核对（全部通过）**

- 编译器 240–430 = 60+40+60+25+25+30 / 100+80+100+45+45+60 ✅（L269）
- 夹具 320–510 = 90+80+90+60 / 140+130+140+100 ✅（L270）
- 样例 80–130 ✅；文档 100–160 = 60+40 / 100+60 ✅
- 编译器外合计 500–800 = 320+80+100 / 510+130+160 ✅（L273）
- 库 60–120 = 20+20+20 / 40+40+40 ✅（L274）；文件数 15–26 = 10+1+4 / 18+2+6 ✅
- 唯一「缺口」不是加法错误，而是 S4b=0 的外部依赖（§6）。

**Q5 roadmap 核对（通过）**

`roadmap.md:51` 与英文 `:1037`：依赖 31/33/34、编译器 240–430、夹具 320–510、样例 80–130、文档 100–160、库 60–120、D36-1–D36-14、E36-1–E36-14 / L36-1，与卡片 §10/§7/§4 全部一致；没有对不上的数字。唯一共享的问题是「由 ct-pkg 提供」的措辞（High-1），修卡片时两行同步。

**Low（不阻塞，建议同批修）**

- L13「字符串库代码单列」已过时：本仓库不再有字符串库代码，应改为「库代码（`Vec`/`Option`/`Result` 接入）单列」。
- E36-10（L245）写 `test/modules/p36_str`，§12（L306-307）写 `test/modules/p36_str_shim`；统一为一个名字。
- §2.2 探针 3（`own Str s`）与探针 4（`grep struct Str lib/std`）在新方案下**永远不会转绿**（D36-8 明确不做值移动、`lib/std` 明确不定义 `Str`）。它们应标注为「基线事实/非目标确认」，不要与探针 1/2 并列成「红证」。
- L94 的「`Probe_Drop_drop` 遇到 `id==0` 返回」与 `Str` 零状态是同一类契约，建议合并成一条「零状态可安全 drop」的通用规则，避免只修 `Str` 漏掉 `Probe`。

## 9 复核证据

```text
git show --stat c735ff6   → 2 files, +89/−53（phase36-draft.md 88 行、proposal 54 行）
git log --oneline b7f384e..HEAD → c735ff6 / a72e4ff / 69f2396 …（b7f384e 为卡片 GO 冻结时点）
grep -rn 'cstr_\|CStr'     → 仅卡片/提案自身 + 三处无关的 `map trait CStr for type char *` 夹具
ls -d ~/*ct-pkg*           → no matches；~ /trae-ws 下只有 ct-lang、sam-utils
lib/std/Vec.h.ct:176-207   → retain 真 refcount；release 返回剩余计数并清零句柄
check-ast.sh:513-520,550   → ast 夹具的 shim `-I` 与 `*.shim.c` 接线
check-ast.sh:1879-1884     → shim 头按 `.m.ct` 的 base 名 `#include`
AGENTS.md:51               → ct-pkg/std 不在本仓库维护
AGENTS.md §6               → 逐片红证；新夹具不在三类豁免内
```

未执行：`bash selfhost/check-all.sh`（只读评审，且主工作区有并行会话）。
