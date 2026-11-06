# SH-52 · 命名空间静态初始化器不重写被引用全局的名字，生成的 C 无法编译

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | **High** |
| 锚点 | commit `4176c63`（`v0.19.1`，2026-11-03）；本机 `ct v0.19.1` 复现 |
| 文件 | [Emitter.h.ct:1742-1744](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1742-L1744)（初始化器走 `emit_expr`）；[L1785-1790](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1785-L1790)（声明名才加前缀） |
| 状态 | 待处理 |

## 现象

命名空间里的全局变量在声明处会被加上单元前缀（`k_foo` → `ns_k_foo`），但**静态初始化器里引用的
其它全局**不会。于是一份语义合法的 `.ct` 会生成引用未声明名字的 C，`ct compile` 仍返回 0，错误
要等到 `cc` 才暴露。

## 证据

输入：

```c
namespace ns;
struct Foo { int x; }
struct Bar { int y; struct Foo *f; }
static Foo k_foo = { 7 };
static Bar k_bar = { 9, &k_foo };
```

```text
$ ct compile ns.ct -o ns.c
rc=0

$ grep -n "ns_k_" ns.c
13:static struct ns_Foo ns_k_foo = { 7 };
14:static struct ns_Bar ns_k_bar = { 9, &k_foo };
```

第 14 行的 `&k_foo` 应为 `&ns_k_foo`：

```text
$ cc -std=c99 -c ns.c -o ns.o
ns.c:14: ... error: use of undeclared identifier 'k_foo'
1 error generated.
```

这是外部评估附录 C.4 报告的问题，本轮独立复现；同一缺陷对结构体字段初始化器、嵌套初始化器同样成立。

## 影响

**High**：源码合法、`ct compile` 成功、产物不可编译。对多单元 / 命名空间项目是静默失败——错误信息
指向生成 C 的标识符，而不是 `.ct` 源行；若构建脚本只看 `ct compile` 的退出码，会把失败推迟到链接阶段。
现有门禁没有覆盖「命名空间内静态初始化器引用同单元全局」组合。

## 修复建议

1. 在发射全局初始化器时（`emit_expr` 对 `N_VAR` / 全局引用的路径）套用与 `emit_global_decl`
   相同的 `gprefix` 规则：名字属于本单元命名空间且未 `pub` 化时输出 `<prefix><name>`；
2. 若初始化器是 `N_RAW`（`emit_raw_init`），至少对**本单元已声明的全局名**做一次前缀重写；
3. 新增正例 `test/ast/<n>_ns_static_init/`：`namespace ns; static Foo k_foo…; static Bar k_bar = { …, &k_foo };`，
   断言生成 C 含 `&ns_k_foo` 且能 `cc -c` 通过；
4. 顺带覆盖数组 / 嵌套 struct / 指向 struct 的指针三种初始化器形态。

## 验证

- 上述探针的生成 C 含 `&ns_k_foo`，`cc -std=c99 -c` 成功；
- `bash selfhost/check-ast.sh` 与新正例全绿；
- `bash selfhost/check-all.sh` 仍为 `12 hard gates green`。
