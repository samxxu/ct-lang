# PH-82 收口复核（REV · 2026-11-21）

> 命名注记（LANG-24 Stage A）：本文件是历史快照，正文保留当时的 `box<T>` 拼写；v1.0 起规范拼写为 `Box<T>`（见 docs/language-spec.md §1.2）。


| 项 | 值 |
| --- | --- |
| 复核对象 | `d80c2418`（`v0.82.0`，tag `v0.82.0`） |
| 范围 | `leaks` 两档、`box<X>` 直接环（限深 3 / 去重 / 仅 box）、`allow-cycle`、树模式；E82-1…8、D-012、battle leak-guards-1；版本 / tag / G8 / check-all / sanitizer |
| 方法 | `git archive v0.82.0` → 独立自举 L0→L1→L2→ct-ast（不读工作树产物）；跑 p82 五个探针与 p81/p80 关键探针；读码对照卡 / D-012 / battle；REV 自建正负例；T-7 红基线复跑；回滚演练；`g0` / `g8` / `check-docs` / `check-all` / `check-sanitizers` |
| 结论 | **REV: 通过**（E82-1…8 均通过；§6 为不阻断观察） |
| 交付 | 本文件；不改代码、不 push；无 PH-82 issue 状态变更 |

## 1 独立自举（archive，不依赖工作树产物）

```console
$ git archive v0.82.0 | tar -x -C /tmp/p82-rev && cd /tmp/p82-rev
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc0
$ ./ctc0 selfhost/l1/ctc.ct -o l1.c
$ cc -Wall -Wextra -std=c99 l1.c -o l1
$ ./l1 build selfhost/l2/driver.ct -o l2src
$ cc -Wall -Wextra -std=c99 l2src/*.c -o l2
$ ./l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o astsrc
$ cc -Wall -Wextra -std=c99 astsrc/*.c -o ct-ast
$ ./ct-ast --version
ct-ast v0.82.0
```

七步退出码全 0，四次 C 编译 `-Wall -Wextra` 无告警（日志 `/tmp/p82-rev/{l0,l1,l1b,l2,l2b,astb}.log`）。

## 2 p82 探针（同一 archive 构建）

```console
$ for f in p82_config p82_cycle p82_allow p82_errors p82_docs; do
    sh test/ast/$f.sh /tmp/p82-rev/ct-ast; echo "exit=$?"; done
ok   no manifest: default warn, compile exits 0 and writes the C
ok   leaks = warn: build exits 0, warning, product written
ok   old manifest (no leaks key): unchanged warning, exit 0
ok   leaks = error: build exits 1 with error: on the same record
ok   leaks = error: no .c product is written
ok   compile: error package fails before writing the C (no -I needed)
ok   JSON: leaks = error record carries "severity":"error"
ok   JSON: warn package keeps the pre-PH-82 shape
ok   c-boundary: leaks = error alone does not make the package strict
ok   c-boundary: an explicit c-boundary = strict still wins
ok   leaks = error: a clean unit still exits 0 with no findings
ok   leaks = error: a clean build still succeeds
ok   leaks = error does not escalate arity (still a warning, exit 0)
p82_config: OK
exit=0
ok   self loop C -> C is reported as a warning
ok   A -> B -> A is reported once (duplicate payload field is one edge)
ok   A -> B -> C -> A is reported (depth limit 3)
ok   a four-edge ring is not reported (limit is 3 edges)
ok   a one-way chain (D -> A -> B) is not reported
ok   a plain pointer field is not a box edge
ok   wording says may leak unless broken by hand, never will leak
ok   ct check: potential_cycle JSON carries severity error and col
ok   ct check: text finding is file:line:col: error:
ok   leaks = warn: build exits 0 and writes the product
ok   leaks = error: build exits 1 with error: on the cycle
ok   leaks = error: no .c product is written
ok   corpus: exactly one finding, the deliberate p81_box/cycle.ct self loop
p82_cycle: OK
exit=0
ok   same-line marker suppresses the tree pattern's self loop
ok   removing the marker brings the warning back
ok   a marker on the line above the struct does not suppress
ok   a marker on a field line does not suppress
ok   a marker on one participant suppresses A -> B -> A
ok   a marker on an unrelated struct does not suppress
ok   ct check: reports the suppressed point as a note and exits 0
ok   ct compile: a suppressed cycle produces no note
ok   leaks = error: a suppressed cycle does not fail the build
ok   leaks = error: removing the marker makes the build fail again
p82_allow: OK
exit=0
ok   vec: no cycle warning
ok   generic: no cycle warning
ok   geninst: no cycle warning
ok   iface: no cycle warning
ok   alias: no cycle warning
ok   indirect: no cycle warning
ok   container_ring: no cycle warning
ok   corpus test/ast/05_struct/prog.ct: no cycle warning
ok   corpus test/patterns/composite/prog.ct: no cycle warning
ok   corpus test/patterns/decorator/prog.ct: no cycle warning
ok   box corpus: exactly one finding, the deliberate p81_box/cycle.ct self loop
p82_errors: OK
exit=0
ok   five CTC_VERSION = 0.82.0; README/docs/README carry v0.82.0
ok   roadmap Phase 82 done; spec §4.72 (leaks/allow-cycle/3 条边/可能泄漏/
     c-boundary/--debug-leaks); package-guide leaks 行; patterns §5 tree
ok   card §7 + E82-1…8 rows + closeout status; --debug-leaks still unknown
p82_docs: OK (30 assertions)
exit=0
```

