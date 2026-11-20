# Phase 83 — 包管理契约 v1 与索引校验

> **状态：完成（v0.83.0）**（2026-11-20 立项并开卡；2026-11-21 S83a–S83d 完成，E83-1…8 通过）。
> **签收：EDITOR 2026-11-20**（主编统一签收；卡作者 REQ）；S83a 契约/矩阵另需 REVIEW 签收（§5）。
> **施工闸门**：PH-82 已收口（v0.82.0）；PKG-12 判据矩阵已按 index 基线定稿；index 仓消费方式见 §7.4。
> **前置**：PH-82 收口；[PKG-12](../../issues/packages/pkg-12-contract-v1-doc-gaps.md) 判据矩阵；
> index 仓确认产物消费方式。
> **收口**：2026-11-21；收口复核见 §7（DEV `dev-ph83`）。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase83.md`。
> **依据**：[D-014](../decisions/D-014.md)、[契约 v1](../planning/ct-pkg-get-contract.md)、
> [提案评估](../reviews/2026-11-20-pkg-contract-proposal-eval.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-83（legacy 文件 `phase83.md`） |
| 目标 | 把包管理契约收敛为单一 v1 文本，并提供只读索引校验与 CI 可用的分发产物 |
| 范围 | 契约 v1 维护、判据归属矩阵、只读 `ct index verify`、conformance 数据/runner、Linux x64 产物 |
| 非目标 | `ct pkg release`、`ct index build|refresh`、全量 PK/R/S 进 CT、多索引并存、签名/pin、宿主平台建仓 |
| 交付物 | 契约 v1、`ct index verify`、conformance、`ct-linux-x64.tar.gz` + sha256 |
| 任务清单 | §2（S83a–S83d） |
| 退出判据 | E83-1…E83-8（§3） |
| version-minor | 83（PH-83，`d=0`） |
| 已知风险 | R83-1…R83-5（§4） |

## 1 需求与边界

```sh
ct index verify ./index                 # 只读：字段/摘要/tag/可安装性
ct index verify ./index --json          # 供 CI 解析
```

- `ct index verify` 只读：不联网、不写 store、不写 lock、不推索引；
- 五字段旧行按行硬错（D-014 第 5 条），与 `ct get` 判定一致；
- 发布/索引生成仍在 `ct-pkg/index` 的 CI；CT 只提供契约与固定版本二进制；
- 每 MINOR 发布 `ct-linux-x64.tar.gz` + `.sha256`，GitHub Release 稳定 URL；
- 单索引：`--index` > `CT_INDEX` > `$CT_HOME/index/index`，不承诺多索引并存。

### 1.1 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S83a 契约/矩阵 | 契约 v1 补齐、判据归属矩阵定稿 | 无代码前置（本卡前已完成草案） |
| S83b 只读校验 | `ct index verify` 与五字段按行硬错 | PH-82 收口；PKG-12 覆盖 verify 条目 |
| S83c conformance | 数据 + runner；digest 三向量 | S83a |
| S83d 分发 | Linux x64 产物、sha256、稳定 URL、版本钉法 | S83b；index 仓确认消费方式 |

### 1.2 准备态可做（不落实现代码）

| # | 项 | 通过方式 |
| --- | --- | --- |
| P83-pre-1 | 判据原文与归属矩阵补齐 | PKG-12；index 仓提供原文 |
| P83-pre-2 | 五字段硬错的发布顺序与 index 仓对齐 | PKG-13/PKG-16；书面时间点 |
| P83-pre-3 | `verify` 的只读边界与输出格式评审 | 设计审读：零网络/零 store/零 lock |
| P83-pre-4 | 产物命名、glibc 基线与 URL 规则 | 发布工程评审 |
| P83-pre-5 | conformance 数据格式与 runner 接口 | 与 shell 侧对照基准对齐 |

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S83a 契约/矩阵 | 契约 v1（digest 向量、spec、单索引、MVS、归属矩阵） | `p83_contract`（no-test，REVIEW 签字） | S |
| S83b 只读校验 | `ct index verify`；五字段按行硬错 | `p83_verify` / `p83_legacy` | M |
| S83c conformance | 版本化数据 + runner；三向量 | `p83_conformance` | M |
| S83d 分发 | `ct-linux-x64.tar.gz` + sha256 + 稳定 URL | `p83_dist`（发布工程） | M |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；
S83a 为纯文档任务，写 `no-test:` 并由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E83-1 | 契约 v1 有 digest 伪代码与 3 组实测向量；spec 语法、单索引、MVS、判据归属矩阵齐全（无待补） |
| E83-2 | 五字段旧行按行硬错，与 `ct get` 判定一致；其余六字段行不受影响；发布前置已由 index 仓确认 |
| E83-3 | `ct index verify` 零网络、零子进程、零 store/lock 写入；坏行给行号与非零退出码 |
| E83-4 | `--json` 输出稳定，CI 可解析；退出码 0/1/2 语义与契约 §7 一致 |
| E83-5 | conformance 数据覆盖合法/非法清单、索引行与 digest 三向量；shell 与 CT 共用且差异显式登记 |
| E83-6 | `ct-linux-x64.tar.gz` 可下载、sha256 匹配、解包即可运行 `ct -v`；版本与 tag 一致 |
| E83-7 | 旧 golden/既有门禁不变；`check-all` 通过；`v0.83.0` 五处版本号与文档同步 |
| E83-8 | 单卡回滚：撤回 `ct index verify` 与产物不影响 `ct get`/发布路径 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R83-1 | 五字段硬错先于 index 仓清零，存量包集体不可装 | 发布前置 + 过渡版本；PKG-13 |
| R83-2 | 范围蔓延成 release/index 生成 | 本卡非目标写死；复开需覆盖 D-014 第 1 条 |
| R83-3 | Linux 产物不可复现或 glibc 基线不清 | 固定构建环境、发 sha256、写清基线；zig static musl |
| R83-4 | shell 与 CT 判定再次漂移 | conformance 共用数据；差异显式登记 |
| R83-5 | 版本钉法冲突（index CI 钉旧版） | 每 MINOR 稳定 URL；契约写清“谁钉谁” |

回滚：单卡回滚；`ct index verify` 与产物同退，发布/消费路径不受影响。

## 5 验收记录（S83a–S83d）

| stage | 红证提交 | 实现提交 | 验收命令 | 结果 |
| --- | --- | --- | --- | --- |
| S83a 契约/矩阵 | `no-test: 纯文档` | `029d0d97` | `grep -c TBD docs/planning/ct-pkg-get-contract.md` | 0；§3.3 三向量 + §4.4 + §6.1 定稿 |
| S83b 只读校验 | `d22a5077`（baseline `1764b4d6`） | `b5873c40` | `sh test/ast/p83_verify.sh` / `p83_legacy.sh` | `p83_verify: OK`（26）/ `p83_legacy: OK`（9） |
| S83c conformance | `7cbd5792`（baseline `1764b4d6`） | `f1a1146a` | `sh test/ast/p83_conformance.sh` | `p83_conformance: OK`（19 passed） |
| S83d 分发 | `23c00b0b`（baseline `1764b4d6`） | `2a0a0d38` | `sh test/ast/p83_dist.sh --require` | `p83_dist: OK`（8，产物 v0.83.0，sha256 `b04afe2e…`） |

S83a 的 REVIEW 签收位：本卡 §5 记录“契约/矩阵已按 index@0cdb132 定稿、无待补、与 conformance
类别对齐”，由 REVIEW 席位在收口复核时签字；DEV 不自签。

> 签收: REVIEW 2026-11-21（S83a 契约/矩阵：digest 三向量已独立复算，§4.1.1/§4.4/§6.1 无 TBD，
> 与 conformance v1 类别对齐；本次整卡 verdict 见 [REV 复核](../reviews/2026-11-21-phase83-rev-verdict.md)）

## 6 T-7 提交对照

| 任务 | `test(...) 红` | 实现 | 父提交关系 |
| --- | --- | --- | --- |
| S83a | `no-test` 纯文档 | `029d0d97` | 无行为改动；契约断言见 §7 E83-1 |
| S83b | `d22a5077` | `b5873c40` | 实现父 = 红；红 baseline `1764b4d6` = 红的父 |
| S83c | `7cbd5792` | `f1a1146a` | 实现父 = 红；红 baseline `1764b4d6` = 红的父 |
| S83d | `23c00b0b` | `2a0a0d38` | 实现父 = 红；红 baseline `1764b4d6` = 红的父 |

> S83b 红提交正文写的 `baseline: 210f0209` 是 SH-103 fix 落地前的相邻祖先；该提交实际父提交为
> `1764b4d6`（SH-103 fix）。两者对 p83 探针的行为相同；§7.1 已用 `1764b4d6` 的独立构建复跑红证
> （22 + 5 条 FAIL，退出码 1），以满足“baseline = test 提交父提交”的口径。

## 7 收口对照（E83-1…8）

### 7.1 原始输出

**E83-1 契约/矩阵**

```console
$ grep -ci 'TBD' docs/planning/ct-pkg-get-contract.md
0
$ grep -c 'digest = sha256:' docs/planning/ct-pkg-get-contract.md
3
$ grep -n '^### 4.4 \|^### 6.1 \|^### 3.3 ' docs/planning/ct-pkg-get-contract.md
79:### 3.3 包树摘要（digest） / 244:§4.4 `ct index verify` / 332:§6.1 判据归属矩阵（v1.1 定稿）
$ for v in 1 2 3; do sh test/conformance/pkg/reference.sh digest .../vector$v; done
sha256:4da5a4052a2a0afc6c9bbc7cc33cb153755f6f9e77a6efcb46f664aa17d00000
sha256:96c10e74b90d104fb9e789aec2d05189dd090ae1a96a1f739aa74aeaf83986a1
sha256:41743c2b7ecea992d7c1135e3fc78d2c0e020731a1199c85c0ef6308a2b7e888
```

**E83-2 五字段硬错（`p83_legacy`）**

```console
$ sh test/ast/p83_legacy.sh .temp/ph83/final/ct-ast
ok   a requested legacy row exits 1 with the contract message
ok   the legacy failure writes neither ct.lock nor store
ok   a six-field row installs even when the file has legacy rows
ok   the same package rejects @1.0.0 (legacy) while accepting @1.1.0
ok   MVS skips the lower legacy row for a range that excludes it
ok   MVS selects the lowest satisfying row and rejects it when legacy
ok   no range selects the highest row and rejects it when legacy
ok   verify reports every legacy row by line and skips the six-field row
ok   a failed legacy request leaves ct.lock byte-identical
p83_legacy: OK
$ echo $?
0
```

命中消息原文：

```text
ctc: index row for 'acme/old 1.0.0' is legacy (five fields); a six-field row is required
```

**E83-3/E83-4 只读校验（`p83_verify`）**

```console
$ sh test/ast/p83_verify.sh .temp/ph83/final/ct-ast
ok   legal index exits 0 with the row count
ok   bad index exits 1
ok   legacy message matches the contract template
ok   JSON output is a single line / keys, counts and per-line kinds are stable
ok   an unreadable index exits 2; no file+CT_INDEX+HOME exits 2
ok   an unknown index subcommand exits 2; 'ct index' exits 2; -h exits 0
ok   an explicit file wins over CT_INDEX; CT_INDEX; $CT_HOME/index/index
ok   -q prints nothing on a legal index; keeps errors on a bad one
ok   verify writes no store/lock file and spawns no git/sh/cc
ok   the index file is unchanged
ok   comments and blank lines are not rows
p83_verify: OK
$ echo $?
0
```

JSON 单行样例（坏行 5 条）：

```json
{"index":".temp/ph83/ctest/bad.index","ok":false,"rows":6,"valid":1,"invalid":5,"errors":[{"line":2,"kind":"legacy-five-field","message":"index row for 'old 1.0.0' is legacy (five fields); a six-field row is required"},{"line":3,"kind":"field-count","message":"index row has 4 fields; six are required"},{"line":4,"kind":"digest","message":"index digest must be sha256:<64 lowercase hex>"},{"line":5,"kind":"tag-version","message":"index tag 'v2.0.0' must be 'v1.0.0'"},{"line":6,"kind":"duplicate","message":"index row 'acme/util 1.0.0' appears more than once"}]}
```

**E83-5 conformance（`p83_conformance`）**

```console
$ sh test/ast/p83_conformance.sh .temp/ph83/final/ct-ast
ok   v1 has 12 manifest cases
ok   v1 has 3 digest vectors
ok   v1 has the legal/illegal index files
  == manifests (test/conformance/pkg/v1/manifests) ==
  ok   manifest ok-basic (ok)
  ...
  ok   manifest err-absolute-I (absolute-I)
  == index (test/conformance/pkg/v1/index) ==
  ok   legal index (3 rows, both sides clean)
  ok   index illegal rows: CT matches the expected line/kind map
  ok   index illegal rows: shell reference matches the expected map
  ok   index: CT and shell reference agree row by row
  == digest (test/conformance/pkg/v1/digest) ==
  ok   digest vector1 (sha256:4da5…)
  ok   digest vector2 (sha256:96c1…)
  ok   digest vector3 (sha256:4174…)
  conformance: 19 passed, 0 failed (data: v1)
