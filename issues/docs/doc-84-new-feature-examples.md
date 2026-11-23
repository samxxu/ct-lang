# DOC-84 · 新特性最小 example（ref/out、slice、box/new、match）

| 项 | 值 |
| --- | --- |
| 模块 | examples / docs |
| 定性 | 文档/样例缺口（P2，非 v1-PH-0 门禁） |
| 严重度 | Low |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) §6、P2-9 |
| 状态 | verified |
| 处置证据 | **延后（2026-11-22，REV）**：文档面已由 tutorial §15/§17/§18/§22/§23 与 README §0.5 覆盖；四条 `examples/5x_*` 需新增 `examples/**` 并接门禁，属 DEV 批次，不在 DOC 席位路径内 |
| blocked-by | 执行触发：v1.0 发布前示例批（或 v1.1 首批）；负责人 DEV；需同时接 `test/run.sh` / `check-ast.sh` |

## 现象

v0-PH-78 之后没有新增 example：`ref`/`out`、切片 `T[]`、`String`/`Str`、`box`/`new`、
leaks、`match`/ADT、`ct index verify` 只有 spec/tutorial/测试，没有可运行示例目录。
教程已更新到 §21，但缺少“最小可跑”的 `examples/5x_*`。

## 期望

新增 4 个 example（每个 20–40 行，带 expected）：

| 目录 | 内容 |
| --- | --- |
| `examples/5x_ref_out` | `ref` / `out` 参数与调用点写法；对比 C 的 `int *out` |
| `examples/5x_slice` | `T[]` 切片、子切片、`sum(int[] a)` |
| `examples/5x_box_new` | `box<T>` / `new`、`at()` 借用、`release()` 失效 |
| `examples/5x_match_adt` | 最小 ADT + 穷尽 `match`；owning payload 显式释放 |

## 验收

- 每个 example 可编译、零告警、运行输出与 expected 一致；
- 接入既有 example/门禁入口（不新建平行 runner）；
- 不引入未实现能力；与 spec/tutorial 的写法一致；
- 不改产品代码。

## 非目标

- 不覆盖全部新特性（`ct index verify` 属包管理 example，另议）；
- 不写长教程（tutorial 已有章节）；
- 不阻塞 v1-PH-0。

## 关联

- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)（P2，非门禁）
- [tutorial.md](../../docs/tutorial.md) §18/§20/§21

## 复核与延后（2026-11-22，REV）

**结论：`deferred`（不改文档代偿；示例目录属 DEV 路径）。**

文档面已覆盖最小可跑写法：tutorial §15 `ref`/`out`、§17 `box<T>`/`new`、§18 ADT/`match`、
§22 `String`/`Str`、§23 切片；README §0.5 另有三段可直接 `ct build` 的完整程序。因此本条
缺的不是“说明”，而是 `examples/5x_*` 目录与门禁接线本身；新增 `examples/**` 超出本批
DOC 的可改路径（只动 `issues/docs/**` 与 `docs/**`），且验收要求“接入既有 example/门禁入口”。

```console
$ find examples -maxdepth 1 -type d -name '5x_*' | wc -l
0

$ grep -rl 'match (' examples --include='*.ct' | wc -l
0

$ grep -rl 'box<' examples --include='*.ct' | wc -l
0

$ grep -rn 'void .*(ref \|void .*(out ' examples --include='*.ct' | wc -l
0
```

**触发/负责人**：v1.0 发布前示例批（或 v1.1 首批），负责人 DEV；四项一次落地
`examples/5x_ref_out` / `5x_slice` / `5x_box_new` / `5x_match_adt`，每项带 `expected.out`
并接 `test/run.sh` + `check-ast.sh`（不新建平行 runner）。落地后本条从 `deferred` 转
`open` 复核；与 [DOC-86](doc-86-readme-v088-rewrite.md) 的 tutorial-cases runner 可同批。

## 落地（2026-11-23，DEV）

**状态未改（`deferred`），待 REV 复核。**

新增四个最小 example，每个 `prog.ct` + `prog.expected.out`，首行 `//@ct-requires: ct-ast`，
由既有 `examples/*/*.ct` glob 自动接入 `test/run.sh` 与 `check-ast.sh`，不新建 runner：

| 目录 | 演示 | 实测输出 |
| --- | --- | --- |
| `examples/50_ref_out` | `ref` / `out` 形参与调用点自动取地址 | `2 3 4` |
| `examples/51_slice` | `T[]`、自动补长度、子切片 `s[1..3]` | `14 5 5` |
| `examples/52_box_new` | `box<T>` / `new`、`at()` 借用、`release()` | `4 4` |
| `examples/53_match_adt` | 穷尽 `match` + `String` 负载显式 `release()` | `hi` |

证据：

```console
$ bash test/run.sh
  ok    examples/50_ref_out/prog.ct (ct-ast)
  ok    examples/51_slice/prog.ct (ct-ast)
  ok    examples/52_box_new/prog.ct (ct-ast)
  ok    examples/53_match_adt/prog.ct (ct-ast)
== summary: 160 passed, 0 failed ==

$ bash selfhost/check-warnings.sh
check-warnings: 506 ok, 0 failed
```

索引已补在 [examples/README.md](../../examples/README.md) 的「新句柄层」一节。

## 复核（REV，2026-11-23）

新增 `examples/50_ref_out`、`51_slice`、`52_box_new`、`53_match_adt`，各带 expected；
`test/run.sh` 160/0，`p88_emit` 3/0，语料 SHA 清单已更新。