断言数：`p82_config` 13、`p82_cycle` 13、`p82_allow` 10、`p82_errors` 11、`p82_docs` 30（§2 节选 3 组，完整列表在 `test/ast/p82_docs.sh`），均与卡 §5 / §6 一致。

## 3 不回归（p81 / p80）

```console
$ sh test/ast/p81_box.sh /tmp/p82-rev/ct-ast   → p81_box: OK (40 断言，含 ASan/UBSan)
$ sh test/ast/p80_docs.sh /tmp/p82-rev/ct-ast  → p80_docs: OK (27 断言)
$ sh test/ast/p80_layout.sh /tmp/p82-rev/ct-ast→ p80_layout: OK (7 断言，含 ASan 灵敏度)
$ sh test/ast/p80_cstr.sh /tmp/p82-rev/ct-ast  → p80_cstr: OK (4 断言)
```

`check-all` 内 `p80_layout/literal/methods/cstr/migrate/docs/retain` 与 `p81_box` 全 `ok`（原文见 §5）。

## 4 E82-1…8 逐条

| ID | 结论 | 独立证据 |
| --- | --- | --- |
| E82-1 | **通过** | `p82_config`：无 manifest / `leaks = warn` / 旧 manifest 三路均 `warning:` + exit 0 + 产物；`leaks = error` 同一条记录变 `error:`；`ct pkg` 的 manifest 解析把 `leaks` 收进已知键（读码 + 03012a3a diff） |
| E82-2 | **通过** | `p82_config`：error 包 build/compile 均 exit 1 且不落 `.c`；`leaks = error` 单独 `--show-c-boundary` = `allow`，显式 `c-boundary = strict` 仍 `strict`；REV 反例 CE-1/CE-2 见 §5 |
| E82-3 | **通过** | `p82_cycle`：`C -> C`、`A -> B -> A`（双载荷 1 条）、`A -> B -> C -> A`；4 边环 / 单向链 / 裸指针不报；CE-4 补测反向定义顺序、双端重复字段、2+3 环共存 |
| E82-4 | **通过** | `p82_errors`：7 条形状负例 + 3 条结构语料 + 全 `box<` 语料唯一命中 `p81_box/cycle.ct`；CE-4 的 `Vec<A> + A *` 不报 |
| E82-5 | **通过** | `p82_allow`：同行抑制、移除复报、上一行/字段行不抑制、任一参与者抑制；`ct check` 打 `note:` 且 exit 0，compile 静默；CE-5 补测 3 环第 2/第 3 参与者 |
| E82-6 | **通过** | `p82_cycle`：文案含 `may leak unless the cycle is broken by hand`、无 `will leak`；spec §4.72 记「可能泄漏，除非手工破环」、「不写「会泄漏」」；`--debug-leaks` 实测 `unknown option`，未改称环检测 |
| E82-7 | **通过** | `p82_docs`：spec §4.72（leaks / allow-cycle / 3 条边 / 可能泄漏 / c-boundary / `--debug-leaks` / §4.72）、package-guide §2 `leaks` 行、patterns §5 树模式、memory-guide §11；读文核对语义一致 |
| E82-8 | **通过** | 51 个 golden/expected（含 p39 ABI banner）仅版本 token 变化 + p80_docs/p81_box 跟版本；`check-all` 11 门绿；回滚演练见 §5（8 个 phase 提交全退 → 与 `bf558eb7` 零 diff） |

