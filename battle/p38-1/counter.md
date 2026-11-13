# battle/p38-1 反对席：A accept boundary

> 席位：REVIEW（反对席）。主张：**反对 B，主张 A（接受 v1 边界）**。
> 本文件**不是判决**；判决由 EDITOR 依 `question.md` 的 J-1…J-5 作出。本文只给证据、代价与失效条件。
> 约束遵守：只写 `battle/p38-1/counter.md` 与 `/tmp`；未改源码/测试/文档；未 git add/commit/tag/push；未触碰 `battle/p39-*` 与 `battle/p38-1` 之外的目录。
> 环境：macOS，`cc`（系统默认）；HEAD `0c9320c`（按 `question.md`）；实测日期 2026-11-13。
> 构建方式：`L0 -> L1 -> L2 -> ct-ast` 全链重建于 `/tmp/counter-a`，产物 `ct-ast v0.37.0`，构建日志 0 字节。

---

## 0 结论摘要（不是判决）

1. **A 的现状确实违反 E37-3 / language-spec 的字面契约**：`arr[pick()].area()` 在 `--runtime-checks` 下被接受、段错误、无任何 runtime 消息（E1-2，rc=139，stderr 空）。E37-3 与 language-spec **没有**排除带副作用接收者；phase38 §9.1 的「v1 边界」只是收口记录，不是规范条款。**这是 A 最强弱点，也是本文要求 A 必须补文档 + 修约 J-1 的原因。**
2. 但 A 的「文档化」不是零成本：至少 4 处文档 + 1 条决策/勘误 + 3 个测试缺口；且「接收者不得有副作用」这句话**不够**，必须写成「接收者表达式在两次求值间必须产生相同结果」（否则纯函数但值会变，如 `arr[clock() % 2]`，仍可绕过）。
3. **B 的成本声明不成立**：源码 10–30 行只在「不做真列号、不处理缓存、不做常量下标豁免」时成立。真列号要动 `Arena`/`Parser`（`fail_at` 硬编码 `errcol = 1`，E1-6 实测 `:21:1`）；warm cache 会静默跳过 emitter 检查（`Cache.h.ct` 的 key 只有 version + runtime_checks 等，不含「B 策略」；B 不换 key 就可被旧 `--runtime-checks` 缓存绕过）。这两项任一补上，B 都不止 ≤2 文件。
4. **B 会误伤合法代码**：`arr[0].area()` 今天在 guard 下正常 rc=7（E1-3）；`test/ast/10_iface_array/prog.ct:24-25` 的 `gs[0].greet()` 今天在 `--runtime-checks` 下正常发射 guard（E1-5）。B 的 `N_INDEX` 一刀切会把这两者都拒掉。`N_CALL` 分支则与 Phase 31 的 hoist 冲突：合法的 `make_lit(4).show()` 在发射时已物化成 `__ct_tmp0`（E1-4），B 若在 guard 点检查，`N_CALL` 分支是死代码；若在 hoist 前检查，则会拒掉这个合法且安全的程序。
5. `switch` 这一半**A 已经基本达标**：嵌套块/循环体一律拒绝在 `Stmt.h.ct:1662-1664` 已实现，`language-spec.md:430` 已明文写「case 内嵌套块也禁止」，实测 rc=1（E1-7）。A 只缺一个嵌套块负例（现有 `p38_defer_switch.ct` 只有直接 case）。
6. 因此本文反对 B 的**成本与精度声明**，但不为 A 的「现状」背书：A 只有做到「改文档措辞 + 勘误 E37-3 + 补 3 个测试缺口」才成立；否则 A 就是「已知静默段错误 + 文档没写」，本文不支持。

---

## 1 失效条件（本文立场在什么情况下不成立）

本文的 A 主张在下列任一条件成立时**失效**，EDITOR 应据此转向 B 或 C：

