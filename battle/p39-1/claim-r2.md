# battle/p39-1 主张书 第 2 轮（claim-r2，REQ，立场 A′）

| 字段 | 值 |
| --- | --- |
| 争点 | `ct build --lib` 导出面选择机制：A（`pub` 派生 + 非 C 兼容硬错） vs B（显式标记/清单） |
| 本轮 | T3 交叉质证（第 2 轮）；已读 `battle/p39-1/counter.md`（223 行） |
| 锚定 HEAD | `ac040d17f0bfcebe5bea042bcd6d07070dc05978` |
| 编译器 | `/tmp/p39head/ct`（`ct v0.37.0`，sha256 `080650f62e4fa894efc672c10a14a615bdaa531bdef5f24470e99fb37e59dd10`，HEAD `ac040d1` 干净归档构建） |
| 干净源码 | `/tmp/p39head/src`；临时目录 `/tmp/p39claim` |
| 只改 | 本文件；未触碰源码/文档 |

## 0 本轮结论（先说给裁判）

1. **承认反对席 C1、C3、C5-1 成立**：T2 原文的 A 在 `p34_pub_generic` 上确实整库判死（C1）；卡面 `:45`（不导出泛型）与 `:102/:134`（泛型硬错）确实自相矛盾（C3）；`vendor/std` 确实不在内建判定里（C5-1）。
2. **承认 T2 的一处事实错误**：T2 把 `lib/std/Str.h.ct` 当作非内建、称其 7 个 `Str` 函数会触发 L39-1——错了。`lib/std` 在 `find_builtin()` 覆盖内，是内建单元，不进导出面；真正的漏洞只在 `vendor/std`（对方 C5-1）。
3. **受约束修正 A → A′**（仍是 A 族，不是改投 B）：
   - **泛型 `pub` 函数（含 `T: Trait` 约束泛型）不进入导出候选**：跳过，并输出一条 `file:line:col` 的诊断（L39-1w），构建继续。依据是机械事实：泛型模板在生成 C 里只产生 `static` 实例（`t`，无外部符号，E1-r2-a），C 侧连手写声明都调不到它——跳过不改变归档符号面。
   - **其余非 C 兼容签名（按值 struct / trait 值 / std 类型 / `own`）仍 L39-1 硬错、不写产物**：它们会生成真实外部符号（`T`，E1-r2-a），C 侧可以手写不相容声明强行调用，属 D39-6 用户已定黑名单。
   - **「非内建」定义扩到任意位置的 package std（含 `vendor/std`）**，修 C5-1；这是定义澄清，不改签名黑名单。
4. A′ 与 B 的区别不变：**无标记、无清单、无新语法**；导出面仍由 `pub` 派生。代价是 A′ 收窄了 T2 原文「非 C 兼容一律硬错」的范围——是否接受，由裁判定。

---

## 1 E5：逐条引用反对席原文并回应

> 引文均来自 `battle/p39-1/counter.md`，标行号；未引用的段落不表示同意。

### Q1 `counter.md:26`（§1 C1「泛型 helper 整库判死」）

> 「作者要导出的只有 C 包装器 `from_lib`；`id` 只是同头里的泛型 helper。A 不给作者"只导出 `from_lib`"的任何入口 → 导出集合 ≠ 作者意图，J-1 夹具 2 直接失败。」

**回应：成立，且是本轮修正的直接原因。** T2 原文的 A 确实没有出口：`from_lib` 与 `id` 同在一个 `.h.ct`，`id` 命中规则 3 → 整库 L39-1。A′ 把「泛型模板」从导出候选里移出（跳过 + 诊断），于是该单元只导出 `from_lib`，`id` 保持跨单元可见、不再触发中止——J-1 夹具 2 由失败转通过。**不成立的部分**：这条只证「泛型子规则」错，不证「`pub` 派生」机制错；修一个子规则不等于必须换 B。

### Q2 `counter.md:39`（§1 C3「卡内自相矛盾」）

> 「`phase39-draft.md:45` 写"不导出泛型函数……三者都不写进 `.abi.h`"（语义 = 跳过、继续构建）；`:102` 规则 3 …`:104` …`:134` …**同一文件、同一函数，两条相反的处置。**」