## 5 REV 自建反例与独立门禁

CE-1（`leaks = error` 只升泄漏类，不污染其他告警；目录 `/tmp/rev82/ceA`，`ct.pkg` 含 `leaks = error`）：

```console
$ ct-ast compile --allow-c-boundary ceA.ct -o ceA.c
ceA.ct:4: warning: a borrowed pointer escapes through 'return'      # kind 3
ceA.ct:9: warning: arity mismatch: 'add' takes 2 argument(s), 1 given # kind 4
$ echo $?; ls -l ceA.c
0
-rw-r--r--  459 ceA.c
```

CE-2（kind 2「return path」leak 在 error 包升级；`/tmp/rev82/ceD`）：

```console
$ ct-ast build -I . --emit-c -o out prog.ct      # leaks = error
prog.ct:7: error: potential leak: 'p' (S*) may leak on a return path (line 10)
$ echo $?; ls out/*.c
1
ls: out/*.c: No such file or directory
$ ct-ast build -I . --emit-c -o out prog.ct      # leaks = warn 对照
prog.ct:7: warning: potential leak: 'p' (S*) may leak on a return path (line 10)
exit 0，out/prog.c 已写
```

CE-3（被抑制环 + 真泄漏：只升真泄漏，`ct check` 仍报抑制点；`/tmp/rev82/ceC`）：

```console
$ ct-ast build -I . --emit-c -o out prog.ct      # Node 自环带 allow-cycle + p 未释放
prog.ct:9: error: potential leak: 'p' (S*) allocated but never deleted
exit 1，无产物（被抑制的 Node -> Node 不出现在 compile/build 日志）
$ ct-ast check --allow-c-boundary prog.ct
prog.ct:1:1: note: reference cycle suppressed by 'ct: allow-cycle': Node -> Node
prog.ct:9: error: potential leak: 'p' (S*) allocated but never deleted
exit 1
```

CE-4（去重 / 顺序 / 边界；`/tmp/rev82/ceF`）：

```console
$ ct-ast compile --allow-c-boundary order3.ct   # C→B→A→C，定义顺序反转
order3.ct:1: warning: potential reference cycle: C -> B -> A -> C; ...   # 1 条
$ ct-ast compile --allow-c-boundary order2.ct   # B 先定义
order2.ct:1: warning: potential reference cycle: B -> A -> B; ...         # 1 条
$ ct-ast compile --allow-c-boundary dupboth.ct  # 两端各两条重复字段
dupboth.ct:1: warning: potential reference cycle: A -> B -> A; ...       # 1 条
$ ct-ast compile --allow-c-boundary nocycle.ct  # Vec<A> + A * 回边
exit 0，0 条
$ ct-ast compile --allow-c-boundary selfdup.ct  # box<S> a; box<S> b;
selfdup.ct:1: warning: potential reference cycle: S -> S; ...            # 1 条
$ ct-ast compile --allow-c-boundary threedup.ct # 每边重复两次的 3 环
threedup.ct:1: warning: potential reference cycle: A -> B -> C -> A; ... # 1 条
$ ct-ast compile --allow-c-boundary s1.ct       # A↔B 与 A→B→C→A 共存
s1.ct:1: warning: potential reference cycle: A -> B -> A; ...           # 2 条
s1.ct:1: warning: potential reference cycle: A -> B -> C -> A; ...
$ ct-ast compile --allow-c-boundary s2.ct       # A↔B 与 4 边环
s2.ct:1: warning: potential reference cycle: A -> B -> A; ...           # 仅 1 条，4 边环不报
```

CE-5（3 环第 2/第 3 参与者上的标记；`/tmp/rev82/ceE`）：

```console
$ ct-ast check --allow-c-boundary p1.ct   # 标记在 B
p1.ct:2:1: note: reference cycle suppressed by 'ct: allow-cycle': A -> B -> C -> A
exit 0
$ ct-ast check --allow-c-boundary p2.ct   # 标记在 C
p2.ct:3:1: note: reference cycle suppressed by 'ct: allow-cycle': A -> B -> C -> A
exit 0
$ ct-ast check --allow-c-boundary p1.ct   # ct.pkg = leaks = error，仍 exit 0
p1.ct:2:1: note: reference cycle suppressed by 'ct: allow-cycle': A -> B -> C -> A
exit 0
```