| # | 失效条件 | 为什么会使 A 失效 | 可核验方式 |
| --- | --- | --- | --- |
| F-1 | EDITOR 按 J-1 字面解释「任何**被接受**的派发」，且拒绝把「接收者无副作用」写成被接受的前提 | `arr[pick()].area()` 被编译器接受却段错误，J-1 直接红；A 无法自称收口 | 看 verdict 对 J-1 的措辞；本文 E1-2 |
| F-2 | A 的收口只写「接收者不得有副作用」，不写「两次求值结果必须相同/必须是稳定左值」 | `arr[clock() % 2]` 无副作用（C 语义下 `clock` 不改可观察状态）却可能两次不同；文档承诺仍漏一类绕过 | 看 A 的 `docs/language-spec.md:2005` 最终措辞 |
| F-3 | A 不修改 E37-3 或不做勘误/决策记录，却继续引用 E37-3 作为已满足的退出判据 | 已发布 tag `v0.37.0` 的退出判据被事后扩大解释，属隐藏冲突（AGENTS §6.7 冲突处置纪律） | 看 A 的收口提交是否含 `docs/decisions/D-38-*.md` 或 phase37 勘误 |
| F-4 | 用户/项目把 `--runtime-checks` 当作 CI 安全门（要求「不 abort 即安全」）而非调试断言 | A 的残留 rc=139 在 CI 中是 P0；文档不能替代门禁 | 看用户指令 / CI 是否全局开该开关 |
| F-5 | A 不补（a）嵌套 switch defer 负例、（b）side-effect 接收者特征化测试、（c）安全 `arr[0]` 回归 | 边界只写在文档里，行为可无声明地漂移；A 的「接受」没有可执行锚点 | 看 A 收口 diff 的 `test/**` |
| F-6 | B 的实际 diff 证明：≤2 文件、真列号、不误伤 `arr[0]`、warm cache 也拦得住 | 本文对 B 的成本/精度批评全部落空，A 的「B 太贵」论据消失 | 看 B 的实现 diff 与 `Cache.h.ct` |
| F-7 | 存在本文没找到的规范条款，已明确把「带副作用接收者」排除出 E37-3 | A 的最强弱点不成立，A 只是现状收口即可 | 本文已查 E37-3、language-spec、tutorial、README、phase38 §9.1；若另有出处，请 EDITOR 补锚点 |

---

## 2 逐条判据（J-1…J-5）

> 记号：「A 现状」= 不改代码；「A 收口」= A 加上本文要求的文档/测试；「B 预测」= 按 B 的提案文字推演，未见实现。

| 判据 | A 现状 | A 收口（本文主张） | B 预测 | 证据/说明 |
| --- | --- | --- | --- | --- |
| **J-1** E37-3 安全契约：`--runtime-checks` 下任何被接受的 vtable 派发遇空 vtable 必须 abort 且带 `文件:行` | **红**：side.ct build rc=0，run rc=139，stderr 空；guard 检查的是 `arr[pick()]` 第一次求值，调用用第二次求值 | **有条件绿**：必须先把「被接受」定义成「接收者两次求值一致且无副作用」，并勘误 E37-3；否则仍是红 | **预测绿**（对 `N_INDEX` 的 side.ct 会 `file:line:1: error:` 拒绝）；但列号为 1，且 warm cache 可能绕过 | E1-2、E1-6；`phase37-draft.md:156`、`language-spec.md:2005-2006` 均无排除句；`phase38-draft.md:248` 只是收口记录 |
| **J-2** E38-1…E38-8 全绿、corpus/自举不动点 | 绿（A 不动代码；PH-38 收口记录 `check-ast 1328/0` 等） | 绿（只动 docs/test） | 需自成套跑 `check-all.sh`；新增负例要进 `check-ast` 门禁 | A 无源码改动，J-2 风险最低 |
| **J-3** 不新增语法/CLI，off 产物逐字节不变 | 绿（零改动） | 绿（零源码改动） | 字面绿（检查只在 `runtime_checks` 分支）；但**on 时接受集变小**，属语义代价而非 J-3 违规 | E1-8：off 无 guard（`grep -c` = 0），on 有 guard；`Emitter.h.ct:4620` 等四处均在开关内 |
| **J-4** 成本/风险：≤2 文件、无解析器大改、可回滚 | 源码 0；文档 4 处 + 测试 3 处 | 0 源码；约 5–8 文件、30–60 行文档 + 30–60 行测试；可逐条 revert | **不成立**：源码至少 Emitter；真列号要 `Arena`+parser；warm cache 要 `Cache`；再加 fixture/门禁/规范 → 6–9 文件 | E2 锚点、E4；`fail_at` 的 `errcol=1` 见 `ParseSupport.h.ct:133`；`Cache.h.ct:63-80` |
| **J-5** 可诊断、可测试：拒绝必须 `file:line:col: error:`；新负例旧红新绿 | A 无新诊断；测试缺口 3 个 | 补特征化测试与安全回归后，A 的「边界」可测 | 可诊断但**列号是假的 1**（实测 `:21:1`）；真实接收者列要改 AST 列号，成本跳级；新负例可旧红新绿 | E1-6；`Emitter.h.ct:5133-5138` 只存 line；`ParseSupport.h.ct:125-136` 强制 col=1 |

