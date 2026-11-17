# SH-86 · 带 trait 的数组与 `const` 对象：vptr 静默丢失，初值发非法 C

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`backend/emit`：`Init::emit_raw_init` / `Emitter::emit_unit_init`） |
| 类型 | 静默坏 C + 静默错值（D-005 的 bug，走 PATCH） |
| 严重度 | High（裸机上是上电 HardFault，宿主上是段错误） |
| 状态 | verified |
| 锚点 | v0.62.0（`485129c9`） |
| 承诺出处 | [REQ-HW-001/002](../../docs/planning/hardware-readiness-requirements.md)、[裸机提案 §2.1–2.3](../../docs/proposals/ct-bare-metal-proposal.md) |

## 现象

五种形态，`ct` 全部返回 0，坏在 `cc` 或运行期：

1. **文件/局部数组带初值**：外层被追加顶层字段设计式 `, .__x_vptr = …`，`cc` 报
   `field designator cannot initialize a non-struct, non-union type 'struct Person[2]'`；
2. **`[]` 推导数组带初值**：同上，并在构造函数里再发一个空上界循环 `__ct_i < ;`；
3. **`const` 标量**：一个 vptr 都不写；
4. **`const` 数组**：一个 vptr 都不写、也不走构造函数；
5. **多维 trait 数组**：`ct` 放行，直到 `cc` 才炸。

## 最小复现

```console
$ cat > ps.ct <<'CT'
trait Greeter { char *who(); }
struct Person { char *name; } use Greeter;
impl Greeter for Person { char *who() { return self->name; } }
Person ps[2] = { { .name = "a" }, { .name = "b" } };
int main(void) { return ps[0].who() != 0; }
CT
$ ct ps.ct -o ps.c ; echo $?
0
$ cc -std=c99 -Wall -Wextra -c ps.c
ps.c:12:46: error: field designator cannot initialize a non-struct, non-union type 'struct Person[2]'
```

`const` 分支的 rc：

```console
$ ct d4.ct -o d4.c && cc d4.c -o d4 && ./d4 ; echo $?
139
```

## 期望行为（REQ-HW-001/002）

- 数组元素与 `const` 对象的 vptr 由**C 初值本身**写入，数组外层不得出现设计式；
- 带初值数组不再发 `__attribute__((constructor))`（裸机 `Reset_Handler` 不跑它）；
- 无初值数组保持原路径（局部循环 / 单元构造函数）；
- 多维 trait 数组在 `ct` 阶段硬错并给位置。

## 影响

连接表、驱动表这类全局数组在裸机上静默为空 vptr；`const` 常量表 + 方法完全不可用；
`cc` 阶段才失败使 `ct` 的「要么编过要么硬错」承诺失效。

## 处置（v0.62.1）

- `Init` 增 `unqual()`：`const struct X` 也能解析到结构体与 vtable 名；
- `Init::emit_elem_vptrs`：把 vptr 设计式注入**每个元素自己的花括号**内（跳过字符串与字符字面量，
  只作用于元素层级），数组外层不再追加；
- `Emitter::unit_init_needed`：带初值且已注入的数组不再进构造函数；`{ 0 }` / 嵌套值字段仍保留构造函数；
- `Emitter::dims_depth`：多维 trait 数组在 `ct` 阶段硬错
  `a multi-dimensional array cannot hold trait-carrying values`；
- 夹具 `test/ast/287_trait_array_vptr_init`、`288_trait_array_noinit`、`errors/trait_array_multidim`；
- 25 个 case golden 的 `.c`/`.h` 与 p39 ABI 头各变 1 行 banner（版本 token，不是语义变化）。

红证：`baseline: 9929fa8d`，`bash selfhost/check-ast.sh` → `== summary: 1452 passed, 5 failed ==` rc=1
（详见提交 `566f8e1b` 正文）。

## 关联

- [SH-25](sh25-typedef-alias-drops-dims.md)：`typedef` 别名漏拷 `dims`（已修，另一入口）；
- REQ-HW-010…013（PH-64）：符号面、按需单元、`--alloc`、const vtable。

## 复核（REV，2026-11-17）

| 项 | 值 |
| --- | --- |
| 复核人 | REV |
| HEAD | `72ed6dc`（`ct-ast v0.63.4`；macOS 27.2 arm64 / Apple clang 21） |
| 结论 | `verified` |

四层自举（L0→L1→L2→ct-ast）到 `/tmp/rev/ct-ast`，七步全 `rc=0`。命令与原始输出：

```console
$ /tmp/rev/ct-ast test/ast/287_trait_array_vptr_init/prog.ct -o /tmp/r287.c ; echo rc=$?
rc=0
$ cc -std=c99 -Wall -Wextra -c /tmp/r287.c -o /tmp/r287.o ; echo rc=$?
rc=0
$ grep -c 'constructor' /tmp/r287.c ; echo rc=$?
0
rc=1                # 零命中，判据是计数 0
$ /tmp/rev/ct-ast test/ast/errors/trait_array_multidim.ct -o /tmp/r_multi.c ; echo rc=$?
test/ast/errors/trait_array_multidim.ct:18:1: error: a multi-dimensional array cannot hold trait-carrying values
rc=1
```

补强：287 产物运行输出与 `prog.expected.out` 一致（`diff` rc=0），288 无初值数组仍保留 1 个 constructor
且运行一致。逐条对照见 [复核结论](../../docs/reviews/2026-11-17-fix-closeout-rev-verdict.md) §2.1；
同一 HEAD 的 `check-all` 11 道门禁绿、`check-ast` 1463/0。
