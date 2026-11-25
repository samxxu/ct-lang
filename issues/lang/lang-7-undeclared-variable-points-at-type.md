# LANG-7 · 静态方法解析失败时报 `use of an undeclared variable`

| 项 | 值 |
| --- | --- |
| 模块 | lang（诊断文案） |
| 严重度 | Low |
| 优先级 | **P3** —— 只误导方向，不挡功能；与 LANG-2 同一路径，建议同修 |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-20，REV） |
| 锚点 | `v0.53.1`（`c4727787`） |

## 精确触发条件

静态调用无法解析、且接收者是一个**类型名**时（LANG-2 的主路径）。编译器把接收者当变量查，
查不到后落到通用的未声明变量兜底。

## 最小复现

同 [LANG-2](lang-2-namespaced-static-method-unresolved.md) 的 `main.ct`：

```sh
ct-ast build -I . main.ct -o prog
```

## 实际行为

```text
main.ct:4:16: error: use of an undeclared variable
```

列号 16 指向 `Box.make` 的点号——报错对象是一个**类型名**，用户会去查 import / 可见性，
而真实原因是静态方法没解析出来（namespace 前缀导致查找键不匹配）。

## 期望行为

```text
error: static method 'make' of type 'Box' cannot be resolved; namespace-qualified type names are not supported
```

（或以「类型上没有该方法」为主句，并列出该类型的静态方法候选。）

## 影响面

所有踩 LANG-2 的下游（ct-sse、nexcore）在排查时会先怀疑 import/可见性；
外部反馈口径也因此把问题描述成「静态方法不可用」而非「namespace 下的名字解析」。

## 定位

通用兜底在 [Expr.h.ct:5854](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2658)；
静态调用识别在 [Expr.h.ct:5239](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2043)。

## 说明

这只是 LANG-2 的次生问题，单独登记是为了「修完 LANG-2 后还要检查文案」不被漏掉；
若 LANG-2 修好后该路径不再可达，本单随之关闭。

## 处置（2026-11-20，DEV #2）

**结论：fixed**（类型名接收者的静态调用改报准确诊断，带 `file:line:col`）。

LANG-2 修复后，原单的 namespace 场景已不再可达；但静态调用分支的根因仍在：
它只查 `find_struct`，未命中就落到变量兜底。触发面收窄为**已声明但不是 struct**
的类型名——typedef（`MyInt.make(1)`）与 enum（`Color.make(1)`），baseline 仍报
`use of an undeclared variable`，位置在点号上。

- 红证（baseline `38248747`，即 test 提交的父提交；该提交只改 docs，`selfhost/`
  与 `test/` 与 `7b8e8c9b` 逐字相同，红证用 `fa89d727` 重建的 ct-ast 复跑）：
  ```console
  $ sh test/ast/p77_lang7_static_type.sh /tmp/headbase/ct-ast   # rc=1
  ok   struct static call still works
  ok   declared struct with no such method keeps its message
  ok   an undeclared name still reports an undeclared variable
  FAIL p77/lang7: typedef receiver names the type
    missing diagnostic: .../typealias.ct:2:30: error: use of an undeclared variable
  FAIL p77/lang7: enum receiver names the type
    missing diagnostic: .../enum.ct:2:30: error: use of an undeclared variable
  ```
- 修法：`Expr.h.ct` 静态调用分支在 `find_struct` 未命中后，用
  `find_type` / `find_type_alias` / `find_trait` 确认接收者是否为已声明类型；
  是则前看 `.name(`，命中即报
  `static method 'make' cannot be resolved: 'MyInt' is a type name, not a variable`
  （位置取接收者 token）。非 `.name(` 形状原样回退；未知名仍是未声明变量，不越界。
- 绿：
  ```console
  $ sh test/ast/p77_lang7_static_type.sh .temp/b/ct-ast   # rc=0
  ok   typedef receiver names the type
  ok   enum receiver names the type
  ok   struct static call still works
  ok   declared struct with no such method keeps its message
  ok   an undeclared name still reports an undeclared variable
  OK p77/lang7 (type-name static call diagnostic)
  ```
- 提交：
  - `d0cb10c4` `test(ct-ast): LANG-7 红 — 类型名接收者的静态调用诊断`
  - `eed1cbcd` `fix(ct-ast): LANG-7 类型名接收者的静态调用报准确诊断`
- 探针：`test/ast/p77_lang7_static_type.sh`，已接入 `selfhost/check-ast.sh`。
- 回归扫描：289 个 `test/ast` 夹具、`test/cases` 与 `examples` 无新增拒绝。

## 复核（2026-11-20，REV）

**结论：verified。** 独立自举 `git archive v0.77.2`（`ct-ast v0.77.2`）；红证用
`git archive fa89d727` 重建的基线二进制配 HEAD 探针复跑。

```console
$ sh test/ast/p77_lang7_static_type.sh /tmp/rev-v0772/ct-ast
ok   typedef receiver names the type
ok   enum receiver names the type
ok   struct static call still works
ok   declared struct with no such method keeps its message
ok   an undeclared name still reports an undeclared variable
OK p77/lang7 (type-name static call diagnostic)
$ echo $?
0
```

```console
$ sh test/ast/p77_lang7_static_type.sh /tmp/rev-base/ct-ast
FAIL p77/lang7: typedef receiver names the type
  missing diagnostic /static method 'make' cannot be resolved: 'MyInt' is a type name, not a variable/: .../typealias.ct:2:30: error: use of an undeclared variable
FAIL p77/lang7: enum receiver names the type
  missing diagnostic /static method 'make' cannot be resolved: 'Color' is a type name, not a variable/: .../enum.ct:2:30: error: use of an undeclared variable
ok   struct static call still works
ok   declared struct with no such method keeps its message
ok   an undeclared name still reports an undeclared variable
$ echo $?
1
```

逐条对照：typedef（`MyInt.make`）与 enum（`Color.make`）接收者在 v0.77.2 报
`static method 'make' cannot be resolved: '<T>' is a type name, not a variable`，位置在接收者；
struct 静态调用、struct 无此方法、未知名三例文案不变，未越界。

引用瑕疵（不影响结论）：处置段把 baseline 写作 `38248747`，但红证实际用 `fa89d727` 重建的
二进制；两者只差 LANG-5 的 `Expr.h.ct` 49 行，LANG-7 路径不受影响，红证仍成立。
`38248747` 确实是红提交 `d0cb10c4` 的父提交，T-7 链成立。