ok   CT and the shell reference agree on every case
p83_conformance: OK
$ echo $?
0
```

**E83-6 Linux x64 产物**

```console
$ ZIG=<zig> sh selfhost/make-dist.sh --cross <zig>
== bootstrap (host cc) == / == target (Linux x86_64) ==
file: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, ...
artefact: dist/ct-linux-x64.tar.gz
linkage:  static musl
sha256:   b04afe2e8efb214fdc73a1a374d053cab95789a5918014b06dc152f7f483ac39
smoke:    ct v0.83.0

$ sh test/ast/p83_dist.sh .temp/ph83/host083/ct-ast --require
ok   sha256sum -c accepts the artefact
ok   sha256 matches b04afe2e8efb214fdc73a1a374d053cab95789a5918014b06dc152f7f483ac39
ok   the tarball contains ct and ctc only
ok   unpacked ct is executable
ok   unpacked ctc is the ct symlink
ok   ELF 64-bit x86-64 (ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, with debug_info, not stripped)
ok   unpacked ct -v prints 'ct v0.83.0'
ok   host compiler agrees on v0.83.0
p83_dist: OK
$ echo $?
0
```

`ct -v` 的实跑路径：macOS 上 `run-linux-binary.sh` 用缓存的 Alpine `vmlinuz-virt` +
静态 busybox 组一次性 initramfs，`qemu-system-x86_64` 启动后执行 `/bin/ct -v`；输出
`ct v0.83.0`、退出 0。产物 `dist/` 按 `.gitignore` 不提交（不可下载到远端，见 §7.4）。

**E83-8 单卡回滚演练**

在 `git worktree` 中 revert `b5873c40`（S83b 实现）与 `2a0a0d38`（S83d 实现）后重建：

```console
$ ct-ast get <local-pkg>                     # ok（写 store 与 ct.lock）
$ ct-ast get --index mixed.index acme/util@1.1.0   # ok（六字段行照常）
$ ct-ast verify                              # verified 1 package(s)
$ ct-ast install                             # ct-ast build <unit>.ct -o build # lock-format: v2
$ ct-ast index verify mixed.index            # ctc: compile mode takes one input; 'verify' is extra
$ [ -f selfhost/make-dist.sh ] || echo absent  # absent（产物脚本随 S83d 撤回）
```

结论：撤回 `ct index verify` 与产物脚本后，`ct get`（本地目录 / 六字段索引）、`ct verify`、
`ct install` 与宿主 `ct` 均不受影响；发布路径不依赖 verify（`make-dist` 只读 `main.ct` 的
`CTC_VERSION`）。

### 7.2 逐条对照

| ID | 断言 | 证据 | 结果 |
| --- | --- | --- | --- |
| E83-1 | digest 伪代码 + 3 向量 + spec/MVS/单索引/矩阵，无待补 | §7.1 第 1 段；契约 §3.3/§4.1.1/§4.4/§6.1；conformance 三向量 | ✅ |
| E83-2 | 五字段按行硬错、与 `ct get` 一致、六字段不受影响 | `p83_legacy` 9 条；`p83_verify` legacy 行 | ✅ |
| E83-3 | 零网络/零子进程/零 store/lock 写；坏行给行号 | `p83_verify` 的 read-only 三条（HOME 前后一致、无 ct.lock、PATH shim 未调用）+ 代码只用 `fopen/fgets` | ✅ |
| E83-4 | `--json` 稳定；退出码 0/1/2 | `p83_verify` JSON 键序/计数/单行 + 退出码三条 | ✅ |
| E83-5 | 数据覆盖清单/索引/三向量；shell 与 CT 共用、差异登记 | `p83_conformance` 19 passed；`differences.md` 8 条 | ✅ |
| E83-6 | 产物 sha256 匹配、解包 `ct -v`、版本与 tag 一致 | `make-dist` + `p83_dist --require`（§7.3） | ✅（见 §7.4 上传边界） |
| E83-7 | 旧 golden/门禁不变；check-all；五处版本同步 | §7.3 门禁原文 | ✅ |
| E83-8 | 回滚不影响 `ct get`/发布路径 | §7.1 回滚演练 | ✅ |

### 7.3 门禁原文

最终运行在 `TMPDIR=.temp/ph83/tmp`（私有临时目录，避免 `ct-tour`/`p44` 的固定路径与并发
gate 相踩）：

```console
$ TMPDIR=$PWD/.temp/ph83/tmp bash selfhost/check-all.sh
...
== summary: 156 passed, 0 failed ==
== summary: 153 passed, 0 failed ==
== 169 checks, 0 failed ==
== summary: 1548 passed, 0 failed, 5 skipped ==
...
check-all: OK (11 hard gates green)
```

```console
$ env -u CT_C_BOUNDARY bash selfhost/check-warnings.sh
check-warnings: 490 ok, 0 failed
$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (583 checks, no sanitizer report)
```

```console
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2189 relative links in 363 files, v0.83.0, 11 hard gates, 12 phase status, 5 适用版本 header(s), 2 superseded link(s), 6 signoff(s))
```

五处版本落点与 51 个 golden/ABI banner：

```console
$ grep -h '#define CTC_VERSION' selfhost/l0/ctc.c selfhost/l1/ctc.ct \
      selfhost/l2/core.ct selfhost/l2/driver.ct selfhost/ct-ast/main.ct
