# S2 `ref` / `out` 最小原型：证据记录

> J-6 / P-7.1 的第一步。**不是 phase 卡**，不改语言规范；只证明最小语法与发射路径可行。

## 基线

- 主树基线：`2c87179a`（v0.77.2）。
- 原型工作树：`/tmp/ct-refout`，分支 `proto/ref-out`。
- 补丁：[ref_out.patch](ref_out.patch)（5 个源文件，477 行 diff）。
- 构建：`CT_SOURCE_DIR=/tmp/ct-refout CT_PREFIX=/tmp/ct-refout-bin sh install.sh`。

## 红：未打补丁的编译器

```console
$ sh test/proto/ref_out/run.sh
...
prog.ct:5:10: error: unknown type name 'ref'
prog.ct:6:10: error: unknown type name 'out'
run_rc=1
```

## 绿：打补丁后的编译器

```console
$ rm -rf .ctbuild
$ CT=/tmp/ct-refout-bin/ct sh test/proto/ref_out/run.sh
...
ref_out: rc=0
```

生成的 C：

```c
void inc(int * x) {
    (*x) = ((*x) + 1);
}
int read(int * y) {
    (*y) = 7;
    return (*y);
}
int main(void) {
    int v = 1;
    int n;
    inc(&v);
    r = read(&n);
    ...
}
```

## 已实现（仅原型）

- `ref T` / `out T` 作为形参表内的上下文标注；
- 形参签名发射为 `T *`；
- 函数体内对 ref/out 参数的读写发射 `(*name)`；
- 调用点对 ref/out 实参自动加 `&`；
- 调用点 lvalue 硬错：变量、字段、`*p`、数组/切片/Vec/Map 元素允许；
  字面量/表达式/调用结果/cast 拒绝；
- `out` 调用方初始化：trivial 可未初始化；owning 必须已初始化（直接变量形态）；
- `out` L1 定值：顺序语句 + if/else 精确，`return`/函数末尾检查，循环/switch/goto 保守；
- 原型/定义/ABI 头的参数类型同步；
- 标量 `int` 正例通过；字段/数组 place 正例通过；
- 既有 `examples/01_greeter`、`test/ast/17_param_array` 回归通过。

反例：

```console
$ ct build evidence/ref_out/bad_literal.ct -o /tmp/bad
evidence/ref_out/bad_literal.ct:9:1: error: ref/out argument must be an assignable place

$ ct build evidence/ref_out/bad_out_path.ct -o /tmp/bad
evidence/ref_out/bad_out_path.ct:6:1: error: out parameter 'y' is not assigned on every path

$ ct build evidence/ref_out/bad_out_uninit.ct -o /tmp/bad
evidence/ref_out/bad_out_uninit.ct:13:1: error: out owning argument must be initialized
```

正例：

```text
ref_out: rc=0                 # 变量 ref/out
places.ct: rc=0               # 字段/数组元素
good_out_if.ct: rc=0          # if/else 两边都赋值
good_out_owning.ct: rc=0      # owning out 已初始化
```

## P-7.1b：方法 / trait 上的 ref / out

同一编译器上补齐方法签名、trait 签名、vtable 槽与调用点的 `&`：

- trait 声明参数接受 `ref` / `out` 上下文标注，`MethodSig.pann[]` 记录；
- vtable 槽发射 `T *`，impl 方法定义与头文件原型同步发射 `T *`；
- 方法体 `(*name)` 与 L1 定值检查（`out` 每条路径赋值）覆盖 impl 方法与 trait 默认体；
- 方法调用点对 ref/out 实参自动加 `&`；
- 方法调用的 lvalue / owning 初始化 / 类型匹配负例均硬错；
- 泛型 impl（`impl<T> Box<T> use Touch`）同样覆盖，`methods_generic.ct` 运行 `rc=0`。

正例 `methods.ct`（trait 方法 `bump(ref int, out int)`，`n==4 && r==8`）：

```console
$ CT=/tmp/ct-refout-bin/ct sh evidence/ref_out/run.sh
prog: rc=0
places: rc=0
good_out_if: rc=0
good_out_owning: rc=0
methods: rc=0
methods_generic: rc=0
bad_literal: rejected
bad_out_path: rejected
bad_out_uninit: rejected
bad_method_out: rejected
bad_method_literal: rejected
bad_method_type: rejected
ref_out: all green
```

反例诊断：

```text
bad_method_out.ct:11:1: error: out parameter 'y' is not assigned on every path
bad_method_literal.ct:22:1: error: ref/out argument must be an assignable place
bad_method_type.ct:23:7: error: type mismatch: 'bump' argument 1: expected 'int', got 'struct Box'
```

回归：`examples/01_greeter`、`examples/05_body_dispatch`、`examples/24_vec_ops` 编译通过。

## 未实现（明确限制）

- `out` owning 初始化只查**直接变量声明**；先声明后赋值的变量仍会被保守拒绝；
- 字段/元素作为 `out` 实参时假设已初始化，没有逐字段定值；
- L1 循环/switch/goto 保守：循环内赋值再 return 会被误拒；
- 类型匹配按基类型比较（`ref/out` 不改 `ptype`）；负例已覆盖基类型不匹配；
- trait 方法与泛型 impl 已覆盖；闭包、函数指针、跨单元签名未验收；
- 拒绝数组/函数指针形态的 ref/out 参数；
- 未跑全量 `check-all` / ASan。

## 下一步

1. `out` owning 初始化扩展到「先声明后赋值」的数据流；
2. 泛型 impl 与跨单元签名；
3. 全量门禁与 ASan；
4. P-7.2（S3 切片）与 P-7.3（S5 最小垂直切片）。

## 复现

```console
$ # 在干净的 HEAD 工作树上：
$ git apply --check /tmp/ct-refout/evidence/ref_out/ref_out.patch
$ CT_SOURCE_DIR=/tmp/ct-refout CT_PREFIX=/tmp/ct-refout-bin sh /tmp/ct-refout/install.sh
$ CT=/tmp/ct-refout-bin/ct sh /tmp/ct-refout/evidence/ref_out/run.sh
```