CE-6（跨单元环，`ct build` 两单元；`/tmp/rev82/cross`）：`a.ct` 的 `pub struct A { box<B> b; }` 与 `b.ct` 的
`pub struct B { box<A> a; }` 在同一包内被检测到，`leaks = error` 下构建 exit 1；卡 §7.4 说「跨单元转手不报」，
实际检测更宽（§6 第 6 条）。

CE-7（`ns-root` 包根清单不可达；`/tmp/rev82/ns`，`pkg/ct.pkg` 含 `leaks = error; ns-root = src`）：

```console
$ ct-ast build --ns-root pkg -I pkg/src --emit-c -o out pkg/src/main.ct
pkg/src/main.ct:3: warning: potential leak: 'p' (S*) allocated but never deleted
cc -std=c99 -I out out/main.c -o a.out
exit 0，out/main.c 已写
$ cp pkg/ct.pkg pkg/src/ct.pkg   # 把清单放到 -I 根再跑
pkg/src/main.ct:3: error: potential leak: 'p' (S*) allocated but never deleted
exit 1，无产物
```

版本 / tag / 门禁（archive 与工作树只读复核）：

```console
$ git cat-file -t v0.82.0; git rev-parse v0.82.0^{commit}
tag
d80c2418c0376ad7467a5416c1d231fb62155743
$ git for-each-ref refs/tags/v0.82.0 --format='%(taggername) %(subject)'
Sam X. Xu@macMini PH-82 closeout (d80c241)
$ git ls-remote origin 'refs/tags/v0.82.0*'
189e4469...  refs/tags/v0.82.0
d80c2418...  refs/tags/v0.82.0^{}     # 远端 annotated tag 解引用到收口提交
$ bash tools/check.sh g0   → g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8   → g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2185 links / 361 files, v0.82.0, 11 hard gates, 12 phase status, 7 signoff)
$ bash selfhost/check-all.sh
  ok    PH-82-S82a…S82d 五条
  == summary: 156 passed, 0 failed ==          # L0
  == summary: 153 passed, 0 failed ==          # check-archive
  == summary: 1545 passed, 0 failed, 4 skipped ==  # AST
  == summary: 20 pass, 0 new, 0 pending, 0 regression ==  # acceptance（仅报告）
  check-warnings: 490 ok, 0 failed
check-all: OK (11 hard gates green)            # exit 0
$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (583 checks, no sanitizer report)   # exit 0
```

T-7 红基线独立复跑（baseline 用 `git archive` 重建，测试脚本取红提交；均如预期红）：

```console
$ # S82a: baseline bf558eb7 / red 1d36a8b1 → p82_config exit 1（error 包/JSON/compile 断言失败）
$ # S82b: baseline 03012a3a / red 93e4fc67 → p82_cycle exit 1（self/two/three/wording/check 失败）
$ # S82c: baseline 42242e8e / red b1097f23 → p82_allow exit 1（tree/partner/check/compile/error 失败）
```

父提交链逐一核对：`1d36a8b1←bf558eb7`、`03012a3a←1d36a8b1`、`93e4fc67←03012a3a`、`42242e8e←93e4fc67`、
`b1097f23←42242e8e`、`aa18772e←b1097f23`、`5526a1d2←aa18772e`、`d80c2418←5526a1d2`；T-7 成立。

回滚演练（临时克隆，反序 revert 全部 8 个 phase 提交）：`git diff bf558eb7` 行数为 0，即整卡回退后
与开工前提交逐字节一致；未在回退树上重跑门禁（树相同于已知基线，见 §7）。

golden 范围：`git diff --diff-filter=M --name-only v0.81.0 v0.82.0 -- test/` 共 53 个——51 个
golden/expected/ABI banner（非 `.sh`）+ `p80_docs.sh`/`p81_box.sh`；非版本 token 的差异行只有这两个脚本
里的 `v0.8[12].0` 字符串，无行为差异。

## 6 不阻断观察

1. **`ns-root` 包根清单读不到（最重要，PH-83 前必须处理）**：消费者拿到的 `-I` 是
   `<版本>/<ns-root>`，`ct.pkg` 在它上一级；`leaks_for` 只读 `-I` 根与入口单元目录，不向上找包根，
   于是 `ns-root = src` 的包写 `leaks = error` 也不会生效（CE-7：`warning` + exit 0 + 落产物）。
   建议在 PH-83 的包 v1 契约落地前修 `leaks_for`（按 `--ns-root`/包根解析），或另立 SH 条目；
   当前 `ns-root = .` 的存量布局不受影响，故不阻断 PH-82。
