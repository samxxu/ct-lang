# battle/langcap-1 — 九条语言能力缺口的定性

| 字段 | 值 |
| --- | --- |
| 争点 | 九条能力缺口逐条定性：**A** 既有设计/需求已承诺但没实现（bug）；**B** 从未支持（需求）；**C** 明确不做（设计拒绝）。只定性、落库，不动实现 |
| 当前 HEAD | 开工 `3337ac7a`；写作中并行提交 `89b1124b`（登记 LANG-13/14、把 JSON-2 并入 LANG-5） |
| 触发理由 | 负责人判断「前一段时间确实提过要提升这部分能力，其中不少可能是 bug 没实现完」。判定必须回到仓库既有的规范、设计文档与 issue 原文，不能凭印象；本轮组织主张席与反证席逐条对抗 |
| 相关 Issue | LANG-4（下标类型不匹配静默空值）、LANG-5（结果作接收者）、LANG-6（并入 PKG-2）、LANG-13（三级链，`JSON-1`，已修）、LANG-14（`char *` 传 `Str`，`JSON-3`，已修）、SH-73（临时接收者有意边界）、SH-18（限定类型名）、PKG-2（包根 import）、REQ-JSACCESS-1、REQ-INDEX-1；`JSON-2` 按主控交接对应 LANG-5 / SH-73 一族 |
| proposer | REQ（主张「多数是 bug / 没实现完」） |
| opposition | REVIEW（主张「多数是已载明的限制或设计拒绝」） |
| judge | EDITOR |

## 逐条判据

| ID | 条目 | 判据（三选一，必须给依据原文） |
| --- | --- | --- |
| J-1 | namespace 常量（标量 / 数组 / struct 值）、跨单元引用、`.h.ct` 声明 + `.ct` 定义 | 分出「直接定义」「跨单元引用」「C 式分离」三小项，各自判 A/B/C |
| J-2 | 限定名取值 `FsErrCode::FS_ERR_NOT_FOUND` | 判 A/B/C；同时说明 namespace 限定 `ns::FS_ERR_NOT_FOUND` 是否已可用 |
| J-3 | `ct install` 只发 `-I vendor/<包名>`，`src/<ns>/` 布局无法 import | 判「工具/包约定缺陷」或「包布局必须迁就现状」 |
| J-4 | 自定义类型属性访问 `doc.server.host` | 判 A/B/C；不得把「C 字段访问」误当协议 |
| J-5 | 无重载 / 无按键类型分派，`get(char *)` 与 `get(int)` 并存冲突 | 判 A/B/C；区分「静默空值」与「重载不可用」 |
| J-6 | 临时值作接收者（三级链、`doc["server"].has(k)`） | 判 A/B/C；区分方法形态与「下标结果取字段」形态 |
| J-7 | `doc["port"] + 1` 运算符协议；`printf("%s", ref)` 格式化协议 | 两个子项各自判 A/B/C |
| J-8 | `for (e in arr)`；「foreach 只接受一维 C 数组」 | 判 A/B/C；核对 foreach 现状是否已覆盖 `Vec` / `Map` |
| J-9 | 字符串字面量到 `Str` 的隐式转换；诊断级别（warning → cc error） | 转换与诊断级别分开判 |

## 证据要求

按主规范 §7.7 E1–E5：完整命令 + 原始输出、`file:line`（至少 1 条利于己方、1 条不利于己方）、可证伪预测、代价量化、对对方最强论点的 steelman。重点复现：

- `pub const` 标量 / 数组 / struct 值在 `.h.ct` 内直接定义并跨单元引用；
- 同名 `.h.ct` + `.ct` 在 `ct build` 下的产物路径与链接结果；
- `ns::FS_ERR_NOT_FOUND`、`FsErrCode::FS_ERR_NOT_FOUND`、`ns::FsErrCode::FS_ERR_NOT_FOUND` 三种形态；
- `get(char *)` 与 `get(int)` 并存时的 `conflicting types for '<T>_get'`；
- `a["a"]["b"]["c"]` 与 `doc["server"].has(k)` 的两条文案；
- `for (int e in a)` 的 `unexpected token`，以及 `foreach (Vec<int>)` 的 rc=0；
- `ct build` 对 `Str` 形参的 warning 与 `cc` 的 error。

## 纪律

- 只写 `battle/langcap-1/`、`issues/lang/lang-11-*.md`、`issues/lang/lang-12-*.md` 与 `issues/README.md` 的对应行。
- 不修改 `selfhost/**`、`test/**`、`lib/**`、`docs/language-spec.md`、`docs/package-guide.md`。
- 只本地提交，不 push、不打 tag、不 bump 版本。
- 已有 issue 不重复开号；`JSON-1` / `JSON-2` / `JSON-3` 由并行会话持有，本轮只引用不建文件。
