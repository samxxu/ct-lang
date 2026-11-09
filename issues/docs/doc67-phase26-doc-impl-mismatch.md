# DOC-67 · Phase 26 文档与实现对不上：S4 能力、L26-3/L26-4 文案、E1 断言作用域、AGENTS 版本登记

| 模块 | docs |
| --- | --- |
| 严重度 | **P2（Medium）**（行为缺陷本体见 SH-62 / SH-63；本条只记文档侧） |
| 锚点 | `v0.26.0` / `ac1c7cd`（HEAD = `main`） |
| 文件 | [language-spec.md](../../docs/language-spec.md#L1900-L1914)、[language-spec.md](../../docs/language-spec.md#L4163-L4174)、[phase26.md](../../docs/design/phase26.md#L151-L158)、[phase26.md](../../docs/design/phase26.md#L181)、[phase26.md](../../docs/design/phase26.md#L265)、[roadmap.md](../../docs/roadmap.md#L105)、[check-ast.sh](../../selfhost/check-ast.sh#L1159-L1160)、[AGENTS.md](../../AGENTS.md#L92) |
| 状态 | **fixed**（2026-11-09，docs 提交，`v0.26.1`；`verified` 待评审回写） |

## 1. `language-spec` §4.48 的 S4 承诺不成立（中英同错）

- 中 [L1905-1906](../../docs/language-spec.md#L1905-L1906)、英 [L4168](../../docs/language-spec.md#L4168)
  承诺 `(T)` 转型、`sizeof(T)` / `_Alignof(T)`、`offsetof(T, ...)` 都会被替换。实测四类全部不成立，
  其中 `sizeof(T)` 还是退出 0 的静默坏产物（SH-62）。
- 中 [L1913-1914](../../docs/language-spec.md#L1913-L1914) 说“这些都在源码处硬报错，不静默降级”。
  `sizeof(T)` 恰恰是静默降级，两种语言版本的同一句都需要改。
- [phase26.md §2.3](../../docs/design/phase26.md#L151-L158) / [§2.4 L169](../../docs/design/phase26.md#L169)
  把 `N_CAST` / `N_SIZEOF` / `N_OFFSETOF` 列为替换点；解析器从未为 `T` 生成这三类节点，
  这三个替换点目前是死代码。§6.2 的偏差清单也没有登记这一条，违反 §7.1 的第 10 条教训。

## 2. 诊断文案与实现不符

| 文档 | 文档说法 | 实测 |
| --- | --- | --- |
| [phase26.md:181](../../docs/design/phase26.md#L181)、[language-spec:1901-1902](../../docs/language-spec.md#L1901-L1902) | 函数指针类型实参报 `'<type>' cannot be a generic type argument` | `id<int (*)(int)>(fp)` → `error: expected a name in the function-pointer declarator` |
| 同上 | `T` 作类型实参报 L26-4 | 在泛型体内先撞 L26-5；在非泛型上下文 `T` 未注册 → 走 `parse_type` 的其他错误。L26-4 的 `strcmp(targ, tparam)` 分支不可达 |
| [phase26.md:265](../../docs/design/phase26.md#L265) 与 [§2.5](../../docs/design/phase26.md#L181) | 空 `< >` 列表“由 `parse_params` 的既有空参数诊断先行处理” | `T f<T>()` 正常；`f<>` 报 `expected a type parameter name`，不是空参数诊断 |
| [roadmap.md:105](../../docs/roadmap.md#L105) | “L26-4 `void`/函数指针/`T` 作实参” | 只有 `void` 走该文案；另两类不走（见上两行） |

## 3. E1 的命令描述与门禁脚本不一致

[phase26.md](../../docs/design/phase26.md) E1 写“`! grep -E '\bT\b'` 作用于生成 C 的函数段”，
但 [check-ast.sh:1160](../../selfhost/check-ast.sh#L1159-L1160) 实际作用于**整个** `prog.c`：

```sh
&& ! grep -qE '\bT\b' "$work/p26g123/prog.c" \
```

断言更强，不算缺陷，但冻结的退出判据描述与实跑命令不一致，审计时会对不上。另外
`grep -c '__ct[0-9]' ... -ge 2` 只能证明“至少两个实例行”，不能证明“每个类型实参恰好一份”，
与 E1 的文字“每个类型实参一份函数”不完全等价（精度问题见 TEST-17）。

## 4. `AGENTS.md` 的版本 bump 登记清单停在 v0.17.0

[AGENTS.md:92](../../AGENTS.md#L92) 的括号只列到 `v0.17.0`，v0.18.0–v0.26.0 均未登记。
这是**既有漂移**（不是 Phase 26 引入），但 7287044 正好改了这一节的“当前版本”表述却没有顺手补齐，
下一次审计仍会踩到。建议改为“v0.18.0 起的每次 bump 见 roadmap 版本记录”，避免继续逐条追加。

## 修复建议

配合 SH-61 决定“实现还是删承诺”：若实现，改 §4.48/§2.3/§2.4；若不实现，把三处删掉并在 §6.2 登记偏差。
同时修正上表四行文案、E1 的断言作用域描述，并把 AGENTS.md §2 的 bump 清单改成可维护的写法。

## 修复（`v0.26.1`，docs 提交）

配套 SH-62 选择「实现」后，逐项对齐：

1. `language-spec` §4.48（中英）：四处类型位改写为「成立」；函数指针 / 数组类型实参在解析期先报各自的精确文案；补 `va_arg(ap, T)`；`struct`/`union`/`enum` 标签不替换；删除「不静默降级」的失实表述，改为「解析期无法识别的形态一律硬报错；可识别的类型位不会把 `T` 漏进产物」。`phase26` §2.3/§2.4 的替换点补 `_Alignof` / `N_VAARG`，§6.2 登记三条偏差。
2. 诊断文案：§2.5 表按实测改写——L26-3 只覆盖多参数，空 `<>` 报 `expected a type parameter name`；L26-4 只覆盖 `void`（`T` 作实参的分支在非泛型上下文不可达，已注明）；函数指针 / 数组报解析期各自的文案。`roadmap` v0.26.0 行同步改为「L26-4 `void` 作实参」。
3. E1：作用域写明**整份生成 C**（与 `grep` 实跑一致），实例计数改为精确 `-eq`，并补 `id__ct1` 定义恰 1 份。
4. `AGENTS.md`：版本 bump 清单改为「v0.4.0 至今的全部版本，逐次见 roadmap 版本记录」，不再逐条追加；当前版本同步 `v0.26.1`。

验证：

```console
$ python3 test/docs/check-docs.py
check-docs: OK (863 relative links in 173 files, v0.26.1, 11 hard gates, 10 phase status, 3 适用版本 header(s))
```