**J-1 的裁决关键**：`question.md` 写的是「任何**被接受**的 vtable 派发」。A 的文档不能改变编译器的接受集（编译器仍然 rc=0 接受 side.ct），只能在**规范层**把这类程序排除出契约。若 EDITOR 认为「被接受」指编译器接受，A **必红**；若 EDITOR 接受「规范前置条件排除」，A 必须同步做 F-3 的勘误。这个二选一不能在 counter.md 里替 EDITOR 决定——故本文不是判决。

---

## 3 E1 命令与原始输出

### E1-1 构建链（证明后续实验用的是 HEAD 源码）

```console
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/counter-a/ctc
$ /tmp/counter-a/ctc selfhost/l1/ctc.ct -o /tmp/counter-a/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/counter-a/l1.c -o /tmp/counter-a/l1
$ /tmp/counter-a/l1 build selfhost/l2/driver.ct -o /tmp/counter-a/l2src
$ cc -Wall -Wextra -std=c99 /tmp/counter-a/l2src/*.c -o /tmp/counter-a/l2
$ /tmp/counter-a/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/counter-a/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/counter-a/astsrc/*.c -o /tmp/counter-a/ct-ast
built
ct-ast v0.37.0
0        # /tmp/counter-a/astb.log 字节数，零警告
```

### E1-2 A 现状：`arr[pick()].area()` 段错误且无 runtime 消息

夹具 `/tmp/counter-a/side.ct`（`arr[0]` 正常、`arr[1]` 清零、`pick()` 第一次返回 0、第二次返回 1）：

```console
$ /tmp/counter-a/ct-ast build --runtime-checks --emit-c /tmp/counter-a/side.ct -o /tmp/counter-a/side-on
rc=0
$ cc -std=c99 /tmp/counter-a/side-on/side.c -o /tmp/counter-a/side-bin
rc=0
$ /tmp/counter-a/side-bin
Segmentation fault: 11
rc=139
stdout: <empty>
stderr: <empty>
```

生成的 guard（**接收者被求值两次**）：

```c
/tmp/counter-a/side-on/side.c:56:
    return ((struct Area_vtbl *)__ct_vt_guard((void *)(arr[pick()]).vt, __FILE__, 28, "area"))->area((arr[pick()]).self);
```

这是 J-1 的直接反例：编译器**接受**了它（rc=0），运行期既没有 abort 也没有 `null vtable` 消息。

### E1-3 安全反例：`arr[0].area()` 在 guard 下正常

```console
$ /tmp/counter-a/ct-ast build --runtime-checks --emit-c /tmp/counter-a/safe_index.ct -o /tmp/counter-a/safe_index-on
rc=0
$ cc -std=c99 /tmp/counter-a/safe_index-on/safe_index.c -o /tmp/counter-a/safe_index-bin
rc=0
$ /tmp/counter-a/safe_index-bin
rc=7
```

```c
/tmp/counter-a/safe_index-on/safe_index.c:46:
    return ((struct Area_vtbl *)__ct_vt_guard((void *)(arr[0]).vt, __FILE__, 17, "area"))->area((arr[0]).self);
```

B 的规则是「接收者种类为 `N_INDEX`」即拒绝，不区分常量下标；`arr[0]` 正是 `N_INDEX`，且**无副作用、今天工作正常**。B 要避免误伤，必须额外做「常量下标豁免」——这不在 B 的 10–30 行描述里。

### E1-4 B 的 `N_CALL` 分支：合法调用接收者已被 hoist 成临时量

```console
$ /tmp/counter-a/ct-ast build --runtime-checks --emit-c /tmp/counter-a/safe_call.ct -o /tmp/counter-a/safe_call-on
rc=0
$ /tmp/counter-a/safe_call-bin
rc=4
```

