# battle/typecheck-1 · 反证书（反对席 REVIEW，主张 B：增量 opt-in）

| 字段 | 值 |
| --- | --- |
| 主张 B | 编译路径保持现状；先扩 `ct check` 的 opt-in 类型/语义检查，分 4 相推进，稳定后再议进编译路径 |
| 基线 | `ed172075`（v0.65.1，Phase 66 已收口） |
| 环境 | Darwin arm64；Apple clang 21.0.0；`/tmp/tc1/ct-ast` 由 HEAD 自举链 L0→L1→L2→ct-ast 重建，`ct-ast v0.65.1`（sha256 前缀 `114357b05dae43d9`） |
| 结论 | B 胜出；A 的“1.0 前大爆炸”不成立；B 的成立条件与失效条件见 §7 |
## 1. B 的分相（每相独立交付、独立回退）

| 相 | 范围 | 独立验收（命令/阈值） | 编译器 LOC | 回退 |
| --- | --- | --- | --- | --- |
| B1 类型核心 | `chk_type` 扩到二元/一元/三目/cast/compound/`sizeof`、字面量类别；四个位置（初值/赋值/`return`/容器实参）统一指针基类型与层数；显式 skip 表（数组、fnptr、void、宏）；修 `char s[]="x"` 误报 | `ct check --types` 在合法单单元语料 0 误报；12 个 `check_errors` 仍为 error；`git diff` 无 golden | 250–400 | 关 `types_mode` 或 revert 该相提交 |
| B2 调用/generic/trait/跨单元 | `ct check` 复用 build 单元图但止于发射前；跨单元签名、泛型绑定替换、trait bound；`.h.ct` 可见性 | 41 个含 `import` 的输入可检查（合法件 rc=0）；不写 `.c/.h`；`ct build`/`compile` 输出逐字节不变 | 400–700 | 同上 |
| B3 CFG/定值/return/switch | 函数内 CFG、定值/初始化、return 路径、switch 覆盖、不可达；复用既有 return/switch 诊断 | 探针矩阵（goto 跨声明/缺 return/switch 漏分支）逐条 error；合法语料 0 误报；`--semantics` opt-in | 1,500–2,500 | 同上 |
| B4 own/borrow/Drop + 包级 strict | 扩现有 AutoDrop/leak 台账：重复 release、use-after-delete、Drop 完整、`borrow` 经一层调用的写入摘要；包级 strict | own/borrow 夹具全绿；ASAN 干净；0 误报；**不承诺完整借用检查** | 500–1,000 | 同上 |

相门禁（每相相同）：合法语料误报 = 0、skip 清单只减不增、旧语料产物与 golden 零变化、关闭开关即回到 HEAD 行为。
四相全部通过后再讨论编译路径，且**逐相接**（先 B1 的四个位置硬错，再 B3，再 B4），不是一次全接。

## 2. 现有基线（E1，原始输出）
三处粗检与默认路径的窗口；`ct compile` 写出 `cc` 拒收的 C：

```console
$ /tmp/tc1/ct-ast check --types test/ast/check_errors/check_init_ptr.ct 2>&1; echo rc=$?
test/ast/check_errors/check_init_ptr.ct:3:13: error: initializer: expected 'int', got 'char *'
rc=1
$ /tmp/tc1/ct-ast check test/ast/check_errors/check_init_ptr.ct 2>&1; echo rc=$?
rc=0
$ /tmp/tc1/ct-ast build test/ast/check_errors/check_init_ptr.ct -o /tmp/tc1/ipbuild 2>&1 | tail -4; echo rc=${PIPESTATUS[0]}
test/ast/check_errors/check_init_ptr.ct:7:9: error: incompatible pointer to integer conversion initializing 'int' with an expression of type 'char[2]' [-Wint-conversion]
    7 |     int x = "s";
      |         ^   ~~~
1 error generated.
rc=1
```
**B 的不利证据 1（误报）**：合法、`ct build` 全绿的形态在 `--types` 下被误报；最小复现如下（在 `/tmp/tc1/cases` 下执行，`array_str_init.ct` 为新建文件）：

