# 主张席（REQ）：多数是「承诺过但没做完」

> 立场：负责人回忆「前一段时间提过提升这部分能力」。若仓库里已有对应的规范条款、单元模型或需求条目，
> 而实现没有兑现，就应判 **A（bug）**；只有仓库明确写过「不做」或「未定义」的，才退到 B/C。
> 本席不主张全部是 bug：凡反证席能给出明文拒绝的，本席按判据让步。

## E1 文档与需求原文

| 条目 | 本席依据 | 位置 |
| --- | --- | --- |
| 1 | 单元表把 `.ct` 定义为「实现 / 入口；接口写在同目录的 `.h.ct`」 | [language-spec.md:616](../../docs/language-spec.md#L616) |
| 1 | `pub` 全局跨单元导出已有明文：`.c` 发定义、`.h` 发 `extern` | [language-spec.md:774-775](../../docs/language-spec.md#L774-L775) |
| 2 | enum 成员「命名空间 mangling 与全局变量相同」，`pub enum` 的成员裸名与限定名都能用 | [language-spec.md:905-908](../../docs/language-spec.md#L905-L908) |
| 3 | `ct install` 的语义是「打印一条可直接执行的 `ct build` 命令」 | [package-guide.md:111](../../docs/package-guide.md#L111) |
| 5 | `REQ-JSACCESS-1` 明确承诺「同一类型可并存 `get(char *)` 与 `get(int)`」 | [requirements-pool.md:76](../../docs/planning/requirements-pool.md#L76) |
| 6 | 规约承认两条 lowering 的差异「不是设计意图」 | [language-spec.md:1973-1977](../../docs/language-spec.md#L1973-L1977) |
| 8 | 语法总览的容器遍历一行写的是「数组、`Vec`、`Map`」 | [language-spec.md:148](../../docs/language-spec.md#L148) |
| 9 | `ct build` 的语义诊断里只有 impl 签名漂移是硬错，其余是 warning | [language-spec.md:2187-2192](../../docs/language-spec.md#L2187-L2192) |

## E2 实测（本席复跑）

```console
# 1. `.h.ct` 内直接定义 `pub const` 标量 / 数组 / struct 值 → 通过
$ ct build -I . app/main.ct -o out
'cc' -std=c99 ... '-o' 'out'
$ ./out; echo $?
14
```

```console
# 1. 同名 `.h.ct` + `.ct` 一起进 build → 同一个 `.ctbuild/cfg.c` 被写两次
$ ct build -I . app/main.ct lib/cfg.ct -o out
... '.ctbuild/cfg.c' '.ctbuild/cfg.c' '-o' 'out'
duplicate symbol '_K' ...
```

```console
# 5. 两个 get 并存 → C 层冲突
a.ct:17:36: error: conflicting types for 'J_get'
```

```console
# 6. 三级链 / 下标结果作接收者 → 两条不同的拒绝文案
a.ct:8:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
a.ct:8:1: error: method receiver must be a variable, an element, a call or a field chain
```

## E3 反例（本席自己先认）

- 条目 3：`package-guide.md` §1 明写「包仓库的根目录就是包根……不嵌套子目录」，`src/<ns>/` 不是文档布局。
  这一条本席不坚持判 bug。
- 条目 6：SH-73 把 **trait 动态派发**的方法形态写成「有意的实现边界」，并给了 100–300 行代价；
  这一半本席承认是 C。但**固有方法结果**（`doc["server"].has(k)`）是类型推断缺口，LANG-5 / `JSON-2`
  已在修，本席坚持判 A；字段形态 `b["k"].v` 的静默坏 C 也判 A。
- 条目 7：`modern-oo-gap.md` §6.3 明确把运算符重载列进「明确不做」；本席让步。
- 条目 8：`for ... in` 在 D27-4 里明确不做；本席只坚持「foreach 仅数组」这句已经被实现推翻。

## E4 代价量化（若按 A 修）

| 条目 | 最小改动面 | 量级 |
| --- | --- | --- |
| 1 | `ct build` 的产物命名 / 同名单元配对；不动符号表 | 小（工具层） |
| 2 | 表达式位置 `Type::Member` 解析到 enum 成员 C 名；不动 ABI | 小 |
| 5 | 下标协议加实参类型匹配；重载需内部名 mangling | 中（先做匹配，后做并存） |
| 6 | Emitter 的接收者物化与 hoist 位置；100–300 行 | 中 |
| 9 | 诊断级别提升或插入 `str_from`；只动诊断 | 小 |

## E5 对反证席最强论点的 steelman

反证席最强的一条是：**「规约已经把限制写出来了，所以不是 bug」**。本席接受这个判据，但要求它同时满足两个条件：
（a）写的是「不做」，不是「没写」；（b）写的位置是用户能查到的规范/指南，而不是仅在 issue 里追认。
按这两个条件，条目 1 的同名单元冲突、条目 5 的并存承诺、条目 6 的字段静默、条目 8 的「仅数组」旧句
都仍然站不住：它们要么与明文承诺冲突，要么与实现现状冲突。