**回应：成立。** 这是卡面文本缺陷，不是 A 的机制缺陷。A′ 明确取 `:45` 作为**泛型模板**的处置（不写进 `.abi.h`、跳过），并把 `:102/:104/:134` 的 L39-1 限缩为「会生成外部符号的非 C 兼容签名」。需要卡上改 3–5 行：§3.1 规则 1 加「泛型模板不是导出候选」、规则 3/L39-1 行加「仅针对有外部符号的签名」。**风险披露**：D39-6（`phase39-draft.md:60`）逐字含「泛型……一律 L39-1」，A′ 缩窄该项，需 EDITOR 明确裁定；若裁判认为用户批准的三项决策不可由本庭缩窄，则 A′ 不成立，本席接受按 T2 原文 A 被判。

### Q3 `counter.md:51`（§1 C5-1「vendor/std 不在内建」）

> 「`vendor/std` 不在其中 → 包 std 是普通单元 → `lib/std/Str.h.ct:33,51,63,70,80,99,117` 的 7 个值类型 `Str` 的 `pub` 函数全部触发 L39-1。J-2 要求"`lib/std/**/*.h.ct` 不改一行即可构成 `--lib` 库"，在 A 下这半句要么失败（vendor/std），要么因内建跳过而不可测。」

**回应：成立（C5-1），并修正 T2。** 仓库内 `lib/std` 是内建、不进导出面，T2 的 A-1 锚点用错了；真实风险是 `vendor/std`（`ct get std` 拉入的位置）不被 `is_builtin_unit` 识别。A′ 第 3 条把 package std 的任意位置纳入内建，J-2 在两种位置上都不再触发 L39-1。

### Q4 `counter.md:52`（§1 C5-2「visibility 不改变归档符号面」）

> 「`-fvisibility=hidden` 不会把 std 的 `pub` 函数从 `nm -g` 里去掉。……A 承诺"导出函数是唯一 default 可见的符号"……而卡片自己在 `:40` 承认"visibility 不改变静态归档的全局符号表"——两处结论互相否定。」

**回应：前提成立，结论不成立为对 A 的反驳。** `nm` 事实成立（T2 未否认）；但卡片 `:40` 已把「归档符号表」排除在 ABI 承诺之外，承诺面是 `.abi.h`。A′ 的硬错门恰好保证：凡是会留下「可被 C 手写声明调用」的外部符号、而签名又不在黑名单允许范围内的单元，直接不产库——不会出现「`.abi.h` 声明面 ⊂ 可调用符号面」的错配。多出来的 vtable/impl 符号是 `:40` 明示的非承诺面。C5-2 是一条需要改文案的卡面张力，不是 A 应被 rejected 的理由。

### Q5 `counter.md:34`（§1 C2「全量 pub、无子集入口」）

> 「把这类工程改成 `--lib`，A 会把这 72 个全部写进 `.abi.h`——恰好是 J-1 要排除的"作者没打算导出的集合"。」

**回应：部分成立。** A/A′ 确实没有「只导出 C 兼容 `pub` 的真子集」的输入；这是 A 的公开定价：`pub` = 公开 API，`--lib` 把它投影到 C。**不成立的部分**：`selfhost/ct-ast` 不是 `--lib` 目标，72 个访问器是编译器自己的单元 API，不构成一次实测的 J-1 失败；真实库若需要「跨单元 helper 但不对 C 公开」，B 的清单也只是第二份手写真相，会与代码漂移（T2 E5 已述）。A′ 只修「无符号的泛型模板」，不承诺解决「有符号的内部 helper」——这条留作 A 的已知代价。

### Q6 `counter.md:212`（§6「可预测已被打破」）

> 「**"可预测"已被 A 自己打破**：`:45`（不导出泛型 = 跳过）与 `:102/:104/:134`（泛型 = L39-1 中止）对同一函数给出相反处置（C3）……」

**回应：成立（在 T2 原文下）。** 文本二义确实伤可预测。A′ 用一条明确规则消歧（泛型 = 跳过 + 诊断；有符号非兼容 = 硬错），并给出 E3-r2 的一次性预测。**不成立的部分**：这不能推出「`pub` 派生机制不可预测」；消歧后规则是机械的。

### Q7 `counter.md:168`（§3 E2-6「用户签字不覆盖选择机制」）

> 「用户签字不能补上 J-1 的缺口。」

**回应：在 T2 原文下成立；在 A′ 下缺口被补上。** 用户签字覆盖的是「导出面里能放什么签名」（D39-6 黑名单）；A′ 不动黑名单，只把「无符号的泛型模板」从候选里移出。J-1 剩下的缺口只有 trait 值 / 按值 struct 的硬错——那正是用户签字的部分。若裁判认为签字也覆盖「泛型的处置方式」，则 A′ 的修正需要用户再确认，本席不回避。

