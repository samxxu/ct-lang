# CI-3 · 门禁依赖 `diff` / `python3` / `git`，缺一个就产生成百条假 FAIL

| 项 | 值 |
| --- | --- |
| 模块 | ci |
| 严重度 | **Low**（不影响编译器正确性，但会把「环境缺件」误报成「产品坏了」） |
| 锚点 | commit `2ead601`（2026-10-21） |
| 文件 | [selfhost/check-all.sh](../../selfhost/check-all.sh)、[test/run.sh](../../test/run.sh)、[selfhost/check-goldens.sh](../../selfhost/check-goldens.sh)、[selfhost/check-archive.sh](../../selfhost/check-archive.sh)、[selfhost/check-m2a.sh](../../selfhost/check-m2a.sh)、[selfhost/ct-tour.sh](../../selfhost/ct-tour.sh)、[test/pkg/run.sh](../../test/pkg/run.sh) |
| 状态 | ⬜ 未修复 |

## 现象

门禁脚本默认宿主机是完整开发环境。在精简镜像（Rocky / Alinux 的 `*-minimal` 一类）里，
缺一个工具不会得到「缺少前置条件」的提示，而是让每个用例都失败一次：

```
./test/run.sh: line 105: diff: command not found
  FAIL  01_trait_basic: generated .c differs from golden
./test/run.sh: line 105: diff: command not found
  FAIL  02_multi_trait: generated .c differs from golden
...
== summary: 83 passed, 33 failed ==
FAIL: 1) L0 suite (test/run.sh) (exit 1)
FAIL: 2) CT: check-goldens (exit 1)
...
check-all: FAIL (at least one hard gate failed)
```

## 证据

跨发行版实测（podman，arm64，锚点 `2ead601`）：

| 环境 | 缺失 | 结果 |
| --- | --- | --- |
| Rocky Linux 8.9 精简镜像 | `diff`（`diffutils` 未装） | `check-all` **FAIL**，日志里 **127 行** `FAIL`／`FAIL:`；`test/run.sh` 报 83 passed / **33 failed**，根因全部是 `diff: command not found` |
| 同上，`dnf install diffutils` 之后 | — | 同一份代码 **`check-all: OK (8 hard gates green)`**，`test/run.sh` 116 passed / 0 failed |
| Alibaba Cloud Linux 3 | 无 `python3`（只有 `python3.11` 这个包名）、无 `tar` | 第 6 关（编辑器语法检查）无从执行；`tar` 缺失会让 `install.sh` 提前 `die`（这条有明确报错，行为正确） |

即：**产品代码一行没变**，缺 `diff` 让 127 条断言由绿转红。

同一族的隐性依赖还有：

| 工具 | 谁在用 | 缺了会怎样 |
| --- | --- | --- |
| `diff` | `test/run.sh`、`check-goldens.sh`、`check-archive.sh`、`check-m2a.sh`、`ct-tour.sh`、`check-ast.sh` | 每个 golden 比对都报「differs from golden」 |
| `python3` | `check-all.sh` 第 6 关（`editors/vscode/test/check-grammar.py`） | 该关直接非零退出，原因只有 `python3: command not found` |
| `git` | `test/pkg/run.sh`（Phase 8.2 的 git 源用例） | 包管理关卡失败 |
| `tar` | `install.sh` | 有明确 `'tar' is required`，不算本问题 |

## 影响

- 在新发行版 / CI 容器里第一次跑门禁，会得到一份「编译器看起来全坏了」的报告，实际是环境缺件；
  排查成本高（需逐条翻日志才能发现 `command not found`）。
- 反向风险：有人图省事把 `diff` 换成 `cmp`、或给 `diff` 失败加 `|| true`，会真正削弱 golden 关卡。

## 修复建议

在 `check-all.sh` 开头加**一次前置检查**（各子脚本仍保持独立可跑）：

```sh
missing=
for t in "${CC:-cc}" diff python3 git; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
[ -z "$missing" ] || die "missing prerequisites:$missing (Debian/Ubuntu: apt-get install -y build-essential diffutils python3 git; RHEL/Rocky: dnf install -y gcc diffutils python3 git)"
```

要点：

1. **一次报告全部缺失项并带上按发行版的安装命令**，而不是让每个用例各自失败。
2. 缺失时以非零退出（不能静默跳过——那会让「绿」失去意义）；但输出里要区分「环境不满足」与
   「断言失败」，避免和前一类失败混在同一份 `FAIL` 列表里。
3. `test/pkg/run.sh` 已有的「无 `git` 时硬报错并提示」是同一思路，可复用其措辞。

## 验证

- 在未装 `diffutils` 的精简镜像里跑 `bash selfhost/check-all.sh`：只出现一条前置条件缺失的提示，
  不再出现逐用例的 `differs from golden` 假失败，退出码非零。
- 装齐依赖后同一镜像跑出 `check-all: OK (8 hard gates green)`，与宿主机结果一致
  （Rocky 8.9 / Alinux 3 已实测通过）。
