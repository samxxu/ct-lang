# TEST-18 · `tparam_residue()` 只覆盖编译模式夹具的实例体，其余产物仍是盲区

| 模块 | testing |
| --- | --- |
| 严重度 | **Medium** |
| 锚点 | `v0.26.3` |
| 文件 | [check-ast.sh](../../selfhost/check-ast.sh) |
| 状态 | **verified**（2026-11-09 v0.26.4 补丁处置并经独立评审复核；依据 [review-phase26-v0.26.4.md](../../docs/history/reports/review-phase26-v0.26.4.md) §3 与 §1 的 P1/P2） |

## 现状（已覆盖）

`tparam_residue()` 挂在 `check-ast.sh` 的主夹具循环里，覆盖 `test/ast/*/prog.ct` 的**编译模式**
产物（`$work/<name>.c`），并且：

1. 类型参数名从夹具自身的顶层泛型声明自动提取，新夹具自动纳入；
2. 只扫描实例函数体（`<name>__ctN(...) { … }`），因此用户在非模板函数里写的 `int T = 5;`
   不再被当成泄漏（SH-64 轮消掉的假阳）；
3. 实例体内扣掉合法的 `struct|union|enum T` 标签后，残留即 `bad`。

红/绿对照：v0.26.1 坏产物 `sz261.c` → `T(1)`；含 `int T = 5;` 的探针整文件扫描 `T(2)`（假阳）、
实例体扫描空；123–129 的 v0.26.3 产物为空。

## 盲区（未覆盖）

| 产物 | 为什么没扫 | 扩面的代价 |
| --- | --- | --- |
| `.h` 产物（`.h.ct` 输入） | 主循环只编译 `prog.ct`，不扫头文件 | 需要把扫描挂到 `check-ast` 的 `.h.ct` 分支与 module 构建路径 |
| `test/ast/errors/` | 负例按“必须非零退出”判定，通常没有产物 | 一旦某条负例回归成退出 0，负例本身已红；补扫属冗余 |
| module `build` 产物 | 产物在临时 build 目录，主循环不接触 | 需要遍历 build 目录，并按单元关联模板声明；跨单元实例（模板在 `.h.ct`、实例在消费者 `.c`）还要建立声明→实例映射 |
| `test/cases` / `examples` 语料 | 走 corpus-equivalence，按行为比对 | 需要为每个语料保留编译产物并重复实例体提取 |
| build 模式的任意夹具 | 主循环用 `ct-ast <src> -o`，不走 `build` | 同上，且 build 会拆分多文件产物 |

这些盲区不影响本轮根因修复（SH-64 的守卫在解析期硬错，任何出口都到不了发射），但意味着
`tparam_residue()` 不能声称“全产物覆盖”。文档中的措辞已限定为“编译模式夹具的实例体”。

## 建议

优先把扫描挂到 `ct-ast build` 的产物写出点：那里能拿到“本单元声明了哪些泛型 + 生成了哪些实例”，
可以继续用实例体限定避免假阳。跨单元实例需要额外的声明映射，成本明显更高，建议单独立项。
在扩面之前，任何新的泛型形态仍应同时补一条负例（`p26_diag` + `p26_chk`），不要只依赖防线。

## 关闭条件

`build` 与 `.h` 产物的实例体也被同一个机械扫描覆盖，或明确决定永久不覆盖并在
`docs/design/phase26.md` §2.7 写明理由。

## 处置（实现方，v0.26.4 补丁）

关闭条件的前半已满足：

- **`test(check-ast): scan build and header products for leaked type parameters`**：
  build 分支对 `<outdir>` 下每个 `*.c` 逐份扫描、每个 `*.h` 断言无实例体；`.h.ct` 的 hdr /
  prologue 块接同一断言；扫描器加红/绿自检。夹具 `test/ast/130_generic_build_mode/`。
- **`fix(check-ast): read type parameters from every unit in a fixture`**：
  类型参数名从夹具目录下**全部 `.ct`** 提取（`fixture_sources()`），修掉「泛型只声明在导入单元」
  时的静默；夹具 `test/ast/131_generic_cross_unit/` 固定该形态（实例体在导入单元的产物 `lib.c`——
  `-o` 目录扁平化——入口无泛型）。`check-warnings.sh` 的 build 触发条件同步扩到 `.h.ct`。

残余盲区（`test/modules/**` 独立构建、`test/cases` / `examples` 语料）按关闭条件后半处理：
理由与触发条件写在 [phase26.md §2.7](../../docs/design/phase26.md#L252) 的覆盖表里。

验证：

```console
$ bash selfhost/check-ast.sh        # == summary: 834 passed, 0 failed ==
$ bash selfhost/check-warnings.sh   # check-warnings: 253 ok, 0 failed
```

红证：把自检调用改回「只传入口 `src.ct`」→ `FAIL tparam_residue self-test: the scanner
stayed silent on a leaked type parameter`（`833 passed, 1 failed`，退出 1）。