---

## 2 新增证据（不重复 T2）

### E1-r2-a 符号类别：泛型实例是 `static`，trait 值/按值是外部符号

夹具（`/tmp/p39claim/f2_generic/lib.h.ct`，在 T2 的 f2 上追加 `lib_wrap` 以强制实例化）：

```c
/* F2': C-compatible export + generic helper + one concrete instantiation. */
pub T lib_id<T>(T x)
{
    return x;
}

pub int lib_add(int a, int b)
{
    return a + b;
}

pub int lib_wrap(int x)
{
    return lib_id<int>(x);
}
```

```console
$ cd /tmp/p39claim && mkdir -p out1b out2b out3b
$ /tmp/p39head/ct build --emit-c f1_purec/lib.h.ct --outdir out1b >/dev/null 2>&1
$ /tmp/p39head/ct build --emit-c f2_generic/lib.h.ct --outdir out2b >/dev/null 2>&1
$ /tmp/p39head/ct build --emit-c f3_trait/lib.h.ct  --outdir out3b >/dev/null 2>&1
$ cc -c out1b/lib.c -o out1b/lib.o && cc -c out2b/lib.c -o out2b/lib.o && cc -c out3b/lib.c -o out3b/lib.o
$ tail -8 out2b/lib.c
    return (a + b);
}
int lib_wrap(int x) {
    return lib_id__ct1(x);
}
static int lib_id__ct1(int x) {
    return x;
}
$ nm out2b/lib.o | grep -E 'lib_id|lib_wrap|lib_add'
0000000000000000 T _lib_add
0000000000000044 t _lib_id__ct1
0000000000000020 T _lib_wrap
$ nm out1b/lib.o | grep -E 'lib_add|lib_name'
0000000000000000 T _lib_add
0000000000000020 T _lib_name
$ nm out3b/lib.o | grep -E 'sink_open|sink1'
0000000000000088 D _sink1
000000000000003c T _sink_open
```

**读法**：泛型实例 `lib_id__ct1` 在生成 C 里是 `static`，`nm` 类别是小写 `t`（local），**没有外部符号**；`T` 是 external text。按值 `Str`（对方 E1-d 的 `_str_from` 等 9 个）与 trait 值返回的 `sink_open` 都是 `T`。这就是 A′「无符号 → 可跳；有符号 → 必错」的机械依据，也回答了 C3 的「跳过还是硬错」：**按符号类别分，不按 `pub` 分**。

### E1-r2-b 既有的非致命、带位置诊断通道（J-5/J-4）

```console
$ cd /tmp/p39head/src
$ /tmp/p39head/ct build test/modules/leak/prog.ct -o /tmp/p39claim/leak_app; echo "exit=$?"
'cc' -std=c99 -I '.ctbuild' '.ctbuild/Vec.c' '.ctbuild/Option.c' '.ctbuild/Result.c' '.ctbuild/Str.c' '.ctbuild/prog.c' '-o' '/tmp/p39claim/leak_app'
test/modules/leak/prog.ct:6: warning: potential leak: 'p' (S*) allocated but never deleted
exit=0
$ /tmp/p39head/ct check test/modules/leak/prog.ct; echo "exit=$?"
test/modules/leak/prog.ct:6: error: potential leak: 'p' (S*) allocated but never deleted
exit=1
$ /tmp/p39head/ct check test/modules/sig_mismatch/prog.ct; echo "exit=$?"
test/modules/sig_mismatch/prog.ct:4:10: error: signature mismatch: 'f' in impl of 'T' for 'S': return type 'void' does not match the trait's 'int'
exit=1
```

**读法**：编译器已有「非致命警告 + `file:line`」通道（`ct build`，exit 0），也有「`file:line:col`」的严格位置格式（`ct check`，`4:10`）。位置格式的来源（`selfhost/ct-ast/tool/diag/Diag.h.ct:385-391`，HEAD 锚点）逐字为：

```c
/* `ct check` follows the source location contract
   (`file:line:col:`); compile and build stay `file:line:` so
   their bytes do not move (D19-4). */
if (self->strict && w->col > 0)
    snprintf(loc, sizeof loc, "%s:%d:%d:", w->file, w->line, w->col);
else
    snprintf(loc, sizeof loc, "%s:%d:", w->file, w->line);
```

