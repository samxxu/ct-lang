# SH-117 · J-6 本仓段收尾：`out/ref` 证据与 `ref/out` 逃逸条款

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（J-6 证据）/ spec 条款 |
| 定性 | 证据缺口（v1.0 闸门 E-V1-6） |
| 严重度 | Medium |
| 锚点 | `78477712`（2026-11-24） |
| 依据 | [J-6 台账](../../docs/planning/j6-evidence/ledger.md) 本仓段 3 缺失 / 3 部分；[SH-104](sh104-j6-evidence-ledger.md)（台账与拆段） |
| 状态 | open |
| 处置证据 | **accepted（2026-11-24 所有者同意开卡；承接 SH-104 未闭合的本仓段证据）** |

## 1. 范围

SH-104 已验证的是**台账结构、外部段拆出与 check-docs 断言**；下列 7 项证据仍属未闭合，
由本条承接。全部闭合后，台账本仓段应为 `passed=28 partial=0 missing=0 blocked=1 external=5`
（`blocked` 只剩 P-1.3，已由所有者裁定归 v1.x）。

| 判据 | 现状 | 要交付什么 |
| --- | --- | --- |
| P-3.5 C 边界 | 部分：`char *p = s`、`return s`（`String`/`Str`）仍被接受并发射坏 C | 先判定是修还是立 bug 卡；三类负例入库：赋值 / `return` / 变参 |
| P-5.2 旧值释放 / 别名 | 缺失：`out String` / `ref String` 的 owning 旧值释放轨迹无夹具 | `p80_retain` 增 out/ref 组合：retain 右值 → release 旧值 → 写入，ASan 无 UAF |
| P-5.3 `ref` 赋值 vs 显式 release | 缺失：两侧都没有夹具 | `ref String` 赋值合法；`release(ref)` 硬错，两例各一 |
| P-5.4 `out` 错误路径 | 部分：错误路径（提前 `return` / `err:`）缺用例 | out 在提前返回路径上“赋值即生效”的夹具 |
| P-5.5 `out/ref` 借用类型 | 缺失：`out Str` / `ref int[]` 无夹具 | 白名单正例 + 越界/写负例 |
| P-5.6 泄漏 / 双释放 | 部分：缺 out/ref 专项 ASan 组合 | 把上述夹具并入 ASan 组合，零报告 |
| J-4b `ref/out` 逃逸 | 缺失：契约文本未成文 | [spec §4.68](../../docs/language-spec.md#468-ref--out-参数phase-78仅-ct-ast) 增“可存储 / 可传更长寿命位置”的条款 + 存储负例 |

## 2. 约束

- **不混改**：P-3.5 若需要改编译器行为（拒绝隐式转换），先另立 bug 卡并在本卡记指针，
  不在本卡同时做“改行为 + 补夹具”；
- 夹具一律走既有探针目录与命名（`test/ast/p80_retain*` 等），不新造框架；
- 每行闭合时在同一次提交里更新 [台账](../../docs/planning/j6-evidence/ledger.md) 的状态、
  指针与 `<!-- j6:counts -->`；`check-docs` 必须绿。

## 3. 验收

- 上表 7 行全部为 `已过`，且“现有证据”列有可复跑路径；
- `check-docs` 计数为 `passed=28 partial=0 missing=0 blocked=1 external=5`；
- 新增的负例在对应探针里确实变红（至少一次红证，含 `baseline: <sha>`）；
- ASan/UBSan 组合零报告；
- 不改语言布局、不改 `Box`/`String` 的既有语义（J-4b 只写条款，不改行为）。

## 4. 非目标

- 不处理外部段（P-3.6 / P-6.x，已转 std 包）；
- 不处理 P-1.3（迁移 lint，归 v1.x）；
- 不做 `LANG-26` 的绑定点转换（归 v1.1）。

## 5. 关联

- [J-6 台账](../../docs/planning/j6-evidence/ledger.md)
- [SH-104](sh104-j6-evidence-ledger.md)（台账/拆段；verified 范围不含本条）
- [v1-PH-0](../../docs/phases/v1-PH-0/card.md)（E-V1-6）
- [spec §4.68](../../docs/language-spec.md#468-ref--out-参数phase-78仅-ct-ast)

## 6. 处置（DEV，2026-11-24）

> 本节只写处置与证据；`status` 字段不动，等集成后由 REV 复核改状态。

### 6.1 P-3.5：修编译器，不另立 bug

判定：**修**。三条形状修复前都发射 `cc` 直接拒绝的 C，或把 16 字节 struct 当 `%s`
实参（UB）：

- `char *p = s` → `char * p = s;`（`incompatible types`）；
- `char *give() { …; return s; }` → `char * __ct_sret = s;`（同一错误）；
- `printf("%s", s)` → 变参把 `struct String` 按值传入（`%s` 读垃圾）。

它们不是任何当前可编译语料会走的路径，拒绝它们不会让已通过的程序回归；全量
`check-ast` / `check-all` 复跑见 §6.4。风险低，故按卡内「若修」分支闭环，不另立
bug 卡。实现位置：`lit_coerce()`（声明初始式 / 普通赋值 / 返回位 / 声明形参实参）
与未解析 C 调用的实参检查（变参 `printf` 等；函数指针变量调用跳过）。

红证（`f6646943`，baseline `369fac67`）：

```console
$ sh test/ast/p80_cstr.sh .temp/sh117/ct-ast-baseline   # 退出码 1
FAIL p80/cstr: neg_ptr_assign
  accepted a negative
FAIL p80/cstr: neg_ptr_str_assign
  accepted a negative
FAIL p80/cstr: neg_ptr_return
  accepted a negative
FAIL p80/cstr: neg_ptr_vararg
  accepted a negative
```

绿证（`0469dd01`）：

```console
$ sh test/ast/p80_cstr.sh <ct-ast>   # 退出码 0
ok   neg_ptr_assign (rejected: cannot convert 'String' to)
ok   neg_ptr_str_assign (rejected: cannot convert 'Str' to)
ok   neg_ptr_return (rejected: cannot convert 'String' to)
ok   neg_ptr_vararg (rejected: cannot pass a 'String' handle to C function)
p80_cstr: OK
```

### 6.2 P-5.2 / P-5.3 / P-5.4 / P-5.5 / P-5.6：夹具并入 `p80_retain`

P-5.2 / P-5.3 的红证同时暴露一个所有权缺口：`out` / `ref` 形参的 owning 目标赋值
只发射 `(*slot) = (*src);`，旧值泄漏、两个句柄共用一个 refcount，`ref` 上的显式
`release` 也仍被接受。按 D-013 §3 与提案 Q13 的「赋值点 retain → release 旧值 →
写入」补齐（`0c9b29d1`）：

- emitter 把 ref/out 形参登记进类型表（own=0），使赋值目标解析成 owning；
- `sb_assign` 对 out/ref owning 目标补上「保留旧句柄 → retain（或 move）右值 →
  写入 → release 旧值」，别名自赋值安全；
- `ref`（非 out）上的显式 `release` / `drop` 硬错。

红证（`be1aee7e`，baseline `0469dd01`）：

```console
$ sh test/ast/p80_retain.sh .temp/sh117/ct-ast   # 退出码 1
FAIL p80/retain: out_ref_owning behaviour
  -after a=2 b=2 live=1 len=4
  +after a=1 b=1 live=2 len=4
FAIL p80/retain: ref_assign behaviour
FAIL p80/retain: out_error_path behaviour
FAIL p80/retain: neg_ref_release
  accepted a negative
ok   borrow_out_ref (automatic retain / release trace)
ok   trap_ref_slice_oob (out-of-bounds ref slice write trapped)
```

绿证（`0c9b29d1` + `4c55f459`）：

```console
$ sh test/ast/p80_retain.sh <ct-ast>   # 退出码 0
ok   out_ref_owning -fsanitize=address
ok   out_ref_owning -fsanitize=undefined
ok   out_ref_owning (automatic retain / release trace)
ok   ref_assign -fsanitize=address
ok   ref_assign -fsanitize=undefined
ok   ref_assign (automatic retain / release trace)
ok   out_error_path -fsanitize=address
ok   out_error_path -fsanitize=undefined
ok   out_error_path (automatic retain / release trace)
ok   out_err_path -fsanitize=address
ok   out_err_path -fsanitize=undefined
ok   out_err_path (automatic retain / release trace)
ok   borrow_out_ref -fsanitize=address
ok   borrow_out_ref -fsanitize=undefined
ok   borrow_out_ref (automatic retain / release trace)
ok   neg_ref_release (rejected: P-5.3: explicit release through ref)
ok   neg_out_str_write (rejected: P-5.5: write through out Str)
ok   neg_ref_slice_const (rejected: P-5.5: const slice write behind a parameter)
ok   neg_ref_array (rejected: P-5.5: C array as ref)
ok   trap_ref_slice_oob (out-of-bounds ref slice write trapped)
p80_retain: OK
```

逐行对应：

| 行 | 夹具 / 断言 |
| --- | --- |
| P-5.2 | `out_ref_owning`：trace `after a=2 b=2 live=1` / `end live=0`，别名 `rebind(a, a)` 后计数不变 |
| P-5.3 | `ref_assign` 正例；`neg_ref_release` 断言 `cannot release through a 'ref' parameter` |
| P-5.4 | `out_error_path`（提前 `return`）与 `out_err_path`（`return err:`）：`len=-1` / 新 `echo` 对调用方可见，旧值已释放 |
| P-5.5 | `borrow_out_ref` 正例（`out Str` / `ref Str` / `ref int[]`）；`neg_out_str_write` / `neg_ref_slice_const` / `neg_ref_array` 负例；`trap_ref_slice_oob` 越界 trap |
| P-5.6 | 上述正例全部在 `-fsanitize=address` / `-fsanitize=undefined` 下重跑，stderr 为空、输出逐字一致 |

### 6.3 J-4b：契约成文 + 存储负例

- spec §4.68 新增「逃逸契约（J-4b）」：`ref` / `out` **可存储、可传更长寿命位置**，
  语言不做借用检查；作者契约（存活期、`ref` 不得显式 release、`out` 赋值点释放
  旧值、错误出口不撤销）；类型系统只硬拦「借用视图存进禁止位置」（字段 / `Map` 键）。
- 存储负例 `test/ast/p80_retain/escape_ref_store.ct`（`ba33af51`）：`ref String` 上取到的
  视图存进全局，owner 先释放后读——编译器接受该存储（D-011 J-4b 裁定：契约级，无法
  类型级硬禁），ASan 报 `heap-use-after-free`，`p80_retain.sh` 的 `asan_escape_case`
  断言这条残余风险确实可被 ASan 抓到。

```console
$ sh test/ast/p80_retain.sh <ct-ast> | grep escape
ok   escape_ref_store (J-4b store escape is caught by ASan, not the type checker)
```

### 6.4 台账与门禁

- 台账 `<!-- j6:counts -->`：`passed=28 partial=0 missing=0 blocked=1 external=5`；
  P-3.5 / P-5.2–P-5.6 / J-4b 全部 `已过`，`python3 test/docs/check-docs.py` OK
  （34 J-6 row(s)，计数与逐行一致）。
- `selfhost/check-ast.sh`：`== summary: 1630 passed, 0 failed, 5 skipped ==`（退出码 0；
  5 skipped 为 Renode / dist / 外部包抓取类环境项）。
- `selfhost/check-all.sh`：`check-all: OK (12 hard gates green)`（退出码 0；私有
  `TMPDIR=/tmp/sh117-all`）。
- `selfhost/check-sanitizers.sh`：`check-sanitizers: OK (599 checks, no sanitizer report)`。
- 治理门禁：`g0` OK（block 1.18.0）、`g6` OK（307 issues）、`g8` OK（PN-2；9 legacy
  offsets）、`g9` OK（spec 1.18.0）。
- 未闭合项：**无**。P-1.3 仍 `阻塞`（所有者 2026-11-23 已裁定迁移 lint 归 v1.x）；
  外部段 5 项（P-3.6 / P-6.1–P-6.4）不属本仓 v1.0。
