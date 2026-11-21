# conformance 差异登记（v1）

契约 v1 的 CT 侧与 shell 侧**共用** `v1/` 的数据（[PKG-15](../../../issues/packages/pkg-15-conformance-suite.md)）。
本文件登记两侧**已知且允许**的差异；`run.sh` 比较的是退出码 + 类别 + 摘要，不比较诊断句子。
未登记的任何差异都会让 `run.sh` 变红——「静默跳过」不被接受。

| # | 差异 | 为什么允许 | 谁覆盖 |
| --- | --- | --- | --- |
| D1 | 诊断**措辞**不同（CT 打 `ctc:` 前缀与完整句子；shell 只输出类别） | 契约只要求类别与退出码一致；句子由 `test/ast/p83_verify.sh` / `p83_legacy.sh` 逐字钉住 | `run.sh` 只比类别 |
| D2 | ~~`ct get` 对 **>6 字段**的行读前六字段；`ct index verify` 要求恰好六字段（IV-1）~~ **已消除（PKG-19，v0.88.3）**：两者共用同一行解析/校验，`ct get` 对**选中行**的 `ntok != 6`（五字段 legacy 除外）同样报 `field-count`；`ct get` 仍不做全文件扫描（未选中坏行不阻塞） | 不再是差异；保留 D2 编号供历史引用（`docs/design/phase83.md` §441） | `pkg19_20_rows.sh`；`p83_verify.sh` |
| D3 | 五字段旧行的消息 `<spec>`：`ct get` 用**请求写法**（`acme/old`），`ct index verify` 用**行内 name**（`old`） | 旧行没有 publisher 字段，verify 无法知道请求会写哪个 publisher；判定（硬错）相同 | 契约 §4.4；`p83_legacy.sh` 分别钉住两种拼写 |
| D4 | `ct get` 只在**请求命中**旧行时失败；`ct index verify` 扫描全文件逐行报旧行 | 两者职责不同：一个解析一个请求，一个审计整份索引 | `p83_legacy.sh` 的 mixed index 用例 |
| D5 | shell digest 用 `sha256sum`/`shasum` + `LC_ALL=C sort`；CT 用自带 SHA-256 + `strcmp` | 两套独立实现正是基准的目的；三向量逐字节一致 | `run.sh` digest 段 |
| D6 | shell digest 不支持文件名含换行；CT 支持任意字节路径 | POSIX shell 的 `while read` 以换行为分隔；这类路径不在包布局允许范围内 | 本表 |
| D7 | shell 清单实现只做 PK-1/2/5/8；R1–R3/S1–S5 不做 | 与 `ct pkg check` 的既有承诺一致（D-014 第 2 条）；后者归 index CI | 本表；`v1/README.md` |
| D8 | `ct pkg check` 的 PK-8 扫描跳过 `.git`/`docs`/`issues`/`battle`/`test`、`*.md` 与 >262144 字节文件；shell 实现逐条镜像 | 两侧必须同判，否则 `absolute-I` 数据会漂移；改动任一侧须同步改数据与本节 | `run.sh` manifest 段 |

## 变更纪律

- 改数据（新增/修改 case）→ 同时改 `cases.tsv` 与 `expect.tsv`，并确认两侧都过；
- 改 CT 或 shell 任一实现 → 先跑 `run.sh`，任何新差异先登记在本表，再决定是否修；
- 契约算法（§3.3）变化 → 新建 `v2/`，保留 `v1/` 作为历史基准；不原地改期望摘要。
