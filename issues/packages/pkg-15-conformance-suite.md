# PKG-15 · 包管理 conformance 数据与 runner

| 项 | 值 |
| --- | --- |
| 模块 | packages（跨仓验收） |
| 定性 | 能力缺口（无双实现对照基准） |
| 严重度 | Medium |
| 锚点 | v0.79.0（2026-11-20） |
| 文件 | [契约 v1](../../docs/planning/ct-pkg-get-contract.md) §3.3/§9、[D-014](../../docs/decisions/D-014.md) |
| 状态 | verified |
| 处置证据 | **verified（REV 复核，2026-11-22，HEAD `38cd4ae4`；`ct-ast` v0.88.2）** |

## 现象

`package-check.sh` 与 `ct pkg check` 各自实现同一批规则，缺一套机器可执行的共同基准；
digest 算法只有文字描述，没有可回归的输入输出对。

## 交付

1. **数据**（版本化，纯文本）：
   - 合法/非法 `ct.pkg`（缺 publisher、`local`、坏 `ns-root`、未知键等）；
   - 合法/非法索引行（五字段旧行、字段数、digest 拼写、tag/版本不一致）；
   - digest 输入输出对：至少包含契约 §3.3 的三个向量；
2. **runner**：同一份数据分别喂 `ct` 与 shell，逐条比对退出码与诊断类别；
3. **基准**：契约 v1 发布时给出“两边一致/已知差异”清单。

## 验收

- 数据可被第三方 registry 直接复用；
- digest 三向量与契约 §3.3 完全一致；
- runner 在 CI 中可对固定 `ct` 版本重放；差异必须显式登记，不得静默跳过。

## 关联

- [PKG-12](pkg-12-contract-v1-doc-gaps.md)（判据编号）、[PKG-13](pkg-13-legacy-five-field-row-hard-error.md)（旧行行为）

## §复核（REV，2026-11-22，HEAD `38cd4ae4`）

用 HEAD 构建的 `ct-ast`（`sh .temp/build-ct-ast.sh . .temp/rev-pkg-head`，自报 `v0.88.2`）
重放同一份版本化数据：

```console
$ bash test/conformance/pkg/run.sh --ct .temp/rev-pkg-head/ct-ast
== manifests ... ==
ok   manifest ok-basic (ok)
...
ok   manifest err-absolute-I (absolute-I)
== index ... ==
ok   legal index (3 rows, both sides clean)
ok   index illegal rows: CT matches the expected line/kind map
ok   index illegal rows: shell reference matches the expected map
ok   index: CT and shell reference agree row by row
== digest ... ==
ok   digest vector1 (sha256:4da5a4052a2a0afc6c9bbc7cc33cb153755f6f9e77a6efcb46f664aa17d00000)
ok   digest vector2 (sha256:96c10e74b90d104fb9e789aec2d05189dd090ae1a96a1f739aa74aeaf83986a1)
ok   digest vector3 (sha256:41743c2b7ecea992d7c1135e3fc78d2c0e020731a1199c85c0ef6308a2b7e888)

conformance: 19 passed, 0 failed (data: v1)          # exit 0
```

逐条对照验收：

- **数据可复用**：`test/conformance/pkg/v1/` 是纯文本 + 三个小目录树，`README.md` 写明布局、
  字段、类别与复算命令；格式变更走 `v2/`，不原地改；
- **digest 三向量与契约 §3.3 一致**：`digest/expect.tsv` 三行与契约第 116/128/146 行的
  `sha256:4da5…/96c1…/4174…` 逐字相同；
- **runner 在 CI 中重放**：`selfhost/check-all.sh:119` 的第 8 道硬门禁调用
  `selfhost/check-ast.sh`，后者在 `:1389-1390` 注册
  `p83_probe conformance ... test/ast/p83_conformance.sh`；`.github/workflows/ci.yml`
  的 `ubuntu-gcc` 与 `macos-clang` 作业跑 `check-all.sh`（`:54`、`:80`），
  `ubuntu-clang-smoke` 作业直接跑 `check-ast.sh`（`:108`），因此该 runner 属常规 CI；
- **差异显式登记**：`test/conformance/pkg/differences.md` 8 条（D1–D8），runner 对比退出码 +
  类别 + 摘要，未登记差异即失败，不静默跳过。

结论：`verified`。
