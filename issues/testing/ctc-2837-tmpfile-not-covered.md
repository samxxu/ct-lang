# TEST-1 · `ctc.c:2837`（cannot create a temporary file）可达但无负例

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | **Medium** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 站点 | `ctc.c:2837` |
| 状态 | 已修复（commit `1a1ae91`，`cli/tmpfile-cannot-create`） |

## 现象

`ctc.c:2837` 的诊断 `ctc: cannot create a temporary file`（`tmpfile()` 失败分支）**可达**，但 `test/errors/**` 与 `test/cli` 均无 fixture 覆盖它。

## 证据（探针）

```bash
printf 'int main(){return 0;}\n' > /tmp/ok.ct
TMPDIR=/nonexistent/zzz ./ctc /tmp/ok.ct -o /tmp/ok.c
# -> ctc: cannot create a temporary file
# exit=1
```

macOS 上 `tmpfile()` 遵循 `$TMPDIR`，故把一个不可写/不存在的 `TMPDIR` 指向即可稳定触发。

## 影响

`test/errors` 的负例层是「诊断覆盖」的机械证据；此站点可达却无守门，回归时无人发现。且 [DOC-4](../docs/architecture-unreachable-claim.md) 误把它记为「不可达」，双重掩盖。

## 修复建议

按 `ctc-coverage-audit` skill 的负例流程补一条 fixture：

- 报告格式为 `ctc: cannot create a temporary file`（**注意**：它走 `fprintf(stderr)`，无 `文件:行:列: error:` 前缀，属 CLI/驱动类错误）。
- 由于触发依赖环境变量 `TMPDIR`，**不宜**用 `test/errors/*.ct` 的纯输入方式；更合适的落点是 `test/run.sh` 的 `cli` 层——用 `TMPDIR=/nonexistent/zzz` 调一次 `ctc`，断言非零退出与消息子串。
- 定 fixture 前先跑真实二进制取输出，禁止凭记忆手写（见 skill §7）。

## 验证

新增断言后 `./test/run.sh` 全绿；断言内容与 `TMPDIR=/nonexistent/zzz ./ctc …` 的真实输出逐字一致。