```c
/tmp/counter-a/safe_call-on/safe_call.c:48:
    int v = ((struct Area_vtbl *)__ct_vt_guard((void *)(__ct_tmp0).__area_vptr, __FILE__, 19, "area"))->area(&(__ct_tmp0));
```

`make(4).area()` 的接收者 `N_CALL` 在发射前已被 Phase 31 的 `hoist_scan` 物化成 `__ct_tmp0`（`Emitter.h.ct:2168-2197`；`text3` 短路在 `Emitter.h.ct:4600-4602`）。因此：

- 若 B 在**发射 guard 的接收者种类**处检查，`N_CALL` 分支对这类合法程序是**死代码**（看到的是临时量，不是 `N_CALL`）；
- 若 B 在 **hoist 之前**（parser/扫描阶段）检查，则会拒掉 `make_lit(4).show()` 这类合法程序（`test/ast/12_rvalue_iface/prog.ct:68` 今天在 `--runtime-checks` 下正常，发射 `__ct_tmp0`）。

B 的提案文字没有说明在哪一层检查，也没有提 hoist 交互；这是实现精度的硬缺口。

### E1-5 现有 corpus 在 `--runtime-checks` 下会命中 B 的 `N_INDEX` 规则

```console
$ /tmp/counter-a/ct-ast build --runtime-checks --emit-c test/ast/10_iface_array/prog.ct -o /tmp/counter-a/c-10_iface_array
# 生成的 prog.c 含：
60:    ((struct Greeter_vtbl *)__ct_vt_guard((void *)(gs[0]).vt, __FILE__, 24, "greet"))->greet((gs[0]).self);
61:    ((struct Greeter_vtbl *)__ct_vt_guard((void *)(gs[1]).vt, __FILE__, 25, "greet"))->greet((gs[1]).self);
```

`test/ast/10_iface_array/prog.ct:24-25` 当前是绿的合法 corpus；B 会把它在 `--runtime-checks` 下拒掉。B 若想「只拒有副作用的」，就必须证明 `arr[0]` 无副作用——这正是它声称不做的别名分析。

### E1-6 B 的列号：`fail_from` 只有行号，`fail_at` 把列号硬编码为 1

```console
$ /tmp/counter-a/ct-ast build /tmp/counter-a/argcall.ct -o /tmp/counter-a/argcall-bin
/tmp/counter-a/argcall.ct:21:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
rc=1
```

`argcall.ct:21` 的真实接收者从第 19 列左右开始，输出却是 `21:1`。源码锚点：`Emitter.h.ct:5133-5138` 的 `fail_from` 只写 `failline`；`ParseSupport.h.ct:125-136` 的 `fail_at` 写死 `errcol = 1`。B 要达到「真实的 `file:line:col`」，必须给 `Node` 加 `col` 并在 parser 全部分配点填值——`Arena.h.ct` + `Parser/Expr/Stmt` 多文件，绝非 ≤2 文件。

### E1-7 switch：嵌套块/循环体已经一律拒绝，且文档已写

```console
$ /tmp/counter-a/ct-ast check /tmp/counter-a/switch_nested.ct
/tmp/counter-a/switch_nested.ct:5:9: error: defer is not allowed inside a switch
ctc: 1 error(s) generated
rc=1

$ /tmp/counter-a/ct-ast check /tmp/counter-a/switch_loop.ct
/tmp/counter-a/switch_loop.ct:7:13: error: defer is not allowed inside a switch
ctc: 1 error(s) generated
rc=1
```

实现锚点：`Stmt.h.ct:1662-1664` 的 `switch_depth > 0` 在进入 `switch` 时递增、只在 `parse_switch_body` 退出时递减（`:2270`、`:2280`、`:2290`、`:2295`），嵌套块/循环体天然继承该深度。规范锚点：`docs/language-spec.md:430` 已经写明「v1 不定义 case/fallthrough 语义，case 内嵌套块也禁止」。
**结论：A 的 switch 半句不需要新实现、也不需要新规范措辞；只缺一个嵌套块负例。**

### E1-8 开关边界：off 无 guard；`--runtime-checks` 只属于 `ct build`