警告记录本身已带列号（`Diag.h.ct:44` `record_sig_warn(int line, int col, ...)`）。`--lib` 是新模式、没有既有 golden 字节负担，把 `--lib` 放进「严格位置」集合即可输出 `file:line:col`——**约 2 行，J-5 与 J-4 同时满足**，不新增诊断机制。

### E2-r2 新锚点（均 `git grep -n ... HEAD` 取得，非 T2 已有）

| # | 锚点 | 原文 | 用途 |
| --- | --- | --- | --- |
| N-1 | `examples/38_ecosystem_reuse/src/eco.h.ct:24` | `pub T twice<T>(T x) {` | **新的不利实例（T2 未覆盖 `examples/`）**：第三个「可复用库 + 泛型 helper」；A′ 的跳过规则把它从判死转为可成库 |
| N-2 | `docs/design/phase39-draft.md:60` | `\| D39-6 \| v1 只收标量 / 指针 / 函数指针 / 数组参数 / 指向具名 struct 的指针；按值 struct、trait 值、泛型、std 容器类型一律 L39-1 \|` | **对 A′ 不利**：用户批准的黑名单逐字含「泛型」；A′ 缩窄它，需裁判/用户确认（Q2 已披露） |
| N-3 | `selfhost/ct-ast/tool/diag/Diag.h.ct:26` | `/* One collected warning (10.2 signature mismatch, 10.3 leak, 19.1 arity,` | J-4/J-5：警告存储已存在，不需要新机制 |
| N-4 | `selfhost/ct-ast/tool/diag/Diag.h.ct:44` | `int  record_sig_warn(int line, int col, const char *method, const char *trait,` | 列号已记录，`--lib` 可直接输出 `file:line:col` |

---

## 3 明确承认 / 不承认

| 对方条目 | 判定 | 理由（本轮） |
| --- | --- | --- |
| C1 泛型 helper 整库判死 | **成立**（对 T2 原文） | A′ 修：泛型模板跳过 + 诊断；`p34_pub_generic`/`p34_pub_bound`/`eco` 三实例转为可成库 |
| C2 无「导出子集」入口 | **部分成立** | 「C 兼容的内部 helper 也会被导出」是 A 的公开定价；`selfhost` 72 个不是 `--lib` 目标，不构成实测 J-1 失败 |
| C3 卡面 `:45` vs `:102/:134` 矛盾 | **成立** | A′ 取 `:45` 处置泛型模板，`L39-1` 限缩到有外部符号的签名；需卡上 3–5 行 + 裁判裁定 |
| C4 `pub` = 跨单元可见 ≠ 对外 ABI | **事实成立，致命性不成立** | `--lib` 是 opt-in；非 `--lib` 构建的 `pub` 语义不变。PH-39 O2 已批准「`.h.ct` 的 `pub` 即 ABI 面」这一方向（对方 E2-6 自承用户签过三项） |
| C5-1 `vendor/std` 非内建 | **成立** | A′ 第 3 条：package std 任意位置纳入内建；同时修正 T2 的 A-1 错误 |
| C5-2 `nm` 仍有 std 符号 | **前提成立，反驳不成立** | `:40` 已把归档符号面排除在承诺外；A′ 的硬错门避免「可手写调用但未声明」的错配 |
| C6 现有工程转库需改造 | **对 T2 成立；A′ 下泛型部分不成立** | 泛型单元零改动成库；trait 值 / 按值 struct 仍硬错，属 D39-6 |
| P1 泛型库非零退出 | **对 T2 成立；A′ 下预测改变** | A′ 预测：exit 0、`.abi.h` 只有 `from_lib`、stderr 有 `lib.h.ct:3:<col>` 的 L39-1w |
| P2 `nm` 符号与 `.abi.h` 不等 | **不成立为对 A 的检验** | 该预测预设「跳过」实现；A′ 对 Str/trait 是硬错中止，P2 的前提不发生 |
| P3 两夹具必有一个不成库 | **A′ 下失效** | 两者都成库（泛型跳过、`from_lib` 导出） |
| P4 selfhost `.abi.h` ≥70 | **不适用** | `selfhost/ct-ast` 无 `--lib` 目标；且 A′ 下泛型被跳过，计数不再等于 72 |
| §7 自承「B 至少要一次用户批准」 | **接受** | B 的 `pub export` / `--export` 都撞 `AGENTS.md:469`；本席不以此单独判 B 死，只作为 J-3 的对照 |