```console
$ cat array_str_init.ct
int main(void) {
    char s[] = "x";
    return s[0] - 'x';
}
$ /tmp/tc1/ct-ast check --types array_str_init.ct 2>&1; echo rc=$?
array_str_init.ct:2:16: error: initializer: expected 'char', got 'char *'
rc=1
$ /tmp/tc1/ct-ast check array_str_init.ct 2>&1; echo rc=$?
rc=0
$ /tmp/tc1/ct-ast array_str_init.ct -o as.c 2>&1; echo rc=$?; cc -std=c99 as.c -o as && ./as; echo run_rc=$?
rc=0
run_rc=0
```

对应语料夹具 `test/ast/234_err_return_contract/prog.ct`：`ct build` 通过、运行输出 `3 x`，`check --types` 却在
`:9:23` 报 `initializer: expected 'char', got 'char *'`。规范 §4.53（`language-spec.md:2488`）明写数组应静默，
这是“规范已承诺、实现未兑现”，不是新特性。
**B 的不利证据 2（覆盖不足）**：`ct check` 只吃单单元；含 `import` 的入口直接拒绝：

```console
$ /tmp/tc1/ct-ast check examples/08_map_binding/src/main.ct 2>&1; echo rc=$?
examples/08_map_binding/src/main.ct:14:1: error: 'import' requires multi-file mode: use 'ct build' (ct check is single-unit)
rc=1
```
**B 的不利证据 3（使用者不跑 check）**：`ct check` 不在编译路径，CI 的 gate 10 只跑 Phase 19 的四类检查
（`check-semantics.sh`），`--types` 只在 `check-ast.sh` 的 p32 夹具上跑，没有对全语料的例行扫描。

**E1 扫描（HEAD，`ct-ast v0.65.1`；在仓库根执行）**：`test/` 下 1851 个文件、495 个 `*.expected.*`；扫描的 289 个 `test/ast/*/prog.ct` + 216 个 `examples/**/*.ct` + 25 个 `test/cases/*.ct`
共 530 个 `.ct`：262+175 = 437 通过，41 个含 `import` 无法单单元检查，52 个失败。52 个失败里 51 个 plain check
也失败（loop_shadow、loop count、负例/诊断样例），`--types` 独有失败恰好 1 个：
```console
$ for f in $(find test/ast -maxdepth 2 -name prog.ct) $(find examples test/cases -name '*.ct'); do
    grep -q '^import ' "$f" && continue
    /tmp/tc1/ct-ast check --types "$f" >/dev/null 2>&1 || { /tmp/tc1/ct-ast check "$f" >/dev/null 2>&1 && echo "TYPES_ONLY $f"; }
  done
TYPES_ONLY test/ast/234_err_return_contract/prog.ct
```

故合法可检 438 个中误报 1 个（0.23%）。C 超集兼容要求这些合法 C 惯例（数组字符串初值、fnptr、宏）继续静默，而它们正是误报源。
## 3. E2 当前 HEAD 的 `file:line` 锚点

| 方向 | 锚点 | 内容 |
| --- | --- | --- |
| 利 B | `selfhost/ct-ast/tool/driver/Driver.h.ct:352-355` | `check` 单独设 `ct_diag_set_strict(1)`；`compile`/`build` 不走这条，严格入口已存在 |
| 利 B | `selfhost/ct-ast/frontend/parse/Expr.h.ct:395-398` | `types_mode` 只由 `ct check --types` 置位；opt-in 开关是现成的 |
| 利 B | `docs/planning/requirements-pool.md:208` | 默认严格的影响面已登记：461 语料 rc + `test/cases/*.expected.c` 全量重生成 + archive ratchet 口径变化 |
| 利 B | `selfhost/ct-ast/frontend/type/TypeCheck.h.ct:323-540` | `expr_type` 已覆盖变量/成员/下标/调用/装箱/字面量/cast，B1 可直接复用 |
| 不利于己方 | `README.md:448` | `ct check` “仅单文件单元，`import` 不被接受”；41/530 个入口不可检 |
| 不利于己方 | `selfhost/ct-ast/frontend/parse/Stmt.h.ct:3788` | 初值判定只传 `typebuf`，数组维度在 `text3`；`char s[]="x"` 因此误报 |
| 不利于己方 | `selfhost/ct-ast/frontend/parse/Expr.h.ct:6960` | `chk_type` 对未建模形态 `return -1` 静默跳过，漏报是设计的一部分 |
| 不利于己方 | `docs/language-spec.md:2490` | “跨单元函数体与 `import` 单元不检查”写进规范，B2 要改规范口径 |