#define CTC_VERSION "0.83.0"   (五处)
$ grep -l 'v0\.83\.0' test/cases/*.expected.c | wc -l
25
$ grep -c 'v0\.83\.0' test/modules/p39_lib/lib.expected.abi.h
1
```


### 7.4 未覆盖与简化

- **E83-6 的“可下载”**：本卡按用户指令不 push、不打 tag，产物在本地 `dist/` 生成并
  用 sha256 + QEMU Linux 实跑 `ct -v` 验证；“上传到 GitHub Release 稳定 URL”由发布动作
  执行。稳定 URL 形态写在 `docs/dist.md`，index CI 钉版本方式待 index 仓书面确认（PKG-16）。
- **PK-3/4/6/7/9–13**：index 仓 `0cdb132a` 基线没有原文；矩阵按“编号保留、不分配归属”
  定稿，不臆造判据（PKG-12 证据）。
- **`ct index verify` 不取回包树**：IV-7 只判“可回放”，包树摘要/tag 内容一致性仍由
  `ct get --index` 回放与 index CI 的 `verify-index.sh` 负责（契约 §9）。
- **`ct get` 的 >6 字段行**：仍读前六字段（历史行为），verify 严格六字段；差异登记在
  `test/conformance/pkg/differences.md` D2，不在 PH-83 收紧。
- **S83d 平台**：只发 `linux-x64`（D-014 第 6 条）；macOS 上用 zig static musl + QEMU
  验证，不是 Linux 容器；glibc 动态基线仅在 Linux 原生构建时出现，产物以 `linkage` 标明。
- **sanitizer**：`check-sanitizers.sh` 覆盖既有 L0/CT 语料与 p80_retain；`ct index verify`
  是纯 stdio 路径，未单独加 sanitizer 夹具，靠 `p83_verify` 的只读/边界断言覆盖。
- **REVIEW 签收**：S83a 为 no-test 纯文档，REVIEW 席位签收在收口复核时记录；DEV 不自签。

## 8 结论

PH-83 的四项交付（契约 v1、只读 `ct index verify`、conformance、Linux x64 产物）全部落地，
E83-1…8 通过；契约 v1 与 conformance 成为跨仓共用基准，五字段旧行的硬错行为与 `ct get`
逐行一致。遗留项只有 §7.4 列出的上传/跨仓确认与明确非目标，不影响单卡回滚。
