# CI-4 · 仓库无 CI 配置，九道门禁只靠手工执行

| 项 | 值 |
| --- | --- |
| 模块 | ci |
| 严重度 | Medium |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | 仓库根（无 `.github/`、无 `Makefile` / `justfile` / `.gitlab-ci.yml`） |
| 状态 | 已修（2026-11-02，commit `810e0fc` + `bc1fd52`） |

## 现象

九道硬门禁已由 [selfhost/check-all.sh](../../selfhost/check-all.sh#L72-L80) 聚合为一条命令，但仓库里
**没有任何 CI 配置**，也没有 `make check` 之类的入口别名。门禁是否被执行，完全取决于开发者记得手工运行。

```bash
$ ls .github
ls: .github: No such file or directory
$ ls Makefile justfile .gitlab-ci.yml 2>&1
ls: … No such file or directory
```

## 证据

本轮审计的基线正是手工执行的结果：

```text
$ bash selfhost/check-all.sh
check-all: OK (9 hard gates green)
```

CI-1 / CI-2 已分别解决「run.sh 不覆盖 CT 线」与「无聚合入口」；本条是剩下的最后一环：**自动执行**。

## 影响

- 回归只能在提交后由人发现，PR 上没有状态信号；
- 审计期间还观察到并发执行 `check-all.sh` 时出现过一次 `check-all: FAIL (at least one hard gate failed)`，
  串行重跑全绿但未复现——没有 CI 就没有稳定的串行执行环境来证伪这类环境相关失败；
- 新增 batch 时容易漏跑某一关（例如只跑 `test/run.sh`）。

## 修复建议

- 最小方案：加一个 `Makefile`（或 `check.sh` 别名）目标 `check` → `bash selfhost/check-all.sh`，不改动
  任何门禁语义；再加一条 GitHub Actions workflow，`ubuntu-latest` + `macos-latest` 矩阵串行跑该目标；
- 保留 `bash test/acceptance/run.sh` 的「只报告不阻断」语义，不要在 CI 里把它改成硬失败；
- Linux 上两条 BSD 探针仍按既有设计 `skip`（见 `AGENTS.md` §6），不要为通过 CI 去改探针。

## 验证

CI 首次运行应九关全绿；故意引入一处小回归（本地实验）应使对应关卡变红；工作树无生成物残留。

## 处理（2026-10-31）

部分修复：新增 `Makefile` 的 `make check`（调用 `check-all.sh`，语义不变）。不加云端 workflow：仓库托管平台与凭据未定，且两条 BSD 探针在 Linux 需要跳过策略；先提供本地聚合入口。

## 处置（2026-11-07 回填）

已完成。GitHub Actions 于 2026-11-02 落地，「手工执行」的前提不再成立：

- `810e0fc`：`ci.yml`（`ubuntu-gcc` / `macos-clang` 串行跑 `bash selfhost/check-all.sh`，
  `ubuntu-clang-smoke` 跑 L0 / `check-ast` / `check-warnings`）与 `nightly.yml`；
- `bc1fd52`：`packages.yml`，覆盖包门禁。

`make check` 保留为本地聚合入口，与 CI 并存。
