# TEST-17 · Phase 26 夹具只覆盖“返回类型 / 形参”替换，S4 其余替换点与实例管理均无断言

| 模块 | testing |
| --- | --- |
| 严重度 | **P1（High）**（门禁全绿但放过了 SH-62 的静默坏产物） |
| 锚点 | `v0.26.0` / `ac1c7cd`（HEAD = `main`） |
| 文件 | [check-ast.sh](../../selfhost/check-ast.sh#L1159-L1222)、[123/prog.ct](../../test/ast/123_generic_identity/prog.ct)、[124/prog.ct](../../test/ast/124_generic_struct/prog.ct) |
| 状态 | **reopened**（2026-11-09 评审复核，`v0.26.1` / `d29de8f`：新增夹具与断言属实且负例会红，但无括号 `sizeof T` 的静默坏产物仍无夹具，见「评审复核」） |

## 现象

两个正例夹具的模板体都只有 `return x;`（123 为 `id<T>`，124 为 `pass<T>`），
`check-ast.sh:1160` 的 `! grep -qE '\bT\b'` 只能证明**签名**里的 `T` 被替换，
函数体里根本没有任何类型位置，因此对 §4.48 承诺的其余替换点零覆盖：

| 立项 S4 / §4.48 的替换点 | 是否有夹具 | 实测结果 |
| --- | --- | --- |
| 返回类型 | ✅ 123 / 124 | 成立 |
| 形参 | ✅ 123 / 124 | 成立 |
| 局部声明 | ❌ | 成立（本次评审用 `/tmp` 探针验证） |
| `(T)` 转型 | ❌ | **不成立**（SH-62） |
| `sizeof(T)` | ❌ | **不成立，且静默产出非法 C**（SH-62） |
| `_Alignof(T)` | ❌ | **不成立**（SH-62） |
| `offsetof(T, …)` | ❌ | **不成立**（SH-62） |

此外，以下已实现的行为也没有任何断言：

- 同一 `(模板, 类型)` 的多处调用只登记一份实例（`id<int>` 调用三次）；
- 实例名冲突回退（R6）与 `MAX_GENERIC_INSTS = 64` 边界；
- `struct T` 与类型参数 `T` 同名时不得替换（SH-63）；
- 实例调用点 arity 不符时的告警文案用的是 `id__ct1` 而非源名 `id`（见 review 报告 §4 观察）。

## 证据

```console
$ sed -n '1,30p' test/ast/123_generic_identity/prog.ct   # 模板体仅 return x;
$ sed -n '1,30p' test/ast/124_generic_struct/prog.ct     # 模板体仅 return x;
$ bash selfhost/check-ast.sh | tail -1
== summary: 803 passed, 0 failed ==
```

门禁绿，但把 SH-62 的 `sizeof(T)` 探针放进 `test/ast/` 后，`! grep -qE '\bT\b'` 会立刻变红——
说明断言本身有效，只是**夹具没有覆盖到**。也就是说 803 这个数字对 S4 的证明力被高估了。

## 修复建议

在 123/124 的模板体里补上局部声明、`(T)`、`sizeof(T)`、`offsetof`（以及 `_Alignof`）四类形态，
或新增 125/126 夹具；补“同类型多处调用只生成一份实例”的精确 `grep -c` 断言
（现在 `-ge 2` 只能证明“至少有实例”，不能证明“每个类型实参恰好一份”）；
补 `struct T` 同名夹具。修完后重跑 `check-ast.sh` 与 `check-all.sh`，确认数字更新且生成物无回归。

## 修复（`v0.26.1`，`f5f1092`）

- `123_generic_identity`：模板体保留 `return x;`，但调用点改为两次 `id<int>` + 一次 `id<char *>`；断言收紧为实例原型 `-eq 2`、`id__ct1` 定义恰 1 份、`b = id__ct1(7);` 存在——证明同一 `(模板, 类型)` 只登记一份。
- 新增 `125_generic_type_positions`：局部声明 `T v;`、`(T)`、`sizeof(T)`、`_Alignof(T)`、`offsetof(T, y)`、调用实参 `absorb((T)v)`、`va_arg(ap, T)`；断言生成 C 的每个具体类型拼写并运行输出 `4 4 4 4 5`。
- 新增 `126_generic_struct_tag`（`struct T` 标签，输出 `7`）、`127_generic_name_retry`（用户先占 `id__ct1`，回退 `id__ct1_1`，输出 `2 2`）、`errors/generic_too_many.ct`（第 65 个实例报 `76:80: error: too many generic instances in this unit`）、`errors/generic_generic_selector.ct`（模板体内 `_Generic` 用类型参数报 `7:24: error: type parameter cannot be used inside _Generic`）。

红证（先红后绿）：

```console
# v0.26.0 基线编译器
$ ct-ast test/ast/125_generic_type_positions/prog.ct -o /tmp/red125.c
prog.ct:21:12: error: unexpected token            # 退出 1
$ ct-ast test/ast/126_generic_struct_tag/prog.ct -o /tmp/red126.c
$ grep getv__ct1 /tmp/red126.c
static struct int getv__ct1(struct int *);        # 退出 0 的坏产物

# v0.26.1
$ bash selfhost/check-ast.sh
== summary: 812 passed, 0 failed ==
```

断言条数由 803 变为 812（新增 5 个 Phase 26 用例 + 123 的 4 条收紧），如实记录，未套用旧数字。

## 评审复核（`v0.26.1` / `d29de8f`，2026-11-09）

结论：**reopened**。修复内容属实，但「静默坏产物仍能通过门禁」这一核心缺口只补了括号形式。

**通过项**：

1. 门禁数字属实：评审方独立实跑 `bash selfhost/check-ast.sh` → `== summary: 815 passed, 0 failed ==`（`EXIT=0`）；
   `bash selfhost/check-all.sh` → `check-all: OK (11 hard gates green)`，同一日志内 check-ast 也是 `815 passed, 0 failed`。
2. 新增夹具存在且断言有效：125 / 126 / 127 与两条负例在 `check-ast.sh` 中都有精确 `grep` / `p26_diag`，不是泛泛的“至少 N 条”。
3. 负例确实会红（变异 + 修复前基线双重证明）：

```console
# A. 在 /tmp 副本删掉 _Generic 守卫后重编 ct-ast
$ /tmp/p261/mut-sel/b/ct-ast test/ast/errors/generic_generic_selector.ct -o ...
ct_exit=0
$ grep -n '_Generic' ...
11:    return _Generic ( x , T : 1 , default : 0 );
$ # 用 check-ast.sh 的同一条 file:line:col: error: 文案判定
RED

# B. 在 /tmp 副本把 MAX_GENERIC_INSTS 64 改为 1000000 后重编 ct-ast
$ /tmp/p261/mut-many/b/ct-ast test/ast/errors/generic_too_many.ct -o ...
ct_exit=0
RED

# C. 修复前基线（v0.26.0 源码 + 冻结 L2 重编的 ct-ast-v0.26.0）
$ ct-ast-v0.26.0 test/ast/125_generic_type_positions/prog.ct
test/ast/125_generic_type_positions/prog.ct:21:12: error: unexpected token        （exit 1）
$ ct-ast-v0.26.0 test/ast/126_generic_struct_tag/prog.ct ...; grep getv__ct1 ...
static struct int getv__ct1(struct int *);                                       （exit 0，坏产物）
```

注：127 的 R6 回退在 v0.26.0 基线已工作（`id__ct1_1`），它不是修复项，只是既有行为固定。

**未通过项**：门禁仍抓不到无括号 `sizeof T`（SH-62 的残余通道）。该形态退出 0、产物含 `T`，
而 125 只覆盖 `sizeof(T)`；把 `sizeof T` 探针放进 `test/ast/` 后 `! grep -E '\bT\b'` 才会红。
即本条的核心判断「门禁全绿但放过静默坏产物」在 v0.26.1 仍成立。

**关闭条件**：补 `sizeof T`（及同族无括号形式）夹具并让生成物断言变红；与 SH-62 同步复核。
