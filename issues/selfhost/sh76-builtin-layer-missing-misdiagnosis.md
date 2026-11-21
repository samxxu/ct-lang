# SH-76 · 找不到内置层时泛型字段被误诊为 `expected a field name`

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（compile / build 驱动 + 解析器诊断） |
| 严重度 | **High**（单文件入口在源码树外无法声明容器字段；裸泛型还会静默落坏 C） |
| 优先级 | **P1** —— 挡住「随附二进制 + 普通项目目录」下的容器使用；有绕法（设 `CT_STD_DIR`） |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-20，REV） |
| 锚点 | `v0.53.1`（`3337ac7a`）；实测 `ct v0.53.0` / `ctc v0.53.0`（同一二进制，`ctc -> ct`） |
| 类型 | **实现缺陷**（不是语言缺口，也不是新特性） |

## 现象

同一份源码、同一台机器，**是否找得到随附的 `lib/std`** 决定结论：

```console
$ ctc src/json.h.ct -I src
ctc: warning: -I is ignored by compile mode; imports require 'ct build'
src/json.h.ct:84:8: error: expected a field name
```

四条最小探针（目录内没有 `lib/std`、未设 `CT_STD_DIR`）：

```console
$ ctc a.ct -o a.c          # struct A { Map<char *, int> *m; };
a.ct:1:15: error: expected a field name
$ ctc e.ct -o e.c          # struct E { Vec<int> *v; };
e.ct:1:15: error: expected a field name
$ ctc c.ct -o c.c          # struct C { Map<Str, int> *m; };
c.ct:1:15: error: expected a field name
$ ctc b.ct -o b.c          # struct B { Str *s; };
$ ctc h.ct -o h.c          # struct H { Str s; };
```

`B` / `H` 通过，因为 `Str` 不是泛型模板，不需要模板表。

## 实测对照（v0.53.0，同一二进制）

| 环境 | `ct a.ct`（compile） | `ct build a.ct` | 结论 |
| --- | --- | --- | --- |
| `/tmp`，无 `lib/std`、无 `CT_STD_DIR` | rc=1，`1:15 expected a field name` | rc=1，同一行 | 两种模式**结论相同** |
| cwd = 仓库根（有 `lib/std`） | rc=0 | rc=0 | 两种模式**结论相同** |
| `/tmp` + `CT_STD_DIR=<repo>/lib/std` | rc=0 | rc=0 | 两种模式**结论相同** |

**由此判定：不是「L0 与 L2 两套前端给出相反结论」。** 在本仓库里：

