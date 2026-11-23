---
phase-id: v0-PH-54
version-minor: 54
---

# Phase 54 · ct-pkg 共享库包体系（切片 S0：观测与只读骨架）

**状态：完成**（S0–S7，v0.54.0–v0.62.0；原 S4 包仓对齐属包外，不在本相跟踪）

| 项 | 值 |
| --- | --- |
| 依据 | [提案 §10 S0](../../proposals/ct-pkg-shared-store.md)、[需求 SP-002/003/004/018/024/027](../../planning/ct-pkg-shared-store-requirements.md) |
| 版本位 | v0.54.0–v0.58.0（S0–S3、S5/S6 各一个 MINOR；v0-PH-54 多占 4 个 MINOR，相位表见 [AGENTS §0.3](../../../AGENTS.md#03-偏离项)） |
| 只动 | `selfhost/ct-ast/tool/pkg/Pkg.h.ct`、`selfhost/ct-ast/main.ct`、`test/pkg/run.sh`、`docs/**` |
| 不碰 | `selfhost/ct-ast/frontend/**`（含其他会话在改的 `TypeCheck.h.ct`）、`selfhost/l2/**`、golden |

## 1. 目标

在不改变任何既有行为的前提下，先让工具**看得见**现状：

1. `ct.lock` 有格式识别：无 `# ct-lock 2` 头即 v1，读取时告警；`ct install` 的输出多一行注释标明格式。
2. 新增只读子命令 `ct pkg check <dir>`，按 PK-1/2/5/8 判包仓，缺 `publisher` / `ns-root` 的包第一次能被机器判出来。
3. 现状契约与陷阱写进包指南与术语表；实测缺陷按 bug / 诊断缺陷 / 需求三档落库。

**不做**：不落共享库、不读 `ns-root` 生成 `-I`、不改 `ct get`、不改 `ct build`、不写 v2 lock。

## 2. 交付物

| # | 交付 | 文件 |
| --- | --- | --- |
| D1 | v1/v2 lock 识别 + `ct install` 的 `# lock-format:` 注释 + v1 告警 | `selfhost/ct-ast/tool/pkg/Pkg.h.ct` |
| D2 | `ct pkg check <dir>` 只读骨架（PK-1/2/5/8） | `selfhost/ct-ast/tool/pkg/Pkg.h.ct`（`install_main`）、`selfhost/ct-ast/main.ct` |
| D3 | S0 夹具与门禁断言 | `test/pkg/run.sh` |
| D4 | 现状契约与陷阱、术语统一 | `docs/package-guide.md`、`docs/glossary.md` |
| D5 | 6 条缺陷落库 | `issues/packages/pkg-3…pkg-8-*.md` |
| D6 | 提案并入裁定、需求定稿、roadmap 版本位 | `docs/proposals/ct-pkg-shared-store.md`、`docs/planning/ct-pkg-shared-store-requirements.md`、`docs/roadmap.md` |

## 3. 任务清单

每项可单独回滚；实现与夹具同一次提交转绿。

| # | 任务 | 交付物 | 验收命令 | effort |
| --- | --- | --- | --- | --- |
| T1 | lock 格式识别 | `pkg_lock_format()` + `install()` 注释与告警 | `cd <旧工程> && ct install` stdout 末行 `# lock-format: v1`，stderr 含 `ct.lock is v1` | S |
| T2 | `pkg check` 骨架 | `ct_pkg_pkg` + `pkg_check` + 两个 static | `ct pkg check test/pkg/s0/good` RC=0 | M |
| T3 | 夹具 | `test/pkg/run.sh` 新增 `== S0 ==` 段（5 个断言） | `bash test/pkg/run.sh` 全绿 | S |
| T4 | 文档 | 包指南 §8、术语表 4 条、6 条 issue | `test/docs/check-docs.py` RC=0 | M |

## 4. 判据（二值）

| # | 判据 | 验收 |
| --- | --- | --- |
| J1 | 旧工程 `ct install` 的 stdout 只比 v0.53.0 多一行 `# lock-format: v1`，其余逐字节不变 | `diff <(旧输出) <(新输出)` 仅差该行 |
| J2 | `ct install --help` / `ct build` / 其他子命令输出不变 | 既有 `test/pkg/run.sh` 断言全绿 |
| J3 | `test/pkg/run.sh` 的 S0 夹具 `$work/s0/nopub`（缺 `publisher`）`ct pkg check` RC≠0，且 stderr 含 `is missing 'publisher'` | 仓内夹具，随 `test/pkg/run.sh` 执行 |
| J4 | 四键齐备、`ns-root` 存在且无绝对 `-I` 的包 RC=0，stdout 含 `ok: 4 criteria` | 直接跑 |
| J5 | `ns-root` 缺失 / 绝对 / 不存在 分别命中 §8 对应文案 | 三个夹具 |
| J6 | `cflags = -I /abs/path` 的包 RC≠0 且含 `absolute -I` | 夹具 |
| J7 | `ct pkg check` 只读：运行前后包目录摘要一致 | 前后 `shasum -a 256` 比对 |
| J8 | 全量门禁 `bash selfhost/check-all.sh` 绿；`test/docs/check-docs.py` 绿 | 直接跑 |

## 5. 红证

实现前先落夹具并真实跑出失败，记录退出码与文案；实现与夹具同一次提交转绿，提交正文带一行：

```
red: rc=<N>, "<失败文案>"
```

禁止用实现后的复跑顶替红证；禁止改判据、改 golden、改版本号凑绿。

## 6. 回滚

S0 只新增只读子命令与一行输出注释，回滚 = `git revert` 单个提交；不涉及仓库格式、不涉及 golden。

## 7. 偏差与约束（实测）

| # | 偏差 | 处理 |
| --- | --- | --- |
| D-1 | `ct-ast` 的 `MAX_FUNCS` 曾是 `256` 的**整程序**预算且已用满：新增任何函数（哪怕独立单元）都会让 `check-ast` 的 self-compile 报 `too many functions in unit '...' (limit 256)`。**已裁定并落地升到 512**（4 处镜像宏 + cap fixture 同步），该阻塞解除 | S0 期间 `ct pkg check` 的解析与目录扫描内联在 `Pkg.h.ct` 的 `install_main`，`main.ct` 把 `pkg` 子命令路由到 `ct_pkg_install`；S1 起可按常规拆单元，不必再为零函数额度绕行 |
| D-2 | 越界文案已改为全程序口径 `too many functions (limit N, whole program)`，不再写 `in unit X` | 依据：`ParseSupport.h.ct` 的判界点、`Expr.h.ct` 的泛型实例路径与 `check-ast.sh` cap fixture |
| D-3 | 为容纳 v1 告警，`test/pkg/run.sh` 原有的「无 requires 的包静默安装」断言改为「除 v1 告警外无 stderr」 | 判据不放宽：仅放行这一条已文档化的新告警 |

## 8. S0 收口记录（2026-11-15）

| 项 | 结果 |
| --- | --- |
| D1 | v1/v2 lock 识别；`ct install` 输出 `# lock-format: v1/v2`，v1 告警 |
| D2 | `ct pkg check <dir>` 只读骨架（PK-1/2/5/8） |
| D3 | `test/pkg/run.sh` 的 S0 段全绿（5 断言） |
| D4 | 包指南 §8 / 术语 / pkg-3…pkg-8 落库 |
| D5/D6 | 提案裁定、需求定稿、roadmap 版本位 |
| J1–J8 | 全绿；check-all 11/11 |
| 门禁 | check-ast 1444/0、test/run 156、warnings 689/0、docs 1446/265 |

S1（v0.55.0）未开工；本收口只发 v0.54.0。

## 9. S1 收口记录（2026-11-15，v0.55.0）

| SP | 结果 |
| --- | --- |
| SP-001 | store `<CT_HOME>/pkg/<pub>/<name>/<ver>` 落盘；`vendor/` 兼容写保留 |
| SP-002/003/004 | `publisher` / `ns-root` 必填与形态校验；`local` 拒绝 |
| SP-005/020 | 多版本并存；同版本同摘要 no-op、异摘要报错 |
| SP-007/014 | install 离线读 store；裸名歧义硬错 |
| SP-017/019 | v2 头 + 7 字段；store 摘要不符报错 |
| 门禁 | `test/pkg/run.sh` 106/0；check-ast 1444/0；check-all 11/11 |

S2（`ct build` 读 lock、`--locked`、dev override）未开工。

## 10. S2 收口记录（2026-11-15，v0.56.0）

| SP | 结果 |
| --- | --- |
| SP-006/013 | build/install/verify 拒绝同名重复，`is required twice` |
| SP-008 | `ct build` 默认读 `ct.lock` 并自动补 `-I`；显式 `-I` 优先 |
| SP-009 | `--locked` 缺失/摘要不符硬错，不回退 |
| SP-010 | 无 lock 退回 `vendor/`，告警一次；无 vendor 不报错 |
| SP-015 | `dir` 行触发 dev override `note:` |
| 门禁 | test/pkg 117/0；check-ast 1444/0；check-all 11/11 |

S3（verify/migrate）未开工。

## 11. S3 收口记录（2026-11-15，v0.57.0）

| SP | 结果 |
| --- | --- |
| SP-016 | verify --strict 拒绝 dir 行与 v1 lock |
| SP-019 | store 摘要不符报 `does not match ct.lock` |
| SP-029 | migrate 后移走 vendor 仍可 build；lock 重写为 v2 |
| update | v2 pin 离线审计，不重新联网 |
| 门禁 | test/pkg 127/0；check-ast 1444/0；check-all 11/11 |

S4（包仓对齐）已移出本 phase：`publisher` / `ns-root` / tag / 各仓测试改写归对应包仓，本卡不再跟踪，也不再作为收口判据。

## 12. S5/S6 收口记录（2026-11-15，v0.58.0，仓内部分）

| 项 | 结果 |
| --- | --- |
| S5 | 双 HOME/CT_HOME 同 lock 构建：lock 逐字节一致、运行输出一致、规范化生成 C 一致；SP-028 vendor 回退告警 |
| S6 | package-guide/tutorial/README/README.en/install.sh/glossary 改为 store 为现行机制；`-I vendor/` 仅兼容期 |
| 门禁 | test/pkg 130/0；check-ast 1444/0；check-all 11/11 |

**未完成/阻塞**：S7 读路径已删除（v1 lock 直接报错、无 lock 不再读 vendor/）；`ct get` 仍写 vendor/，写路径与 SP-028 告警删除待做。本相不宣称整体完成。

## 13. v0.58.0 之后的重排结论（2026-11-15）

| 项 | 结论 |
| --- | --- |
| S6 历史 errata | **未做**。提案 §10 S6 要求给历史 phase 文档加「已被共享库取代」一节；全仓 grep 该短语为 0 命中。纯文档，可随时做 |
| S7 前置口径 | **已定（2026-11-15）：本仓自证**。三条可执行判据见 roadmap S7 行；包仓迁移状态是外部登记项，由各包仓维护，CT 不追踪、不判定 |
| S7 时间 | 仍按「连续两个 minor」的兼容期节奏；v0.58.0 之后至少再发两个 MINOR 才谈收口 |
| 包机制后续 | PKG-5（缓存键裸名，代码 `Pkg.h.ct:865` 仍按裸名）、PKG-6（install 不试解析 import）仍 open；PKG-4/7/8 已由 S2/S3 落地，issue 状态待回填 |

排序、依赖与放弃/合并清单见 [post-58-plan.md](../../planning/post-58-plan.md)。