**一句总结**：对方赢下「T2 原文的泛型硬错」与「卡面自相矛盾」两点；没有赢下「必须换成 B」——A′ 用符号类别把两件事分开，保住了 A 的机制。

---

## 4 A′ 下 J-1…J-5 的结论

| 判据 | A′ 下 | 需要什么输出 | 残留风险 |
| --- | --- | --- | --- |
| J-1 意图一致 | **成立**（在 D39-6 约束下） | f1：2/2 导出；f2：只导出 `from_lib`，`id` 跳过 + 诊断；f3：trait 值硬错——属 D39-6 用户已定黑名单，不在本庭裁判范围。若裁判把 f3 也计入，则 J-1 为 2/3 | f3 的字面失败；D39-6 缩窄需批准 |
| J-2 零语法改动 | **成立** | `lib/std` 本就在内建（T2 A-1 更正）；`vendor/std` 由 A′ 纳入内建；`p34_pub_generic`/`p34_pub_bound`/`eco` 零改动成库；`ns_types`/`xunit_box` 的 trait 值仍硬错（D39-6） | 两个 trait 值单元 + 用户已定黑名单 |
| J-3 语言面最小 | **成立** | 只新增 `--lib` CLI；无关键字、无清单、无 `pub export` | 无 |
| J-4 成本 ≤2 文件/≤80 行 | **成立** | 泛型跳过分支（`Module.h.ct`，约 10 行）+ 内建判定扩 `vendor/std`（同文件，约 10 行）+ `--lib` 进严格位置集合（约 2 行）；警告通道已有（N-3/N-4）；G1/G3/G4 判据不变 | 若裁判要求 A′ 也输出「跳过清单」到 `.abi.h`，行数上浮 |
| J-5 可诊断 | **成立** | 跳过必须带 `file:line:col` + 原因（`'id' not exported: generic`）；`ct check` 的 `4:10` 已证格式可行（E1-r2-b）；不得静默 | `ct build` 当前警告只到 `file:line`；`--lib` 需显式进严格位置集合 |

**结论**：A′ 在 D39-6 用户已定黑名单的约束下满足 J-1…J-5；它不满足的是 T2 原文「所有非 C 兼容一律硬错」的字面定义。**A′ 仍是 A 族**（`pub` 派生、零标记、零新语法），不是 B。

---

## 5 E3-r2：A′ 的可证伪预测（一次性可判）

**预测 P-A′**：A′ 落地后，

```console
$ /tmp/p39head/ct build --lib test/modules/p34_pub_generic/lib.h.ct; echo "exit=$?"
```

应得到：`exit=0`；`.abi.h` 的原型集合恰为 `from_lib`（无 `id`、无 `_iface`/`_vtbl`/`Vec_`/`Map_`）；stderr 含一条 `test/modules/p34_pub_generic/lib.h.ct:3:<col>: warning: 'id' not exported: generic`（或同义 L39-1w）；`nm -g lib<base>.a` 不含 `_id__ct1`（因为它是 `t`）。

**同时预测**：

```console
$ /tmp/p39head/ct build --lib test/modules/xunit_box/net.h.ct; echo "exit=$?"
```

应得到 `exit=1`、`'stream_open' cannot be exported: trait value`（或同义 L39-1）、目录无 `.a`/`.abi.h`——**trait 值仍有符号（E1-r2-a 的 `T _sink_open`），按 A′ 必须硬错**。

**若 P-A′ 得到 exit≠0，或 `.abi.h` 仍缺 `from_lib`，或没有诊断地静默跳过，则 A′ 不成立。** 若第二条得到 exit=0（trait 值被跳过），说明实现把「有符号」也当成了可跳，违反 D39-6，A′ 不成立。

---

## 6 复现与限制

- 本轮全部命令在 `/tmp/p39head/src`（HEAD `ac040d1` 归档）或 `/tmp/p39claim`（自建夹具）下执行；二进制 sha256 见文首；无任何命令读写工作树的源码/文档。
- 新增夹具 `f2_generic/lib.h.ct` 的完整源码见 E1-r2-a；`f1_purec`、`f3_trait` 与 T2 E1-6 相同。
- **限制**：A′ 未实现，P-A′ 是规则预测，不是编译器输出；`--lib` 今天仍 `unknown option`。N-2（D39-6 含泛型）是 A′ 的最大合规风险：若裁判认为用户批准的三项决策不可由本庭缩窄，A′ 的修正无效，应按 T2 原文 A 判——本席接受该结果，不请求用叙述替代证据。