- 随附的 `ctc` 是 `ct` 的符号链接（`~/.local/bin/ctc -> ct`），二者是**同一个 ct-ast 二进制**；
- compile 模式（[Driver.h.ct:93](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L93) `load_builtin`）与
  build 模式（[Module.h.ct:426](../../selfhost/ct-ast/frontend/module/Module.h.ct#L426) `find_builtin`）
  **共用同一套解析器**（`frontend/parse/Parser.h.ct` + `Expr.h.ct`）；
- 仓库里真正的「两套前端」是冻结种子 L0（[l0/ctc.c](../../selfhost/l0/ctc.c)）与 L1/L2/ct-ast 代际，
  不是 compile / build 两个入口。L0 不依赖模板表，`Name<...>` 按拼写放行；ct-ast 要求模板已注册。

现场出现的「`ctc` 失败、`ct build` 正常」，在 v0.53.0 上无法用同一 cwd 复现；可复现的差异只有
「找不找得到内置层」。需要报告方补 `ctc -v`、`ct -v`、`pwd`、`echo $CT_STD_DIR` 才能定位其环境差异。

## 根因

1. `parse_type` 只在 `ct_tmpl_find(name) >= 0` 时读取 `Name<...>`
   （[Expr.h.ct:1867](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1867) → `parse_inst_type`）。
2. 模板表只在 `Vec.h.ct` 等内置单元被解析时登记（[Parser.h.ct:2315](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2315)）。
3. 内置层找不到时，`load_builtin` / `find_builtin` 把它当**合法缺省**（[Driver.h.ct:86-92](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L86-L92)、
   [Module.h.ct:421-425](../../selfhost/ct-ast/frontend/module/Module.h.ct#L421-L425)），继续解析。
4. `Map` 于是被当成普通类型名，`<` 留给字段解析器，[Parser.h.ct:2071](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2071)
   报 `expected a field name` —— 把「标准库没找到」误诊成「字段名写错」。

第二facet：裸 `Map *m`（无实参）在内置层缺失时**静默放行**并发射 `Map *obj;`，到 `cc` 才报
`unknown type name`。该行为已在 [language-capability-gaps §9.3](../../docs/proposals/language-capability-gaps.md)
与 ct-json 评审 C1 记录，但一直没有 issue。

## 修复落点

| 文件 | 改什么 |
| --- | --- |
| `tool/driver/Driver.h.ct` | 内置层探测补「安装相对」候选：`<argv[0] 所在目录>/../lib/std`（必要时再加 `$CT_HOME/lib/std`），优先于 cwd 相对候选 |
| `frontend/module/Module.h.ct` | 与 compile 模式共用同一个探测函数，删掉现在两份重复的三路查找（两处顺序必须一致，否则又会出现模式差异） |
| `frontend/parse/Expr.h.ct` | 防御性诊断：类型位置遇到「未知标识符 + `<`」时报 `unresolved generic type 'Map'（内置层未找到？设 CT_STD_DIR）`，不要回落成普通类型名 |
| 诊断 | 内置层确实缺失且源码引用了 `Vec`/`Map`/`MapEntry`/`Option`/`Result`/`Str` 时，给一条明确的环境诊断；不能继续静默 |

## 回归判据

| ID | 断言 |
| --- | --- |
| R1 | 四条探针（`Map<char*,int> *`、`Vec<int> *`、`Map<Str,int> *`、`Str *`）在**没有 cwd `lib/std`** 的普通目录下 rc=0 |
| R2 | `struct B { Str *s; }`、`struct H { Str s; }` 两种模式仍 rc=0（不依赖内置层也要过） |
| R3 | 同一文件 compile 与 build 结论一致（rc 与诊断逐字相同） |
| R4 | 负例：故意隐藏内置层 → 诊断点名 `CT_STD_DIR` / 内置层缺失，**不是** `expected a field name`，且不写 `.c` |
| R5 | 裸 `Map *m` 仍报 `generic struct 'Map' needs type arguments in a type position`（不因本修放宽） |
| R6 | `test/ast/**` 容器套件与 `test/pkg/run.sh` 全绿 |

## 与其他条目的关系

- **不合并**：LANG-11（同名单元产物冲突）同样改 `Driver.h.ct`，但根因不同，按 V-3 各自单独发。
- **文件族串行**：本条的 `Driver` / `Module` 与 LANG-11 串行；若把 `Expr` 诊断一并做，还要排在
  LANG-5 → LANG-4 → LANG-13 → LANG-14 → SH-65 之后。
- 与 LANG-12 / PH-56 无关：不是属性访问协议，也不是容器语法糖。

## 处置（2026-11-19，PH-72）

- 提交：`4280ed7e`
- 改动：类型位置未知 `Name<` 与裸内建泛型的明确诊断
- 验证：`sh test/ast/p72_stdmissing.sh <ct-ast>` → `OK p72/stdmissing`

## 处置（2026-11-20，DEV · 复跑）

- 结论：PH-72 的修复仍在 HEAD；只记录证据，不改 `status`。
- 命令/输出：

```console
$ bash test/ast/p72_stdmissing.sh /tmp/ci9-sh93-build/ct-ast
OK p72/stdmissing (builtin layer diagnostics)
```

## 复核（2026-11-20，REV）

**结论：verified。** 独立自举（`ct-ast v0.77.1`）后：

```console
$ sh test/ast/p72_stdmissing.sh /tmp/rev-v0771-build/ct-ast
OK p72/stdmissing (builtin layer diagnostics)
$ echo $?
0
```

修复提交 `4280ed7e` 为 HEAD 祖先；探针覆盖类型位置的未知 `Name<` 与裸内建泛型诊断。

## 复核（CI-11 复验，2026-11-21，REV）

**结论：verified（独立复跑）。** 在干净归档 HEAD `600e6595` 上重建 ct-ast v0.88.0，
重跑本条的回归探针；命令与原始输出如下（退出码 0）。

```console
$ sh test/ast/p72_stdmissing.sh /tmp/ct-head/b/ct-ast
OK p72/stdmissing (builtin layer diagnostics)
$ echo $?
0
```

状态词与证据对齐：正文有修复记录，回归探针存在并本轮通过，故维持 `verified`。