## 4. E3 可证伪预测与误报统计
误报率定义：`FP = (合法语料中 plain check rc=0 但 check --types rc=1 的文件数) / (合法语料中 plain check rc=0 的文件数)`；
漏报用固定探针矩阵统计（每条规则 1 个正例、1 个反例，记 caught/undetected），不用“语料没炸”代替覆盖率。
skip（数组/fnptr/void/sizeof/宏/import/接口槽）逐条进台账并写理由，skip 不计入覆盖。

| 预测 | 若 B 成立，运行 X 应得到 Y | 不成立即证伪 |
| --- | --- | --- |
| B1 | 修完 `Stmt.h.ct:3788` 后，上面 438 个合法件 `--types` FP=0；234/`array_str_init` 变 rc=0；12 个 `check_errors` 仍 rc=1；`git diff --stat` 不含任何 `*.expected.*` | 仍有任一合法件误报，或需改 golden 迁就，B1 未交付 |
| B2 | 41 个含 import 输入可检查，合法件 rc=0 且不写 `.c/.h`；跨单元签名错配的新夹具 rc=1；`ct build` 产物与 HEAD 逐字节相同 | 需要用户手动 `-I`、或 check 开始写产物、或 build 诊断变化，B2 未交付 |
| B3 | goto 跨声明/缺 return/switch 漏分支探针各 1 条 error；合法语料 FP=0；`ct compile` 产物不变 | 任一条探针漏报或合法件误报，B3 未交付 |
| B4 | 一层写入摘要能抓“`borrow` 存进全局/字段”的探针；own/borrow 夹具与 ASAN 全绿；FP=0 | 需要 CFG/生命周期类型才能抓，说明 B4 超出可达子集，应降级为 deferred |
| 全局 | 四相收口时 `bash selfhost/check-all.sh` 11 门禁全绿，`test/` 下 62 个 `.expected.c`、320 个 `.expected.out` 零重生成 | 任一 golden 重生成，B 的“旧语料零变化”承诺失效 |

## 5. E4 代价量化（B vs A）
| 项 | B（4 相 opt-in） | A（1 相或 2 相大爆炸） |
| --- | --- | --- |
| 编译器改动 | 2,650–4,600 LOC（B1 250–400 / B2 400–700 / B3 1,500–2,500 / B4 500–1,000） | 3,400–8,000 LOC；若含完整 CFG+数据流所有权，仓库已登记“5,000+ 行”（`requirements-pool.md` REQ-MEM-1） |
| 夹具/门禁 | 每相 100–250 行负例；只加 `check-ast.sh`/`check-semantics.sh` 断言 | 461 个语料 rc 重定基 + 62 个 `.expected.c` 重生成 + `check-goldens`/`check-archive`/`check-m2a`/`check-warnings` 口径复核 |
| phase 数 | 4 个，每相可独立验收、独立回退（关开关即回 HEAD 行为） | 声明 1–2 个；按 §6.6 T-2 单相上限必然再拆，实际 ≥5 个，且规则冻结先于实现 |
| 周期/风险/回退 | 4 个 phase 窗口，风险分散；最高风险是 B2；revert 单相 + 关开关即回 HEAD，不影响产物 | 一个窗口内同时改 CLI 语义、严重级、golden、归档 oracle；回退需恢复 461 语料 rc 与 golden，已发布归档不可回改 |

