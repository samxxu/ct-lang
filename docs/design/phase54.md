# Phase 54 · ct-pkg 共享库包体系（切片 S0：观测与只读骨架）

**状态：实施中**（S0；S1–S7 见 [roadmap](../roadmap.md) 与[需求定稿](../planning/ct-pkg-shared-store-requirements.md)）

| 项 | 值 |
| --- | --- |
| 依据 | [提案 §10 S0](../proposals/ct-pkg-shared-store.md)、[需求 SP-002/003/004/018/021/024/027](../planning/ct-pkg-shared-store-requirements.md) |
| 版本位 | v0.54.0（S0 收口动作；本轮实现提交**不** bump，bump 与 golden 重生成在收口评审后单独提交） |
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
| J3 | `ct pkg check ../ct-fsguard` RC≠0，且 stderr 含 `is missing 'publisher'` | 直接跑 |
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

