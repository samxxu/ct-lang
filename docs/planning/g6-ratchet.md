# G6 ratchet 与基线（CI-13）

> 门禁：`tools/check.sh g6`；实现：`tools/gates/issue_ledger.py`；负例：
> `test/gates/issue_ledger_test.sh`。本文件说明**什么时候**用严格模式、什么时候用 ratchet；
> 判据本身仍以 `AGENTS.md` §5.4 / §6.4 G6 为准。

## 两种模式

| 模式 | 命令 | 判据 | 何时用 |
| --- | --- | --- | --- |
| 严格（默认） | `tools/check.sh g6` | 全台账按 §5.4 判，任何违规即红 | 常态；基线为空或已删除时 |
| ratchet（显式） | `tools/check.sh g6 --ratchet` | 命中基线的旧违规计 `known`；未命中的新违规红；基线里没有对应违规的行（僵尸）红 | 门禁必须先上线、而台账仍有存量旧债时 |
| 重写基线 | `tools/check.sh g6 --write-baseline` | 用当前违规重写 `issues/.g6-baseline.tsv` | 归一一批旧债后；或旧债清零、删除基线时 |

**默认不变。** `tools/check.sh g6` 不读基线；把基线表当成豁免口不会让默认检查变绿。
ratchet 只是让门禁在旧债未清时先上线，不是第二套判据。

**当前等价。** 本仓 297 条 issue 已全部归一到 §5.4 闭集，`--write-baseline` 写出 0 行；
此时 `g6`、`g6 --ratchet` 与严格模式三者等价。基线文件保留为格式与追踪锚点，
CI-14 的退出条件第 1 条（基线为空或已删除）因此成立。

## 基线格式

`issues/.g6-baseline.tsv`，UTF-8、Tab 分隔；`#` 开头为元数据，空行忽略：

```text
# g6-baseline v1
# tracking: CI-14
# owner: REV
# exit: 基线清空、g6 严格模式绿、遗留项各有去向
path	现状	归一键	类别
issues/foo/bar.md	待办	open	在办类
```

| 列 | 含义 |
| --- | --- |
| `path` | 相对仓库根的 issue 路径 |
| `现状` | 违规键：默认是状态字段原文；无状态等机械违规用 `missing-status` / `status-mismatch` / `verified-no-evidence` 等 |
| `归一键` | 按 CI-13 §1 映射到的 §5.4 状态词（`open` / `verified` / …） |
| `类别` | `在办类` / `核销类` / `延后类` |

只收**已存在**的存量违规；新 issue 不受保护。`--write-baseline` 是唯一写入口，
禁止手改；改基线必须与「这批旧债已归一」的提交同一事。

## 必须挂追踪 issue

基线是豁免，必须挂一个**有退出条件**的追踪 issue。`--ratchet` / `--write-baseline` 会：

1. 读 `# tracking: <ID>`，在 `issues/**` 按 front-matter `id:` 或文件名前缀找条目；
2. 条目必须含 `退出条件` 一节，且正文提到 `g6`；
3. 任一缺失 → 基线不可用，退出 1。

当前追踪条目是 [CI-14](../../issues/ci/ci-14-g6-legacy-status-cleanup.md)：基线清空、严格模式绿、
14 条 `待办` 各有去向。基线清空后删文件即可，不需要保留空表；本仓保留 0 行基线是为了
让格式与追踪关系始终有人可查。

## 三类失败（均有负例）

| 场景 | 表现 | 负例 |
| --- | --- | --- |
| 新增违规 | 违规键不在基线 → `new debt not in the baseline`，退出 1 | `test/gates/issue_ledger_test.sh` 第 2 例 |
| 僵尸条目 | 基线行对应的文件已归一、改名或删除 → `zombie baseline row`，退出 1 | 第 4 例 |
| 减少（重写） | 旧行必须由 `--write-baseline` 主动删除，不能靠“文件没了”自动放过 | 第 5 例 |

严格模式本身不读基线，因此「没有基线的干净台账仍绿」也是负例之一（第 1 例）。

## 运维顺序

1. 旧债存在、门禁要先上线：`g6 --write-baseline --tracking CI-14`，REQ 复核行数后入库；
2. 每归一一条：`g6 --write-baseline` 重写，确认该行消失，同提交提交；
3. 新违规：修 issue 状态或补证据，**不要**往基线加行；
4. 基线 0 行 / 删除后：只用严格 `g6`，ratchet 保留但不再需要。