```console
$ grep -c "__ct_vt_guard" /tmp/counter-a/side-off/side.c
0
$ /tmp/counter-a/ct-ast check --runtime-checks /tmp/counter-a/side.ct
ctc: unknown option '--runtime-checks'
rc=1
$ /tmp/counter-a/ct-ast compile --runtime-checks /tmp/counter-a/side.ct -o /tmp/counter-a/side-compile.c
ctc: unknown option '--runtime-checks'
rc=1
```

这既证明 off 产物无注入（J-3 A 侧绿），也说明 B 的诊断**只在 `ct build` 可见**：`ct check` 不认这个开关，不存在「check 应同时报」的额外缺口，但也不要把 B 说成「check/build 一致」。

---

## 4 E2 锚点（file:line，含至少一条不利于 A）

### 4.1 不利于 A 的锚点（A 必须处理）

| 主题 | 位置 | 事实 |
| --- | --- | --- |
| E37-3 原文 | `docs/design/phase37-draft.md:156` | 「`--runtime-checks` 下空接口值派发 abort，stderr 含 `prog.ct:<行>` 与 `null vtable`」——**没有**「接收者不得有副作用」的排除句 |
| 运行期契约 | `docs/language-spec.md:2005-2006` | 「在接口派发前检查 vtable；空则带 `<file>:<line>: runtime check…` abort」——**没有**排除句 |
| 教程 | `docs/tutorial.md:1409` | 同上，仍未排除 |
| README | `README.md:39` | 同上，仍未排除 |
| PH-38 收口记录 | `docs/design/phase38-draft.md:248` | 「guard 下非 hoist 副作用接收者仍按既有两次求值（不新增第三次，但可绕过 guard）；均记录为 v1 边界」——这是**收口记录文字**，不是规范条款，且措辞把它当作既有两次求值的延续，未明确「不得有副作用」 |
| guard 双求值实现 | `selfhost/ct-ast/backend/emit/Emitter.h.ct:4620-4631`（aux 4）、`:4639-4650`（aux 3）、`:4658-4669`（aux 2）、`:4676-4687`（else） | 四个分支各自 `emit_expr(receiver)` 两次；因此 A 的排除不能只写「无副作用」，还要写「两次求值一致/稳定左值」 |
| B 的列号 | `selfhost/ct-ast/backend/emit/Emitter.h.ct:5133-5138`；`frontend/parse/ParseSupport.h.ct:125-136` | `fail_from` 只存 line；`fail_at` 写死 `errcol=1`；J-5 的「col」在现状下是假列号 |

### 4.2 不利于 B 的锚点

| 主题 | 位置 | 事实 |
| --- | --- | --- |
| hoist 交互 | `Emitter.h.ct:2168-2197`；`:4600-4602`；`:2207-2232` | 合法调用接收者被物化成 `__ct_tmp0`，guard 看到的是临时量；`N_CALL` 规则必须说明在哪一层生效 |
| 四路 guard | `Emitter.h.ct:4620/4639/4658/4676` | 只改一路 = 部分覆盖；B 的 10–30 行要覆盖四路或在其前统一 gate |
| 误伤现成 corpus | `test/ast/10_iface_array/prog.ct:24-25` | 常量下标 `gs[0].greet()` 今天在 `--runtime-checks` 下正常 |
| 误伤安全样例 | 本文 E1-3（`safe_index.ct`） | `arr[0].area()` rc=7；B 的 `N_INDEX` 一刀切会拒绝 |
| warm cache | `selfhost/ct-ast/tool/cache/Cache.h.ct:63-80`；`frontend/module/Module.h.ct:1410-1413` | key 只有 version / line_force / diag_json / runtime_checks 等；`runtime_checks=1` 的旧缓存可直接命中，emitter 的拒绝逻辑不会运行。B 不换 key/不 bump version，就能被 warm cache **静默绕过**——与其「不应有静默绕过」的立论直接冲突 |
| 失败清理 | `selfhost/ct-ast/tool/driver/Driver.h.ct:514-521`；`frontend/module/Module.h.ct:1424-1430` | 发射中途失败会 `remove(outc)`，所以 B 不会留下半截 `.c`；这点 B 无额外风险，A 也不应夸大 |
| switch 已实现 | `frontend/parse/Stmt.h.ct:1662-1664`、`:2270-2295`；`docs/language-spec.md:430` | 嵌套块/循环体已拒绝且已文档化；A 只缺负例 |

