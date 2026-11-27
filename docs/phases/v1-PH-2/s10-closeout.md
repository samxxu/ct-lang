# v1-PH-2 · S10 收口清单（已执行，2026-11-27）

> 中文。REQ 起草 2026-11-27，锚点 `3c92e20d`。
> 依据：[卡 §2 S10](card.md)、[E-V3-11](card.md#3-退出判据)、
> 卡内「S10 的版本纪律」注。
> 本文是**施工用清单**，不是新的退出判据；判据以卡为准。**S10 已执行**：结果与原始输出见
> [卡 §6–§7](card.md)；本文件只保留施工口径与待所有者事项。

## 1 当前快照（2026-11-27）

| 项 | 状态 |
| --- | --- |
| S0–S8 尾、S8c、S9 | 已入库；S8r2 单文件默认 LIR、known-gap 清零；S8 尾 D5/D6/外壳落盘（`Emitter.h.ct` 9872→1545）；S8 收尾 D-013 真 lowering（自举 1638/1638、语料 498/498）与外壳行化（882 夹具 0 差异） |
| S8 §5 签字 | DEV 已补 S8 收尾与外壳收尾两行证据；REV 仍「待签字」（[差异清单 §5](../../reviews/2026-11-27-s8-ir2-diff-list.md#5-签字) 与 [最终收尾文档](../../reviews/2026-11-27-s8-closeout-lmodule.md) 两份） |
| S8a（LANG-31，可砍） | **deferred**：未开工，issue 已转 `deferred`；触发条件见卡 §6 E-V3-9d |
| S8b 剩余 | §3.6 已补 D6 函子、D4（`backend/mem`）、D2 符号表行块、D3a–c；仍余 D3 其余 `snprintf`（`Pkg` 53 / `Symbols` 41）、D2 `funcs`/`vars`/`structs` 大表、D4 其余域 |
| 未关闭 issue | DESIGN-1、TEST-27（`open`）；LANG-31 已转 `deferred` |
| ADR | `D-030`（print API）仍 `proposed`，待 REVIEW 签收；本轮不代签 |

## 2 开工闸（不清零不进 S10）

| # | 前置 | 判据 | 负责人 |
| --- | --- | --- | --- |
| G-1 | S8r2 + S8 尾签字 | [差异清单 §5](../../reviews/2026-11-27-s8-ir2-diff-list.md#5-签字) 有 DEV 证据行（含 S8 尾）与 REV「通过」行，且注明「回退 ≠ 已降级」 | DEV → REV |
| G-2 | S8b 生成 C 可读性 | REVIEW 签字（E-V3-9b） | REV |
| G-3 | S8b 剩余处置 | D2 符号表 / D3 / D4 / D6 二选一：做完，或由所有者裁定 deferred 并写入本文 §6 | 所有者 |
| G-4 | S8a 去留 | 同上：做（E-V3-9d）或整体 deferred（卡允许） | 所有者 |
| G-5 | `D-030` 签收 | 状态改 `accepted`，签收行非作者席位 | REV |
| G-6 | DESIGN-1 / TEST-27 | 转 `verified` 或明确 deferred，附证据 | REQ / REV |

## 3 版本 bump 清单

**原则**：源码、golden、版本串分提交；先 bump 后重基线，重基线单独提交。

| # | 对象 | 动作 | 数量 |
| --- | --- | --- | --- |
| V-1 | `selfhost/ct-ast/main.ct` | `CTC_VERSION "1.1.0"` → `"1.2.0"` | 1 处 |
| V-2 | seed | `bash selfhost/gen-seed.sh`，整目录 + `bootstrap/MANIFEST.sha256` 提交；两轮逐字节 | `bootstrap/ct-ast/**`（含 `main.c` 版本串） |
| V-3 | `test/goldens/ast/**` | 25 份静态 golden 的 banner 随版本变化，按既有重基线流程重生成（不手改） | 25 |
| V-4 | `test/cases/**` | `.expected.c` / `.expected.h` banner 重生成 | 50 |
| V-5 | 版本断言脚本 | `test/ast/p80_docs.sh`、`p81_box.sh`、`p82_docs.sh`、`p83_verify.sh`、`p83_legacy.sh`、`pkg19_20_rows.sh` 里的 `1.1.0`/`v1.1.0` 字面量 | 6 个脚本 |
| V-6 | 其他带版本串的夹具 | `test/modules/p39_lib`、`test/conformance/pkg/v1/index` | 2 |
| V-7 | 文档 | `README.md`（头行与两处「v1.1.0 的实测」）、`docs/README.md` 头行、`docs/roadmap.md` 的 v1-PH-2 行（收口版本 `v1.2.0`、状态 ✅、单元格只写索引） | 3 |
| V-8 | 卡 | v1-PH-2 卡状态转「完成」，§7 收口表补齐 E-V3-1…11 | 1 |
| V-9 | 流水账 | `docs/history/phase-log.md` 版本记录表加 `v1.2.0` 行 | 1 |
| V-10 | 指标 pin | `p88 live pin`、`test/ir/README.md` 覆盖率若随版本或代码变化，同批校准 | 视实测 |
| V-11 | [stable-subset](../../stable-subset.md) 分档更新 | 为本期新能力补行或改档：自定义下标协议（D-028）、函子签名（D-029）、`Str`/`String` 的 `print`/`println`（D-030）、`c-boundary` 默认 strict（S9）；泛型 ADT 行已标「v1.2.0 起」 | 4 条 |

**V-3 例外**：若 25 份 golden 与版本无关（实测确认），则跳过，并在 S10 记录里写明「实测无 banner」。不要凭印象跳过。

## 4 冷/热构建（不立项）

按 [roadmap 未排期项](../../roadmap.md) 的口径，在 S10 收口提交上各测一次，写入流水账：

| # | 动作 | 记录 |
| --- | --- | --- |
| C-1 | 冷构建：清 build cache 后 `ct build`（或等价入口）计时 | 用时、机器、commit |
| C-2 | 热构建：同树连跑第二次计时 | 同上，并给出冷/热比值 |
| C-3 | 结论 | 只记录不设门禁；异常时进需求池，不在 S10 修 |

## 5 分发产物

| # | 动作 | 判据 |
| --- | --- | --- |
| P-1 | Linux x86-64 上 `bash selfhost/make-dist.sh` | `dist/ct-linux-x64.tar.gz` + `.sha256`；**dist 不入 git** |
| P-2 | 产物自检 | `tar -tzf` 得 `ct` 与 `ctc` 链接；`./ct -v` == `1.2.0`；`sha256sum -c` 通过 |
| P-3 | 冒烟 | 用产物编译并运行 `examples/50_ref_out`、`examples/52_box_new`（与 `release.yml` 同款断言） |
| P-4 | 文档 | `docs/dist.md` 的示例版本串与稳定 URL 不需改（`v<MAJOR>.<MINOR>.<PATCH>`）；如示例写死旧版本，同批更新 |

## 6 收口记录必写内容

S10 提交里的收口记录（卡 §7 或流水账）必须回答，缺一不算收口：

1. **S8a 去留**：做了 → 附 E-V3-9d 证据；没做 → 记 `deferred`、理由与触发条件（卡已授权）。
2. **S8b 剩余**：D2 符号表 / D3 / D4 / D6 各自「已做 / 不做 + 理由」，附最终 LOC 与计数（自由函数 / `realloc` / `snprintf` / 判别式 / `Vec` / `Result`）。
3. **S8 §3d 剩余边界**：[差异清单 §3d](../../reviews/2026-11-27-s8-ir2-diff-list.md#3d-仍未做剩余清单) 四条照抄一遍——外壳未完全 LModule 化、「回退改真修复」技术债、覆盖率数字、"回退 ≠ 已降级"。
4. **issue 收口**：DESIGN-1、TEST-27、LANG-31（或 deferred）、LANG-30（已 `verified`）逐条状态。
5. **ADR**：`D-030`（及 S8a 若做的 `D-031`）状态。
6. **门禁原始输出**：§7 每一项的末行。

## 7 门禁矩阵（S10 提交前全绿）

| 门禁 | 命令 | 期望 |
| --- | --- | --- |
| 全量 | `bash selfhost/check-all.sh` | 全绿（门数按当期实际，卡上写 8/9 时以脚本输出为准） |
| 语料 | `bash selfhost/check-ast.sh <ct>` | fixpoint，0 失败 |
| 静态 golden | `bash selfhost/check-goldens-ast.sh` | 25/25 逐字节 |
| seed | `bash selfhost/check-seed.sh` | 两轮逐字节 |
| 告警 | `bash selfhost/check-warnings.sh` | 0 条 |
| sanitizers | `bash selfhost/check-sanitizers.sh` | 无报告 |
| 文档 | `python3 test/docs/check-docs.py` + `--selftest` | OK |
| 台账 | `bash tools/check.sh g6` | OK，无 `open` 残留（或 deferred 有记录） |
| 治理 | `bash tools/check.sh g0 && bash tools/check.sh g1 && bash tools/check.sh g8` | OK |

## 8 禁止项

- **不自动打 tag、不自动发 release**：annotated tag 与 GitHub Release 由所有者手工验证后创建（卡内版本纪律）。
- 不在同一提交里混「版本串 bump」与「语义/实现改动」。
- 不改已发布 tag，不改 `test/archive/**`。
- 不为凑绿改判据；判据冲突就地停并改卡。

## 9 建议提交切分

1. `chore(seed): v1.2.0 前 seed 重生成`（若与版本无关的代码已定）
2. `chore(release): CTC_VERSION 1.2.0 与 25+50 份 golden 重基线`
3. `docs(release): README / docs/README / roadmap / 卡 / 流水账 v1.2.0`
4. `docs(release): S10 收口记录（S8a、S8b、§3d、issue、门禁输出）`

## 10 待所有者裁定

| # | 问题 | 影响 |
| --- | --- | --- |
| O-1 | S8a（LANG-31）做还是 deferred | **本轮结论：deferred**（卡已授权可砍）；未做 `D-031`，触发条件见卡 §6 |
| O-2 | S8b 剩余 D2 符号表 / D3 / D4 / D6 做多少 | **2026-11-28 补**：D6 函子、D4（`backend/mem`）、D2 符号表行块、D3a–c 已落（[dogfooding §3.6](../../planning/dogfooding.md)）；仍余 D3 其余 `snprintf`（`Pkg` 53 / `Symbols` 41）、D2 `funcs`/`vars`/`structs` 大表、D4 其余域，如实登记在卡 §6 E-V3-9b |
| O-3 | `v1.2.0` 的 tag 与 release 何时手工执行 | **待所有者**；精确命令与校验项见卡 §7.5 |

## 11 执行结果（2026-11-27）

| 项 | 结果 |
| --- | --- |
| 版本 | `CTC_VERSION 1.2.0`；README / docs/README / AGENTS / roadmap / phase-log / stable-subset 同步 |
| seed | 73 `.c` + 140 `.h` 重生成；`check-seed` 两轮逐字节 + 手改负例红 |
| stable-subset | v1.2 冻结：下标协议、函子、`print`/`println`、默认 strict 入「已冻结」；6 个到期条目转档；保留 1 条「冻结中」 |
| 冷/热构建 | 4.17s / 3.47s（比值 0.83）；只记录，不设门禁 |
| dist | `ct-linux-x64.tar.gz`（static musl，ELF x86-64）；sha256 `98130730155f88934a2c4b4d0ce82e222bc81fc25e34a6fc0fdcf7736a0e28d3`；不入 git；冒烟 UNVERIFIED（无 QEMU 资产） |
| 门禁 | `check-all` 8 门、`check-seed`、sanitizers 662、`check-docs`、`g0/g1/g6/g8`、`test/ir` 15 checks |
| tag/release | **未创建**（按所有者版本纪律）；手工命令见卡 §7.5 |
