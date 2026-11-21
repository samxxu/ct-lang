# DOC-90 · tutorial 补 `String`/`Str` 与切片专章

| 项 | 值 |
| --- | --- |
| 模块 | docs（tutorial） |
| 定性 | 文档缺口（新特性无教程章节） |
| 严重度 | Medium（v1.0 前用户可见） |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [tutorial §10.13](../../docs/tutorial.md)（PH-36 旧 `Str`）、[spec §4.69](../../docs/language-spec.md)、[spec §4.70](../../docs/language-spec.md)、[guide §3](../../docs/guide-for-c-programmers.md)、[DOC-86](doc-86-readme-v088-rewrite.md) D3 |
| 状态 | open |
| 处置证据 | **实施中（§22/§23 初稿已入库；tutorial-cases runner 待 DEV）** |

## 进展（2026-11-21）

- tutorial 新增 **§22 `String` / `Str`** 与 **§23 切片 `T[]`**，放在 §21 之后，未重排现有章节。
- 判据措辞与 [idioms §3](../../docs/idioms.md) 同源（“这份数据过了这行还要活着 → `String`；
  只看一眼 → `Str`”），不做第二次转述；机制细节只链 spec §4.69 / §4.70。
- 两章各一个完整程序，已实跑：
  - `String`/`Str` → `hello, ct`；
  - 切片 → `14 5`（`sum(s)` 与 `sum(s[1..3])`）。
- 可跑证据已落 fixture：`test/docs/tutorial_cases/string_str.ct`、`slice_sum.ct`；
  [DOC-86](doc-86-readme-v088-rewrite.md) 的 D3-5 清单从 8 条扩到 10 条并指向这两个文件。
- 顶部「按层阅读」第 3 项已从“专章待补”改为指向 §22 / §23 的入口（见 tutorial 顶部）。
- 余项：`test/docs/check-tutorial-cases.sh` runner 与 TSV 清单由 DEV 实现。

## 现象

tutorial 已有 22 个章节，但没有 **PH-79 切片** 与 **PH-80 `String`/`Str`** 的专章：

- §10.13 讲的是 PH-36 的长度前缀 `Str`（低层内建），不是 PH-80 的 owning `String` / 借用 `Str` 心智模型；
- 顶部“按层阅读”目前只能把这两项指到 spec §4.69 / §4.70 与 guide §3；
- README §0.5 已有三个可跑程序，tutorial 作为“逐章教程”反而缺最常用的一层。

新用户从 tutorial 学不到：什么时候用 `String`、什么时候用 `Str`、`Str` 能存哪里、
字段/全局/容器怎么释放、切片传参为什么替代 `int *a, int n`。

## 目标

新增两章，**只写教程、不重抄 spec**：

- **§22 `String` / `Str`**：
  1. 判据：过了这行还要活着 → `String`；否则 `Str`；字面量 immortal；
  2. 基本操作：`String s = "x";`、`s.as_str()`、`s.to_string()`、`s.cstr()`、`len` 是字节数；
  3. 存放位置：`String` 字段合法；`Str` 字段 / `Map` 键硬错；`Vec<Str>` / `Option<Str>` /
     ADT 负载 / 全局可编译但存视图；
  4. 释放分层：局部/参数自动；`String` 字段在宿主 `use Drop` 且无显式 impl 时有胶水；
     `Vec`/`Map` 字段、全局、ADT payload 由作者处理；环仍泄漏；
  5. `char *` 方法：`import std::str::CharStr;`（0.19.0 及以前 `std::str::String`），
     没有 `"x".to_string()`；
  6. 一个完整程序 + 实测输出（沿用 README §0.5 的 `hello, ct`，不复制措辞）；
  7. 与 §10.13 的关系：§10.13 是 PH-36 的低层 `Str`，本章是 PH-80 的完整心智模型，不删旧章。
- **§23 切片 `T[]`**：
  1. 表示 `{ptr,len}`；`int[] s = a` 自动补长度；子切片 `a[lo..hi]` 半开；
  2. 传参：`sum(int[] a)` 替代 `sum(int *a, int n)`；`T a[]` 作形参/字段已弃用；
  3. 位置白名单：参数 / 局部 / 返回；字段、全局、容器、泛型实参、闭包捕获硬错；
  4. 下标 `s[i]` 带边界 trap，`s.get(i)` 软访问；`const T[]` 写硬错；
  5. 一个完整程序 + 实测输出（`sum` 例子，输出与 §0.5 不同、可独立复核）。

## 章节位置与编号

- **不改现有编号**：新增 `## 22.` / `## 23.`，放在 §21 之后；不重排 §17–§21，
  避免 tutorial 锚点迁移（与 [DOC-88](doc-88-spec-split-decision.md) 的锚点冻结口径一致）。
- 顶部“按层阅读”把第 3 项从“专章待补”改为指向 §22 / §23；
- §16「下一步」补两行指向 §22 / §23；
- [DOC-86](doc-86-readme-v088-rewrite.md) 的 D3-5 `tutorial-cases` 清单同时收录这两章的例子。

## 验收

- §22 / §23 各至少一个完整程序，命令与输出实跑一致（ct-ast v1.0 基线）；
- 每条判据能在 spec §4.69 / §4.70、guide §3 或实测找到出处；
- 不重抄 spec 的语法表；篇幅各控制在教程现有章节的中位长度；
- 顶部路标与 §16 指向新章；`tutorial-cases` 新增两条用例；
- `check-docs` 绿。

## 非目标

- 不重写整个 tutorial，不重排现有章节；
- 不删 §10.13（PH-36 历史能力保留，只在 §22 里说明关系）；
- 不把 spec §4.69 / §4.70 的全文搬进教程；
- 不在 v1.0 冻结期做（v1.1 落地；若需要提前，单独裁定）。

## 关联

- [DOC-86](doc-86-readme-v088-rewrite.md)（D3 与 tutorial-cases 夹具）
- [DOC-88](doc-88-spec-split-decision.md)（锚点冻结与编号稳定）
- [guide-for-c-programmers §3](../../docs/guide-for-c-programmers.md)