---

## 5 E3 可证伪预测

> 每条都写明「在什么观察下我错」。EDITOR 可用 B 的 diff 或 A 的收口 diff 直接验。

| # | 预测 | 若被观察推翻，说明 |
| --- | --- | --- |
| P-1 | A 若只改文档、不改代码，`side.ct` 仍 build rc=0 / run rc=139 / stderr 空（与 E1-2 相同） | 如果 A 的「文档化」同时偷偷加了运行时行为，A 就不是「接受边界」而是 B/C 的变体 |
| P-2 | A 的文档若只写「接收者不得有副作用」，`arr[clock() % 2].area()` 之类的**纯但值可变**接收者仍被接受且可绕过 | 若 A 写的是「两次求值结果必须相同 / 必须是变量、字段或常量下标」，此预测错，A 更强 |
| P-3 | B 的实际 diff 会触及 ≥3 个路径（`Emitter.h.ct` + 至少一个负例/门禁 + 至少一处规范/教程），除非 B 放弃 J-5 的负例/文档 | 若 B 的 diff 只有 ≤2 文件且仍满足 J-5，我的成本批评错 |
| P-4 | B 若不改 `Arena`/parser，其诊断列号恒为 `1`（E1-6）；若改，则源码路径 ≥3 | 若 B 用别的机制拿到真列号且只动 ≤2 文件，此预测错 |
| P-5 | B 在 guard 点检查 `N_CALL` 是死代码；在 hoist 前检查则会拒掉 `test/ast/12_rvalue_iface/prog.ct:68` 的合法 `make_lit(4).show()` | 若 B 的 diff 精确绕开 hoist 且不误伤，此预测错，B 的精度比我估计高 |
| P-6 | B 若不在 `Cache.h.ct` 或 `CTC_VERSION` 上做失效，warm cache 下不触发拒绝：先用**旧二进制的 `--runtime-checks`** 为同一源产出一份缓存，再用 B 二进制、同一组 flag 构建同一源，emitter 会被跳过 | 若 B 证明缓存 key 已足以区分「有无 B 检查」，此预测错 |
| P-7 | switch 嵌套块/循环体的拒绝在当前实现已成立（E1-7）；A 只需补负例，不需改解析器 | 若 A 收口需要改 `Stmt.h.ct`，说明当前实现有漏洞，我的「已实现」判断错 |
| P-8 | J-1 的裁决取决于「被接受」的解释：字面解释 A 红；规范前置条件解释 A 可有条件绿 | 若 EDITOR 找到第三条路（例如把 E37-3 降级为「尽力而为」并明确不纳入 J-1），则本文的 J-1 分析需重写 |

---

## 6 E4 代价量化

### 6.1 A 的代价（本文主张的「接受边界」完整版）

| 项 | 内容 | 量 |
| --- | --- | --- |
| 规范正文 | `docs/language-spec.md:2005-2006` 增加前置条件：接收者必须**无副作用且两次求值结果相同**；说明 guard 是**调试断言，不是安全边界** | 1–2 行 |
| 教程/README | `docs/tutorial.md:1409`、`README.md:39` 同一措辞 | 2 行 |
| 历史判据 | `docs/design/phase37-draft.md:156` 的 E37-3 需勘误或由 `docs/decisions/D-38-*.md` 说明「接受集 = 满足前置条件的程序」；不能悄悄扩解释已发布 tag 的退出判据 | 1 条决策记录（~20–40 行） |
| PH-38 收口记录 | `docs/design/phase38-draft.md:248` 的「v1 边界」升级为指向规范的明确条款（现在只是记录） | 2–4 行 |
| 测试缺口 1 | `switch` 嵌套块负例（现有 `test/ast/errors/p38_defer_switch.ct` 只有直接 case；E1-7 已证明嵌套被拒，但无 fixture 锁定） | 1 文件 + `p38_probe.sh` 1 行 |
| 测试缺口 2 | side-effect 接收者的**特征化**测试（记录 rc=139、stderr 空；放 known-limitations 或新 probe），防止行为无声变化 | 1 文件 + 1 断言 |
| 测试缺口 3 | 安全回归：`arr[0].area()` 在 `--runtime-checks` 下仍 rc=7（防止将来修 C 时误伤） | 1 文件/1 断言 |
| 源码 | **0 行** | — |
| 合计 | 0 源码；约 5–8 文件；文档 20–40 行 + 测试 40–80 行；可逐项 revert | 0.5–1 人日（含勘误审批） |