2. **spec §4.72「`-I` 根的 manifest（无则入口单元目录）」措辞偏宽**：实测当 `-I` 根存在但无
   `ct.pkg` 时直接回到 `warn`，不会再用入口单元目录（`/tmp/rev82/ceI`：`project/src/ct.pkg`
   `leaks = error`，`-I project` 构建 exit 0 + `warning`）。代码与本条注释的意图是「build 看 `-I` 根，
   compile/check 因忽略 `-I` 才回退」；建议把 spec 改成同一口径，避免读者按字面期待回退。
3. **PH-81 既有 `box<T>` 编码碰撞（非 PH-82 引入）**：同一 `box<X>` 在 X 定义前、后各出现一次时，
   `box<B>`（前向）与 `box<B>`（已定义）被当成两个不同实参，报
   `two type arguments encode to the same C name 'box_B'`。最小复现（v0.81.0 与 v0.82.0 同报，故不是本卡回归）：
   `struct A { box<B> b; } struct B { int n; } struct C { box<B> b2; }`。
   它会让部分合法环图无法编译（不是静默漏报）；建议另立 SH 条目（比较 `ct_type_canon` 后的实参）。
4. **`p82_docs` 的 `spec mentions 会泄漏` 是正串检查**：spec 命中是因为写了「不写「会泄漏」」，
   若将来把「不写」删掉仍会绿；行为侧负例由 `p82_cycle` 的 `! grep "will leak"` 覆盖，E82-6 实质满足，
   建议把断言收紧为「含『不写「会泄漏」』」。
5. **S82d 的 `no-test` 签收角色**：卡 §2 要求「由 REVIEW 签字」，§5 与 `5526a1d2` 提交正文记的是
   `签收: EDITOR 2026-11-21`（单会话偏离下的统一签收）；两处口径不一致，属流程文字问题，不阻断。
6. **卡 §7.4 低估跨单元检测**：卡写「跨单元转手的环不报」，实测同一包内两单元的
   `A { box<B> }` / `B { box<A> }` 会被检测（CE-6）。实现比文档宽，建议改卡为「跨单元直接环可检」。
7. **「最小行号 struct」与实现**：卡 §7.4 / spec §4.72 写「行号最小」，代码按 struct 行号（row）最小；
   单单元内二者一致，多单元时行号不可跨文件比较，属措辞小瑕。
8. **tag message 用 `PH-82` 而非 `v0-PH-82`**：与 `v0.81.0` 的 `PH-81 closeout` 先例一致，
   phase-ID 迁移仍被 blocker 挡住、`g8` 接受；不是 PH-82 缺口。

## 7 未覆盖 / 范围外

- 回滚演练只做「整卡 8 提交反序 revert 后与 `bf558eb7` 零 diff」，未在回退树上重跑 11 门（树与开工前一致）。
- 限深 3 以上的环、运行期环/GC/weak、`--debug-leaks` 计数均为 D-012 明示范围外。
- `ns-root` 包的 v1 契约归 PH-83（D-014）；本轮只验证 PH-82 声明的 `-I` 根/单元目录路径。
- 未验证 32 位平台上的 `box` 布局；E82 不含此判据。
- `tools/check.sh` 仍只有 `g0`/`g8`/`battle-selftest`，G1/G4/G6 缺位是既有治理缺口（`full-review-v0.77.0` 已登记），不属 PH-82。

## 8 结论与交付

**REV: 通过。** E82-1…8 均有从 `v0.82.0` archive 自举得到的独立原始输出；`leaks` 两档、`error` 的窄升级、
直接环（自环/2/3 边、限深、去重、仅 `box<X>`）、`allow-cycle` 同行豁免与 `ct check` 抑制点、文案、
`patterns` 树模式、旧 golden 与回滚均经独立复现。版本五处一致、annotated tag 指向收口提交且远端一致、
`g0`/`g8`/`check-docs`/`check-all`（11 门）/`check-sanitizers`（583 项）全绿。§6 的 8 条均为不阻断观察，
其中第 1 条（`ns-root` 包根清单）建议在 PH-83 前处理并另立条目，第 3 条是 PH-81 既有 `box<T>` 编码缺陷，
均不据此回退 PH-82。本轮不改代码、不 push、无 PH-82 issue 状态变更。