**opt-in 不是 sound。** B 必须自己说清：`ct check` 不是验证器——skip 表（数组/fnptr/void/宏）、单单元、
跨单元函数体不检查、接口槽不比较、指针基类型/层数部分放行；`ct check` 绿不等于程序正确。B 的价值不是
soundness，而是**可量化的错误预算**：FP 率、skip 台账、探针命中率、旧语料零变化。把“opt-in 稳定”说成
“默认路径安全”是 B 的越界；B 只承诺“在 1.0 前把可证明的规则做稳，并给出进编译路径的判据”。
## 6. E5 steelman A 与逐条反驳

A 的最强原文（`battle/typecheck-1/question.md:15-20`）：“在 1.0 前完成全量表达式类型检查”“编译路径默认拒绝类型/语义错误；
不再有‘ct 绿、C 红/运行错’的窗口”“大爆炸式：一个 phase 或两个 phase 内完成，先冻结规则再实现”。
其最强论点是：**opt-in 检查只要没人跑就等于没做**；1.0 是兼容性冻结点，之后再收紧会被当成破坏性变更。

1. “没人跑”是流程缺陷，不等于应把成本转嫁给每次编译。B 的补救是把 `ct check --types` 接进 CI 与
   新代码的默认流程（gate 10 扩一条语料扫描），并保留开关；这比让所有历史 C 超集程序承担误报便宜。
2. “冻结规则再实现”在本仓库已被证伪：Phase 45 的闭包/指针判据、本次 `char s[]` 误报都说明规则要靠
   实现与语料反推；先冻结只会把错误规则写进 1.0。
3. “基础设施已就绪”对双方都成立：`expr_type` 能省 B1 的成本，但省不掉 B3/B4——仓库没有 CFG、没有
   基本块、没有 pass 框架，所有权是名字扫描（`Memory.h.ct:5-9,44-60`），这正是 5,000+ 行的来源。
4. “只拒绝坏代码，不破坏 C 超集”今天不成立：合法件 234 与 `char s[]="x"` 已误报；强制进编译路径会
   把 1 个误报放大成 438 个合法件的迁移面。A 必须先证明 FP=0，这恰好是 B 的验收判据。
5. “1.0 后再收紧是破坏性变更”方向反了：把**已能证明的错误**从 warning 升 error，只影响本就该被 `cc`
   拒绝的程序；真正的破坏是在 1.0 前用未稳定的规则拒绝合法 C。

## 7. 结论
| 判据 | B 的判定 | 理由 |
| --- | --- | --- |
| J-1 覆盖/soundness | **部分不成立** | B 不承诺消掉“ct 绿、C 红”，只承诺可量化收敛；这是 B 的诚实边界 |
| J-2 兼容性 | **成立** | opt-in 不改产物；A 触发 461 语料 rc + 62 golden 重生成 |
| J-3 工作量 | **成立** | 4 相 2,650–4,600 LOC，可切分；A 的 1–2 相不可执行 |
| J-4 增量价值 | **成立** | 每相独立验收/回退；B2 是唯一高风险相 |
| J-5 语义可行性 | **部分成立** | B3/B4 只能做可达子集；完整 CFG/借用检查应 deferred |
| J-6 roadmap/切换 | **成立** | 4 相后逐相进编译路径；切换条件 = 连续 2 个版本 FP=0 + 旧语料零变化 + 开关保留 |

**B 胜出**：不是因为它更安全，而是因为 A 在 1.0 前不可执行、且当前实现连合法语料都有误报。
**B 不成立的条件**（任一出现即应改判 A 或 A-lite）：① B2 无法在不复制 build 的前提下让 check 看 import；
② 4 相后 FP 仍不收敛（`char s[]` 类误报再现）；③ 团队不把 check 接进任何门禁，opt-in 永远没人跑；
④ 1.0 日期早于 4 相窗口且用户要求 1.0 前关闭窗口——此时退到 A-lite：只把已证明的 L32-1/2/3 与 `err:`
在编译路径硬错，CFG/own 留在 opt-in，并登记 C-proposal。