**A 的残余风险**：
- 接受 side.ct 这类程序 = 接受一次「已知的静默段错误」；文档是唯一防线。
- 若文档措辞不精确（F-2），边界仍漏；若不做 F-3，E37-3 与规范冲突。
- 用户可能把 `--runtime-checks` 当安全门（F-4），文档无法阻止误用。

### 6.2 B 的代价（按提案文字 + 现有基础设施推算）

| 项 | 内容 | 量 |
| --- | --- | --- |
| 源码 1 | `Emitter.h.ct`：在 4 个 aux guard 分支之前/之内加接收者检查；处理 hoist 临时量；常量下标豁免（否则误伤 `arr[0]`） | 20–50 行，1 文件 |
| 源码 2 | 真列号：`Arena.h.ct` 的 `Node` 加 `col`，parser 每个 `new_node` 填列（或至少方法调用接收者链） | 多文件，远超 2 |
| 源码 3 | warm cache：`Cache.h.ct` key 加策略位或 bump `CTC_VERSION`；后者还要同步 5 处版本落点 + golden（AGENTS §6.7） | 1–6 文件 |
| 测试 | 新负例（`errors/p38_rt_receiver.ct` 或类似）+ probe 接入 + 旧实现红证 | 2–3 文件 |
| 文档 | language-spec 诊断表 + tutorial + L38 台账（新文案要编号） | 2–3 处 |
| 合计 | 若只做「Emitter 一刀切」：1 源码 + 2–3 测试/文档 = 3–4 文件；若补真列号与缓存：6–9 文件 | 1–2 人日 |
| 行为代价 | `--runtime-checks` 下拒绝 `arr[0].area()`、`gs[0].greet()` 等合法程序；用户需改写为局部绑定；CI 全局开该开关会红 | 迁移成本 |
| off 风险 | 低：检查在 `runtime_checks` 分支内即可保持 off 逐字节不变；发射失败已有 `remove` 清理（E2） | 近零 |

**对比**：B 的「10–30 行、≤2 文件」只在**同时砍掉**（a）真列号、（b）warm cache、（c）测试/规范时成立；而这三项每一项被砍都直接削弱 B 自己的「安全契约不应有静默绕过」立论。A 的 0 源码 + 5–8 文件主要是文档/测试，且不改变接受集；从「本 phase 收口」的交付风险看，A 更小。

---

## 7 E5 对 B 最强论点的 steelman 与回应

### 7.1 B 的最强论点（steelman）

> `--runtime-checks` 是一个**安全开关**。用户打开它，就是要求「空 vtable 不会静默段错误」。现在编译器**明明能在发射期识别** `N_INDEX`/`N_CALL` 这类的接收者，却选择放行并让它在运行期段错误——这不是「文档没写」，而是「编译器知道危险却不拦」。安全契约不能靠用户读文档来兑现；静默绕过一次，开关的信誉就没了。B 用一条 `file:line:col` 诊断把危险挡在编译期，成本低、可回滚、off 产物不变，是典型的「便宜的正确」。

这个论点很强，本文承认：
- A 现状确实让一个**编译器可识别**的危险类静默通过；文档不是执行机制。
- B 的方向（在编译期拒绝不确定的接收者）在原则上是正确的，且比 C 便宜。
- 若用户明确把 `--runtime-checks` 当 CI 安全门，A 的残留段错误不可接受（F-4）。

### 7.2 回应（不靠贬低 B，而靠指出 B 的「正确」不完整）

