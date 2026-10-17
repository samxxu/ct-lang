# TEST-2 · `ctc.c:2708`（cannot read）可达但无负例

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | **Medium** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 站点 | `ctc.c:2708`（`read_file` 中 `sz < 0` 分支） |
| 状态 | 已修复（commit `1a1ae91`，`cli/cannot-read`） |

## 现象

`ctc.c` 的 `read_file` 里，`fseek/ftell` 失败导致 `sz < 0` 时走 `ctc: cannot read '<path>'` 分支（L2708）。该分支**可达**，但无 fixture 覆盖。

## 证据（探针）

```bash
mkfifo /tmp/fifo.ct
( sleep 0.3; printf 'int x;\n' > /tmp/fifo.ct ) &
./ctc /tmp/fifo.ct -o /tmp/fifo.c
# -> ctc: cannot read '/tmp/fifo.ct'
# exit=1
```

FIFO 不可 `fseek`，`ftell` 返回 `-1`，命中该分支。

## 影响

与 [TEST-1](ctc-2837-tmpfile-not-covered.md) 同：可达诊断点无守门。注意 `2704 cannot open` 与 `2712 short read` **已有** `cli/cannot-open`、`cli/short-read` 覆盖，此站点是同一驱动层里唯一漏掉的一环。

## 修复建议

在 `test/run.sh` 的 `cli` 层补一条断言：以 FIFO（或其它不可 seek 的输入）调 `ctc`，断言非零退出且 stderr 含 `cannot read`。

- 门禁需要可移植性：`mkfifo` 是 POSIX 的，macOS/Linux 均可，但要避免依赖后台写进程的时序——可用「先 `mkfifo`，直接 `./ctc fifo`」并接受其阻塞，或用一个不可 seek 的更简手段（若有）。
- 断言文本须由真实二进制输出生成，禁止手写。

## 验证

新增断言后 `./test/run.sh` 全绿；断言与探针实测输出逐字一致。
