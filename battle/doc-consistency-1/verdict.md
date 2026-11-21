# battle/doc-consistency-1 判决

> **状态：`closed`**（2026-11-21；裁判 EDITOR；1 轮 claim/counter）。
> **判决：B —— 最小集 + 增量补丁。**
> 范围冻结：language-spec / tutorial / patterns 的**必需节**，加 README / llm-guide /
> glossary / architecture 的**事实与链接修正**；不做全量重写，未列入项不得顺手扩写。
> S84e 按本判决执行；A 的完整审计仍由 DOC-77 / DOC-78 / DOC-79 按 issue 闭环。

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 覆盖度 | **B** | A 的全量清单覆盖 6460 行、需要一个 M 任务以上的重写；B 的最小集可按 grep 验收（counter E1/E3） |
| J-2 新特性覆盖 | **B，收紧** | String/Str、切片、`ref`/`out`、`box`/`new`、ADT/match 在 spec 有节、tutorial/patterns 有示例；llm-guide 的内置层清单是**事实错误**，必须修（counter E2） |
| J-3 一致性 | **B** | 同一特性的类型/语义/限制在 spec/tutorial/patterns 三处不矛盾；能力→节号断言沿用 DOC-77 的后续条目 |
| J-4 示例可信 | **B** | 新增 ADT 示例已挂 `check-ast`（290/291/292 + `p84_docs`/`p84_layout`）；其余最小集只修事实，不引入不可运行代码块 |
| J-5 不越界 | **B** | 只动文档；`selfhost/**`、`test/**` 由 DEV 卡负责，battle 席位只写 `battle/**` |
| J-6 范围冻结 | **B** | 最小集清单写入 [PH-84 §2 S84e](../../docs/design/phase84.md)：llm-guide H1 与 `std::str` 行、glossary `Str` 行 + ADT/match 三行、architecture 的 ADT 一行、README 的 spec/tutorial 指针；未列入项不得扩写 |

## 2 方案 B（冻结口径）

1. **必需节**（已有或随 PH-84 补）：spec §4.68 `ref`/`out`、§4.69 切片、§4.70 `String`/`Str`、
   §4.71 `box`/`new`、§4.73 ADT/`match`；tutorial §15/§17/§18；patterns §5/§6。
2. **事实修正**：`docs/llm-guide.md` 的内置层清单补 `String` / `U16String`，`Str` 改为
   借用视图；删掉已不存在的 `std::str` 引用（PH-80 S5b）。`docs/glossary.md` 的 `Str` 行改
   借用视图，补 ADT / 变体 / `match` 三行。`docs/architecture.md` 补一行 ADT/match 的落点。
   `README.md` 加 spec §4.73 / tutorial §18 的指针。
3. **验收**：`test/ast/p84_docs_audit.sh` 对上述最小集做 grep/链接断言，接入 `check-ast`；
   `p84_docs` 继续钉 spec/tutorial/patterns 的必需节。
4. **范围外**：全量重写、逐特性重排、把 DOC-77/78/79 的后续条目并入本卡、改代码/ABI/语言语义。

## 3 不采纳

- **A（全量审计重写）**：超出 PH-84 单卡预算，且 A 自己的证据（llm-guide 的 stale 清单）
  用“事实修正”就能消除主路径误导；剩余审计已有 issue 载体。
- **只改 spec/tutorial/patterns**：不采纳——counter E2 已证明入口文档在带错用户，
  因此 llm-guide/glossary/architecture/README 的事实与链接修正必须进最小集。

## 4 后续动作

- 按 §2 执行 S84e，`p84_docs_audit` 进 `check-ast`；E84-9 以“最小集全绿”判通过，
  并在卡 §7/§8 注明“A 的全量审计仍归 DOC-77/78/79”。
- `docs/design/phase84.md` §1.4/§2/§3 同步本判决；roadmap / session-map / phase-log 记录
  “S84e（B 判决）已纳入 v0.84.0”。
