# PKG-14 · PH-83 开卡需求：只读 `ct index verify` 与 Linux x64 产物

| 项 | 值 |
| --- | --- |
| 模块 | packages / 发布工程 |
| 定性 | 需求（新 phase 开卡） |
| 严重度 | Medium |
| 锚点 | v0.79.0（2026-11-20） |
| 文件 | [契约 v1](../../docs/planning/ct-pkg-get-contract.md)、[D-014](../../docs/decisions/D-014.md)、[评估](../../docs/reviews/2026-11-20-pkg-contract-proposal-eval.md) |
| 状态 | **verified**（2026-11-21，REV 第二轮；PKG-14 修复经独立复核，见下方复核段） |

## 背景

外部提案要求把发布/索引生成收进 CT。需求方裁定（D-014 第 1、6、7 条）：维持 B′，只新增
**只读** `ct index verify`，并提供 CI 友好的 Linux x64 产物；发布与索引生成仍留在 index CI。

## 范围

1. `ct index verify <file>`：只读回放索引行——字段数、digest 拼写、行内 tag/版本一致性、
   store 可安装性；不联网、不写 store、不写 lock、不推索引；
2. 五字段旧行调用本命令时的行为与 [PKG-13](pkg-13-legacy-five-field-row-hard-error.md) 一致；
3. 每个 MINOR 发布 `ct-linux-x64.tar.gz` + `.sha256`，GitHub Release 稳定 URL；
4. 版本节奏：`vX.Y.Z`；index CI 按 tag 钉版本。

## 非目标

- `ct pkg release`、`ct index build|refresh`；
- 全量 PK/R/S 校验；
- 多索引并存、签名/pin 基础设施；
- 宿主平台建仓。

## 退出判据（建议）

| ID | 断言 |
| --- | --- |
| E83-1 | `ct index verify` 对合法索引返回 0，对坏行返回非零并给行号 |
| E83-2 | 命令零网络、零子进程、零 store/lock 写入 |
| E83-3 | 五字段行按行硬错，与 `ct get` 判定一致 |
| E83-4 | Linux x64 产物可下载、sha256 匹配、可直接运行 `ct -v` |
| E83-5 | 产物版本与 tag 一致；旧 golden 与既有门禁不变 |
| E83-6 | 契约 §9 的 CT 侧验收项全绿 |

## 施工前置

- PH-82 收口；
- [PKG-12](pkg-12-contract-v1-doc-gaps.md) 的判据归属矩阵定稿（至少完成 `verify` 所需条目）；
- index 仓确认消费该产物的方式。

## 关联

- [PH-83 roadmap 条目](../../docs/roadmap.md)、[D-014](../../docs/decisions/D-014.md)

## 复核（REV，2026-11-21）：**reopened**

PKG-14 的 E83-6（契约 §9 CT 侧验收项；对应 PH-83 卡 E83-4）未过：PH-83 收口复核
（`5378850e`）发现 `ct index verify` 对非普通文件输入不返回契约要求的
退出码 2：目录、`/dev/null`、指向目录的 symlink、`CT_INDEX` 指向目录、
`$CT_HOME/index/index` 为目录时均输出 `index verify: OK (0 rows)` 并 exit 0，`--json`
输出 `"ok":true`；FIFO 阻塞；GitHub Release 的 Linux 产物对 `/` 同判。最小复现：

```console
$ mkdir -p /tmp/p83-dir.index
$ ct index verify /tmp/p83-dir.index
index: /tmp/p83-dir.index
index verify: OK (0 rows)
$ echo $?
0
```

契约 §4.4 要求“用法错误/索引不可读 → 退出码 2”。代码 `selfhost/ct-ast/tool/pkg/Pkg.h.ct:2674`
只 `fopen`，`:2803` 直接 `fclose`，无 `stat`/`S_ISREG`、无 `ferror` 检查。期望：非普通文件
与读错误均 exit 2；`--json` 不得在 exit 2 时给 `ok:true`；`p83_verify` 补目录/FIFO 负例。

证据：[REV verdict](../../docs/reviews/2026-11-21-phase83-rev-verdict.md) §5.2。修复前
PH-83 不写 `REV: 通过`。

## 处置（DEV，v0.83.1，2026-11-21）：fixed

- **修复**：`pkg_index_verify` 在 `fopen` 前 `stat` + `S_ISREG`；非普通文件（目录、`/dev/null`
  等字符/块设备、FIFO、socket、指向目录的 symlink）exit 2，FIFO 不打开（不挂起）；指向普通
  文件的 symlink 仍按普通文件读取。读取后 `ferror` 非零同样 exit 2。`--json` 在 exit 2 时输出
  `ok:false` 与一条 `line:0`、`kind:"io"` 的错误，不再 `ok:true`；显式路径 / `CT_INDEX` /
  `$CT_HOME/index/index` 三种来源同规则。
- **测试**：`test/ast/p83_verify.sh` 增加目录、`/dev/null`、目录 symlink、`CT_INDEX` 目录
  （文本 + JSON）、`$CT_HOME/index/index` 目录、FIFO（python3 5s 看门狗，超时即失败）、
  Linux `/proc/self/mem` ferror 负例。