1. **B 不是 sound，只是更窄的 partial check。** 它按接收者**语法种类**拒绝，不做别名/副作用分析：`arr[i]`（非常量 i）被拒，但 `arr[0]` 被放行；接收者是变量时也放行，而变量在两次求值之间被信号/其它线程改写时同样不在 B 的覆盖内（B 只处理 `N_INDEX`/`N_CALL`）。更关键的是 warm cache：`Cache.h.ct:63-80` 的 key 不含「B 策略」，旧缓存会直接跳过 emitter，B 的拒绝逻辑根本不运行（P-6）。一个能被缓存静默绕过的「安全契约」，和 A 的文档一样需要前提；差别只是前提换成了「冷构建」。
2. **B 的 `N_CALL` 分支与 hoist 冲突。** 合法的 `make_lit(4).show()` 在 guard 点已经是 `__ct_tmp0`（E1-4）；B 要么写死代码，要么在 hoist 前误伤合法程序。B 的提案没有处理这个交互，说明其「10–30 行」估算没有覆盖真实发射路径。
3. **B 的列号是假的。** 要实现 J-5 的 `file:line:col`，B 必须给 AST 加列号（`Arena` + parser），这不是 ≤2 文件；若接受 `:1`，那 J-5 的「col」只剩形式，和 A 的「文档承诺」一样是名义满足。
4. **B 会改变接受集，而 A 不。** `--runtime-checks` 从「加断言」变成「加限制」：`gs[0].greet()`、`arr[0].area()` 这些今天合法的程序在开关下变红（E1-3/E1-5）。这不是 J-3 违规（J-3 只要求 off 不变），但它是**用户可见的语义变更**，需要迁移说明和版本策略；A 的接受集不变，代价集中在文档。
5. **真正的完整修复是 C，不是 B。** C 把接收者物化一次，guard 与被调对象天然一致，既不需要拒绝合法程序，也不需要假列号；B 是在 C 之前用「拒绝」换「安全」，但如果只做 B，将来 C 落地时这些拒绝规则还要拆掉（或保留为更保守的超集）。从工程路径看，A（明确边界 + 文档 + 测试）→ C（下一 phase 物化）比 A→B→C 少一次中间态和一次迁移。
6. **因此本文的立场不是「B 错」，而是「B 在 J-4 上被低估、在 J-5 上被高估，且没有解决它声称解决的静默绕过」**。如果 EDITOR 认为 F-1（J-1 字面）成立，B 仍是比 A 现状好的选择——但那时应要求 B 补齐 cache/列号/hoist 三项，成本接近 C 的低端；本文的 A 主张只在「接受边界 + 勘误 + 测试」被完整执行时成立。

---

## 8 对 A 的明确要求（若 EDITOR 选 A，必须一并落盘）

1. `docs/language-spec.md:2005-2006` 写清：guard 只在接收者**无副作用且两次求值结果相同**时有效；它是**调试断言，不是安全/并发保证**；带副作用接收者必须先绑定局部。
2. `docs/tutorial.md:1409`、`README.md:39` 同步同一句，避免三处口径不一。
3. 用 `docs/decisions/D-38-*.md`（或 phase37 勘误）处理 E37-3 的「任何被接受」：明确「被接受」= 满足前置条件；不静默扩解释已发布 `v0.37.0` 的退出判据。
4. `docs/design/phase38-draft.md:248` 的「v1 边界」改为指向上述规范条款，而不是只在收口记录里提一句。
5. 补 3 个测试缺口（见 §6.1）：嵌套 switch defer 负例、side-effect 接收者特征化、`arr[0]` 安全回归。
6. 在收口报告里明说：**A 接受一次已知静默段错误**；若用户要求「开关即安全」，A 不成立，转 B/C。

以上 6 项不做，A 就是「现状 + 口头边界」，本文不支持。

---

## 9 本文未做的事 / 局限

- 未实现 B 的补丁（禁止改源码），因此 B 的行为是**按代码结构推演**，不是实测；E3 已把每条推演写成可证伪预测。
- 未跑全量 `check-all.sh`（20 分钟预算内不必要；A 不动源码，B 未实现）。
- 未穷举所有接收者 AST 种类；已核对 `Emitter.h.ct:4605-4609` 允许的六类（`N_VAR/N_INDEX/N_CALL/N_MEMBER/N_ARROW/N_INTO*`），B 只提 `N_INDEX/N_CALL`，其余种类的 guard 双求值风险本文未展开。
- 未验证 `arr[clock() % 2]` 的实际双求值差异（时钟粒度可能让两次相同）；P-2 是**语义可能性**论证，不是实测崩溃。A 的正确措辞应写成「两次求值结果必须相同」，而不是依赖本文的实测。
- 本文不构成判决；J-1 的「被接受」解释权在 EDITOR。
