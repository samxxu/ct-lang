# 反证席（REVIEW）：多数是「已载明的边界」，只有四处真缺口

> 立场：判 bug 的门槛不是「用户觉得应该能写」，而是「仓库里存在一条对用户可见的承诺，实现没有兑现」。
> 本席逐条核对规范、包指南、设计评估与既有 issue；凡原文已写明限制或明确不做的，一律降到 B/C。
> 本席不否认有真缺口：条目 1 的同名单元产物冲突、条目 5 的下标静默空值、条目 6 的字段静默坏 C、
> 条目 8 的规范旧句，这四处要么是 bug，要么是必须改文档的缺陷。

## E1 文档原文（对本席有利）

| 条目 | 原文 | 位置 |
| --- | --- | --- |
| 1 | 「`extern` 的名字不参与 mangling，因为它指向 C 库的符号」 | [language-spec.md:778-779](../../docs/language-spec.md#411-跨单元链接pub-全局与-externct-ast) |
| 1 | `pub` 全局的正规形态是「定义写在 `.h.ct`，`.h` 发 `extern`，`.c` 发定义」，没有「`.ct` 另写定义」的承诺 | [language-spec.md:774-775](../../docs/language-spec.md#411-跨单元链接pub-全局与-externct-ast) |
| 2 | 只承诺「enum 成员的 namespace mangling / 限定名 `app::High`」，没有承诺 enum 类型作用域 `Enum::Member` | [language-spec.md:905-908](../../docs/language-spec.md#414-enum常量表达式与-offsetofct-ast) |
| 3 | 「包仓库的根目录就是包根：`ct.pkg`、`LICENSE` 与源码单元并列，不嵌套子目录」 | [package-guide.md:16](../../docs/package-guide.md#L16) |
| 3 | 「单元声明了文件级命名空间，就必须坐在同名目录里……`<包根>/a/b/`」 | [package-guide.md:42-43](../../docs/package-guide.md#L42-L43) |
| 4 | bindings 的基线写法是 `union` + `int tag`，访问写 `(*p).v.i`，不是属性协议 | [bindings-and-patterns.md:10-47](../../docs/bindings-and-patterns.md#L10-L47) |
| 5 | 规约只承诺「名 + 参数个数」匹配，并把这个洞写成「已知洞（D52-6）」 | [language-spec.md:2628-2630](../../docs/language-spec.md#464-自定义类型下标phase-52仅-ct-ast)、[:2646-2648](../../docs/language-spec.md#464-自定义类型下标phase-52仅-ct-ast) |
| 6 | 「方法调用的结果不能作下一跳接收者」被写进 0.44.1 的逐段实测与现状约束 | [language-spec.md:738-740](../../docs/language-spec.md#4101-链式构建器范式权威定义与两档路径)、[:762-763](../../docs/language-spec.md#4101-链式构建器范式权威定义与两档路径) |
| 6 | SH-73 定性为「有意的实现边界」，建议延后 | [sh73:59-69](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md#L59-L69) |
| 7 | 「`printf` 的格式串与实参类型匹配由用户负责，与 C 一致」 | [language-spec.md:1209](../../docs/language-spec.md#424-浮点字面量ct-ast) |
| 7 | 「明确不做」清单含「运算符重载（`into` 是脱糖例外）」 | [modern-oo-gap.md:339](../../docs/modern-oo-gap.md#L339) |
| 8 | 「不做（D27-4）：`in` 形式、显式绑定名、迭代器、容器协议」 | [language-spec.md:2249-2250](../../docs/language-spec.md#449-foreach-语句形态phase-27仅-ct-ast) |
| 9 | `Str` 的 API 是显式 `str_from(s)`；没有隐式转换条款 | [language-spec.md:2492](../../docs/language-spec.md#456-drop-与长度前缀字符串-strphase-36仅-ct-ast) |
| 9 | 只有 impl 签名漂移是 `ct build` 硬错，其余语义记录是 warning | [language-spec.md:2187-2192](../../docs/language-spec.md#9-诊断与退出码) |

## E2 实测（对本席有利）

```console
# 1. namespace 内直接定义三种常量并跨单元引用 → 通过
$ ./out; echo $?
14
```

```console
# 2. namespace 限定的 enum 成员可用
$ ct build -I . app/main.ct -o out   # main 返回 ns::FS_ERR_NOT_FOUND
rc=0
```

```console
# 3. 文档布局 `acme/acme/Uart.h.ct` 下 `-I vendor/acme` 是正确根
#    `src/<ns>/` 需要 `-I vendor/acme/src`，这是布局选择，不是 import 语义错
```

```console
# 8. foreach 已经覆盖 Vec
$ ct build b.ct -o outb
'cc' -std=c99 ... '-o' 'outb'
rc_vec=0
```

```console
# 9. 同一条语句：ct build 先 warning，cc 再 error；ct check 直接 error
a.ct:3:40: warning: type mismatch: 'has' argument 1: expected 'struct Str', got 'char *'
a.ct:16:16: error: passing 'char[5]' to parameter of incompatible type 'struct Str'
$ ct check a.ct
a.ct:3:40: error: type mismatch: ...
```

## E3 反例（本席自己先认）

- 条目 1 的同名 `.h.ct` + `.ct`：`ct build` 把两者都写成 `.ctbuild/<base>.c`，手加入参后
  `duplicate symbol`。单元表明写 `.ct` 是「实现 / 入口；接口写在同目录的 `.h.ct`」，这不是本席能辩护的，
  判 **A（工具缺陷）**。
- 条目 5 的 `v[0]` 静默空值：虽然规约把 D52-6 写成「已知洞」，但 `REQ-JSACCESS-1` 承诺了修法；
  在修法落地前，用户看到的是「编译通过、运行给错值」。本席同意把它保留为 **High 静默缺陷**（LANG-4），
  只是它的定性是「已登记的需求」，不是「没人知道的 bug」。
- 条目 6 的 `b["k"].v`：**固有**方法/下标结果的方法形态已被 LANG-5（`JSON-2`）在 v0.53.1 工作树修，
  但字段形态（`b["k"].v`）没有守卫、静默发射 `Box_get(&b,"k").v` 交给 `cc`——这是 **A**（LANG-5 已登记）。
  **trait 动态派发**的 `a.m().n()` 仍是 SH-73 的有意边界（C），不要把两者混为一谈。
- 条目 8 的「foreach 只接受一维 C 数组」：与 §4.51 的容器协议、教程 10.8、`modern-oo-gap` §3.7 冲突，
  是 **文档缺陷**，不是语言缺口。

## E4 代价量化（本席建议的动作）

| 条目 | 建议动作 | 量级 |
| --- | --- | --- |
| 1 | 修同名单元产物路径；namespace 分离另立需求 | 小 |
| 2 | 不修；若做 enum 作用域，另立需求 | 小 |
| 3 | 不改工具；在包指南写死「包根 = 单元根」或采纳 PKG-2 | 文档 |
| 4 | 不修；写法回退到 `union` + tag 或 `get` | 0 |
| 5 | 先做 LANG-4 的硬错，再做 REQ-JSACCESS-1 | 中 |
| 6 | 字段形态加守卫（小）；方法形态不动 | 小 / 中 |
| 7 | 不修 | 0 |
| 8 | 改规范旧句；`for-in` 不做 | 文档 |
| 9 | 不修转换；诊断级别交 JSON-3 | 小 |

## E5 对主张席最强论点的 steelman

主张席最强的一条是：**「规范自己都承认不是设计意图，为什么不算 bug？」**（§6.2 的「两条 lowering 的差异」）。
本席回应：承认「不是设计意图」与承认「当前是有意拒绝」并不矛盾。规约在同一节里把当前行为写成
「当前一律拒绝」，SH-73 又给出「保持、延后」的裁决；在没有新判据（求值顺序、临时值生命周期）之前，
把它判成 A 会诱导实现者直接放开，反而制造静默坏 C。正确的定性是 **C（当前设计拒绝）+ B（未来需求）**，
而不是 A（承诺未兑现）。