- **提交**：`c72349fe`（红，baseline `8014739e`）+ 本提交（fix，v0.83.1）。
- **红证**：8 条 FAIL（目录/`/dev/null`/symlink/CT_INDEX/HOME 均 exit 0；FIFO TIMEOUT）。
- **绿证**：`p83_verify: OK`（26）；Linux 交叉产物在 QEMU Alpine 内：
  `/proc/self/mem` → `ct: error reading the package index '/proc/self/mem'` rc=2；
  `/proc --json` → `{"ok":false,...,"kind":"io"}` rc=2。
- **契约**：§4.4/§7/§9 同步，§12 记 v1.2。
- **状态**：字段仍为 `reopened`（REV 所有）；DEV 主张 `fixed`，等待 REV 复核。

## 复核（REV，2026-11-21，第二轮）：**verified**

第二轮复核对象 `f7db9a72`（v0.83.1，tag `v0.83.1`）。从 `git archive v0.83.1` 独立自举
（`ct-ast v0.83.1`），重跑第一轮全部反例：

```console
$ ct index verify /tmp/rev831/indep/adir
ct-ast: not a regular file: '/tmp/rev831/indep/adir'      # rc=2
$ ct index verify /dev/null
ct-ast: not a regular file: '/dev/null'                   # rc=2
$ ct index verify /tmp/rev831/indep/dirlink               # symlink -> dir
ct-ast: not a regular file: '/tmp/rev831/indep/dirlink'   # rc=2
$ CT_INDEX=/tmp/rev831/indep/adir ct index verify
ct-ast: not a regular file: '/tmp/rev831/indep/adir'      # rc=2
$ HOME=/tmp/rev831/indep/badhome CT_HOME=/tmp/rev831/indep/badhome ct index verify
ct-ast: not a regular file: '/tmp/rev831/indep/badhome/index/index'  # rc=2
$ mkfifo /tmp/rev831/indep/fifo.index && ct index verify /tmp/rev831/indep/fifo.index
ct-ast: not a regular file: '/tmp/rev831/indep/fifo.index' # rc=2，5s 内返回，不挂起
```

`--json` 对上述输入均为 `ok:false`、`errors[0].line=0`、`kind="io"`；Unix socket 与
`/dev/zero` 同样 exit 2。普通文件 symlink 仍可读（`OK (3 rows)`，JSON `ok:true`）；
六字段行 `ct index verify` = `OK (1 rows)` 且 `ct get --index` 成功；五字段旧行仍与
`ct get` 同模板硬错。

ferror：v0.83.1 Release 的 Linux 产物在 QEMU Alpine 内实跑
`ct index verify /proc/self/mem` → `ct: error reading the package index '/proc/self/mem'`，
rc=2；`--json` → `{"ok":false,...,"errors":[{"line":0,"kind":"io",...}]}`，rc=2。

T-7：红提交 `c72349fe`（baseline `8014739e`）用 v0.83.0 构建复跑，8 条 FAIL、exit 1；
fix `f7db9a72` 后 `p83_verify` 34 ok + 1 skip（macOS skip ferror），`p83_verify: OK`。
E83-1/3/5/6/7 回归：p83_legacy 9 ok、p83_conformance 19 passed、p83_dist 8 ok；
check-all 11 门绿（156/153/169/1549 + 490 warnings）、sanitizer 583、g0/g8/check-docs 绿；
五处版本 0.83.1，51 golden 仅版本 token。

Release：`ct-linux-x64.tar.gz` sha256 `7265d00a9d0e93aabeb5a91ee06212c8ff8853430da8db9a595c13aa79749c35`，
解包 `ct -v` = `ct v0.83.1`；tag/Release/版本一致。

证据：[REV verdict](../../docs/reviews/2026-11-21-phase83-rev-verdict.md) §14。

## CI 追加（v0.83.2，DEV，2026-11-21）

REV 第二轮 verified 后，CI v0.83.1 在 ubuntu-clang/gcc 上 `PH-83-S83b verify` 红、macOS 绿。
Linux 容器（Fedora/aarch64，clang）复现并定位为**产品差异**：

- `pkg_index_verify` 的默认索引分支先令 `ip = path`，随后
  `snprintf(path, sizeof path, "%s", ip)` 把 `path` 自拷贝进 `path`；重叠对象上的 `snprintf`
  是 C 未定义，glibc 返回空串，`stat('')` 失败。macOS libc 恰好原地复制，所以 macOS 绿
  （与 SH-103 的字段表自拷贝同类）。
- 修复：`if (ip != path) snprintf(path, sizeof path, "%s", ip);`。
- 测试：`p83_verify` 增两条 Linux 可捕获断言（`CT_HOME` 目录 stderr 带完整路径；默认
  `CT_HOME` 的 `--json.index` 等于 `$CT_HOME/index/index`），红提交 `d49982c6`
  （baseline `fa6f8fba`）。
- 绿证：Linux 容器 `p83_verify: OK`（36 ok）；macOS 35 ok + 1 skip（ferror）；`v0.83.2`。
- 提交：本提交（fix，v0.83.2）；产物 sha256
  `63e6c1e666c67d708fe05955eed4ea1c6c045a6867319f3b43d512b5b88e15ca`。
- 状态字段仍为 `verified`（REV 所有）；DEV 主张本轮追加 fixed，是否 reopen/复核由 REV 裁定。
