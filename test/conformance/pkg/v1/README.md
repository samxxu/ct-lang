# 包管理 conformance 数据 v1

本目录是契约 v1 的**机器可执行基准**（[PKG-15](../../../../issues/packages/pkg-15-conformance-suite.md)，
契约 [§3.3/§6.1](../../../../docs/planning/ct-pkg-get-contract.md)）。同一份数据同时喂给：

- **CT 侧**：`ct pkg check`、`ct index verify`、`ct get <local-dir>`；
- **shell 侧**：`../reference.sh` 的独立实现；
- 以及 `../run.sh` 里写死的期望行。

数据是纯文本 + 三个小目录树，第三方 registry 可直接复用；格式变更一律新建 `v2/`，不原地改。

## 布局

```text
v1/
  manifests/cases.tsv        # id <TAB> ok|err <TAB> 类别
  manifests/<id>/ct.pkg      # 每个 case 一个包目录
  index/legal.index          # 3 条合法六字段行
  index/illegal.index        # 合法/非法混合，行号是判据的一部分
  index/cases.tsv            # line <TAB> ok|err <TAB> kind <TAB> note
  digest/vector1..3/         # 契约 §3.3 的三棵树
  digest/vector2.excluded.tsv# vector2 的排除项（git 不能跟踪嵌套 .git/）
  digest/expect.tsv          # vector <TAB> sha256:<64 hex>
```

## 清单类别（manifests）

`ct pkg check` 的承诺仍是 PK-1/2/5/8（D-014 第 2 条），类别与判据的对应：

| 类别 | 判据 |
| --- | --- |
| `ok` | 四项全过（`ok: 4 criteria`） |
| `missing-manifest` | PK-1：`ct.pkg` 不存在/不可读 |
| `missing-name` / `missing-publisher` / `missing-version` / `missing-nsroot` | PK-2：身份字段缺失 |
| `local-publisher` | PK-2：`publisher = local` 只是占位 |
| `nsroot-absolute` / `nsroot-dotdot` / `nsroot-not-dir` | PK-5：形状与存在性 |
| `absolute-I` | PK-8：包树内绝对 `-I` |

R1–R3（字符集、版本形状、tag）与 S1–S5（`--strict`）归 index CI / 包仓，**不在**本数据集。

## 索引行（index）

六字段：`name version publisher git-url tag sha256:<64 lowercase hex>`。
`illegal.index` 的行号即测试 id；`cases.tsv` 的 `line` 必须与文件行号一致（注释/空行也计数）。
`kind` 取契约 §4.4 的 IV-1…IV-6 类别：`field-count`、`legacy-five-field`、`identity`、
`tag-version`、`digest`、`duplicate`。合法行不出现在 `cases.tsv` 的 `err` 里。

## 摘要三向量（digest）

`vector1` / `vector2` / `vector3` 的字节与契约 §3.3 完全一致：

- `vector3/nul.bin` 是 4 字节 `6e 75 00 6c`（嵌入 `\0`，不带结尾 LF）；
- `vector2` 的 `.git/y`、`vendor/x`、`.ctcache/z` 由 runner 按 `vector2.excluded.tsv`
  现场创建（git 不能跟踪嵌套 `.git/`），用于证明排除规则；
- `expect.tsv` 的摘要是 2026-11-21 用 `ct get <local-dir>` 与独立 shell 实现
  各测一次、逐字节一致的输出。

复算一条：

```console
$ sha256sum ...   # 见 ../reference.sh digest <tree>，或
$ sh test/conformance/pkg/reference.sh digest test/conformance/pkg/v1/digest/vector1
sha256:4da5a4052a2a0afc6c9bbc7cc33cb153755f6f9e77a6efcb46f664aa17d00000
```

## 怎么跑

```console
$ bash test/conformance/pkg/run.sh --ct ./ct-ast
$ sh test/ast/p83_conformance.sh ./ct-ast      # check-ast 的探针包装
```

差异只允许出现在 `../differences.md`；runner 对未登记的差异一律失败，不静默跳过。
