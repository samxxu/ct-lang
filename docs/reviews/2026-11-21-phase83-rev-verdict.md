# PH-83 收口复核（REV · 2026-11-21）

| 项 | 值 |
| --- | --- |
| 复核对象 | 第一轮：`5378850e`（v0.83.0；tag `v0.83.0` → `958cede3`）；第二轮：`f7db9a72`（v0.83.1；tag `v0.83.1` → `f7db9a72`）；第三轮：`612fa65d`（v0.83.2；tag `v0.83.2` → `612fa65d`） |
| 范围 | 契约 v1（digest 三向量、spec/MVS/单索引、判据矩阵）、只读 `ct index verify`、五字段按行硬错、conformance、Linux x64 产物；E83-1…8、版本/tag/G8/check-all/sanitizer、merge 后 `v0.82.1` 自洽；第二轮另复核 PKG-14 修复（非普通文件/ferror/JSON）；第三轮复核 v0.83.2 的 Linux glibc 默认索引路径自拷贝修复 |
| 方法 | 第一轮：`git archive 5378850e` → 独立自举；跑 p83 四探针；独立 Python 复算三向量；REV 自建 verify 反例；`gh release download v0.83.0`；T-7 红基线复跑；`g0`/`g8`/`check-docs`/`check-all`/`check-sanitizers`。第二轮：`git archive v0.83.1` 自举；重跑全部反例；QEMU Linux 产物验 ferror；`gh release download v0.83.1`；回归 E83-1/3/5/6/7。第三轮：`git archive v0.83.2`；AlmaLinux 9 glibc 容器复现 v0.83.1 红、v0.83.2 绿；x86_64 Linux 容器跑 p83_dist；macOS 35 ok + 1 skip |
| 结论 | 第一轮 **REV: 不通过**（E83-4 未过：`ct index verify` 对目录/设备/FIFO 等非普通文件不返回契约要求的退出码 2，目录甚至输出 `OK (0 rows)`；E83-1/3/5/6/7 通过，E83-2 行为通过但跨仓前置未确认，E83-8 未重跑完整 revert）。第二轮 **REV: 通过**（v0.83.1 PKG-14 已修复并独立复核，见 §14）；第三轮 **v0.83.2 CI 回归复核：通过**（Linux glibc 默认索引路径自拷贝已修复，见 §15） |
| 交付 | 第一轮：本文件；`docs/design/phase83.md` 的 S83a REVIEW 签收；`issues/packages/pkg-14-…` 置 `reopened`；不改代码、不 push。第二轮：本文件 §14；`pkg-14-…` 置 `verified`；不改代码、不 push。第三轮：本文件 §15；PKG-14 保持 `verified`；不改代码、不 push |

> 第二轮（v0.83.1）见 §14、第三轮（v0.83.2）见 §15；第一轮的不通过记录保留在 §5.2/§13，历史不覆盖。

## 1 独立自举（archive，不依赖工作树产物）

```console
$ git archive 5378850e | tar -x -C /tmp/rev-ph83/src
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev-ph83/ctc
$ /tmp/rev-ph83/ctc selfhost/l1/ctc.ct -o /tmp/rev-ph83/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/rev-ph83/l1.c -o /tmp/rev-ph83/l1
$ /tmp/rev-ph83/l1 build selfhost/l2/driver.ct -o /tmp/rev-ph83/l2src
$ cc -Wall -Wextra -std=c99 /tmp/rev-ph83/l2src/*.c -o /tmp/rev-ph83/l2
$ /tmp/rev-ph83/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev-ph83/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/rev-ph83/astsrc/*.c -o /tmp/rev-ph83/ct-ast
$ /tmp/rev-ph83/ct-ast -v
ct-ast v0.83.0
```

七步退出码全 0；四次 C 编译均 `-Wall -Wextra -std=c99`，无告警。后续探针均使用此
`/tmp/rev-ph83/ct-ast`，不依赖工作树 `ctc`/`ct-ast` 产物。

## 2 p83 四探针（同一 archive 构建）

```console
$ sh test/ast/p83_verify.sh /tmp/rev-ph83/ct-ast
ok   legal index exits 0 with the row count
ok   bad index exits 1
ok   legacy row is a per-line hard error (line 3: legacy-five-field)
ok   a four-field row is a field-count error (line 4: field-count)
ok   uppercase hex is rejected (line 5: digest)
ok   a tag that is not v<version> is rejected (line 6: tag-version)
ok   a repeated publisher/name version is rejected (line 7: duplicate)
ok   failure summary counts invalid rows
ok   legacy message matches the contract template
ok   JSON mode keeps exit 1
ok   JSON output is a single line
ok   JSON keys, counts and per-line kinds are stable
ok   legal JSON has ok=true and an empty errors array
ok   an unreadable index exits 2 with the path
ok   no file, CT_INDEX or HOME exits 2
ok   an unknown index subcommand exits 2
ok   'ct index' with no subcommand exits 2
ok   'ct index -h' prints usage and exits 0
ok   an explicit file wins over CT_INDEX
ok   CT_INDEX is used when no file is given
ok   $CT_HOME/index/index is the last resort
ok   -q prints nothing on a legal index
ok   -q keeps the errors and the exit code without the header
ok   verify writes no store/lock file and spawns no git/sh/cc
ok   the index file is unchanged
ok   comments and blank lines are not rows
p83_verify: OK
$ echo $?
0
```

```console
$ sh test/ast/p83_legacy.sh /tmp/rev-ph83/ct-ast
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

```console
$ sh test/ast/p83_conformance.sh /tmp/rev-ph83/ct-ast
ok   v1 has 12 manifest cases
ok   v1 has 3 digest vectors
ok   v1 has the legal/illegal index files
  == manifests (/tmp/rev-ph83/src/test/conformance/pkg/v1/manifests) ==
  ok   manifest ok-basic (ok)
  ok   manifest ok-dot-root (ok)
  ok   manifest err-missing-manifest (missing-manifest)
  ok   manifest err-missing-name (missing-name)
  ok   manifest err-missing-publisher (missing-publisher)
  ok   manifest err-local-publisher (local-publisher)
  ok   manifest err-missing-version (missing-version)
  ok   manifest err-missing-nsroot (missing-nsroot)
  ok   manifest err-nsroot-absolute (nsroot-absolute)
  ok   manifest err-nsroot-dotdot (nsroot-dotdot)
  ok   manifest err-nsroot-not-dir (nsroot-not-dir)
  ok   manifest err-absolute-I (absolute-I)
  == index (/tmp/rev-ph83/src/test/conformance/pkg/v1/index) ==
  ok   legal index (3 rows, both sides clean)
  ok   index illegal rows: CT matches the expected line/kind map
  ok   index illegal rows: shell reference matches the expected map
  ok   index: CT and shell reference agree row by row
  == digest (/tmp/rev-ph83/src/test/conformance/pkg/v1/digest) ==
  ok   digest vector1 (sha256:4da5a4052a2a0afc6c9bbc7cc33cb153755f6f9e77a6efcb46f664aa17d00000)
  ok   digest vector2 (sha256:96c10e74b90d104fb9e789aec2d05189dd090ae1a96a1f739aa74aeaf83986a1)
  ok   digest vector3 (sha256:41743c2b7ecea992d7c1135e3fc78d2c0e020731a1199c85c0ef6308a2b7e888)
  conformance: 19 passed, 0 failed (data: v1)
ok   CT and the shell reference agree on every case
p83_conformance: OK
$ echo $?
0
```

`p83_dist` 使用第 7 节从 GitHub Release 下载的产物（放入 archive 树 `dist/`）：

```console
$ sh test/ast/p83_dist.sh /tmp/rev-ph83/ct-ast --require
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

## 3 E83-1 契约与 digest 三向量

契约文本位于 [`docs/planning/ct-pkg-get-contract.md`](../planning/ct-pkg-get-contract.md)：

```console
$ grep -ci 'TBD' docs/planning/ct-pkg-get-contract.md
0
$ grep -n '^### 3\.3\|^### 4\.1\.1\|^### 4\.4\|^### 6\.1' docs/planning/ct-pkg-get-contract.md
79:### 3.3 包树摘要（digest）
188:### 4.1.1 spec 形态与版本选择（v1 固定）
244:### 4.4 `ct index verify`（只读，ct-lang 负责）
332:### 6.1 判据归属矩阵（v1.1 定稿）
```

- §3.3 有 `collect(root)` 伪代码与三组字节级输入；
- §4.1.1 固定 spec 四形态（裸名 / 限定名 / URL / 本地路径）与 MVS 六实例；
- §4.4 定义 `ct index verify` 的 IV-1…IV-7、输出、JSON、退出码；
- §6.1 矩阵按 `ct-pkg/index@0cdb132a` 基线定稿；PK-3/4/6/7/9–13 明确“无原文、编号保留、不分配归属”，不是 TBD；
- 全文 `grep -ci TBD` = 0，`grep -c 待补` = 1，唯一命中是 §6.1 的“不回到『待补』状态”，不是待办项。

**三向量独立复算**（REV 自己用 Python `hashlib` 按 §3.3 伪代码构造并计算，不读仓库脚本）：

```console
$ python3 - <<'PY'   # REV 按 §3.3 伪代码独立构造并复算
vector1: sha256:4da5a4052a2a0afc6c9bbc7cc33cb153755f6f9e77a6efcb46f664aa17d00000
  files: ['ct.pkg', 'src/demo.h.ct']
vector2: sha256:96c10e74b90d104fb9e789aec2d05189dd090ae1a96a1f739aa74aeaf83986a1
  files: ['ct.pkg', 'src/a/b.ct', 'src/z.h.ct']
vector3: sha256:41743c2b7ecea992d7c1135e3fc78d2c0e020731a1199c85c0ef6308a2b7e888
  files: ['a-file', 'a/file', 'ct.pkg', 'nul.bin']
```

三值与契约 §3.3、`test/conformance/pkg/v1/digest/expect.tsv` 逐字一致；向量 3 的
`nul.bin` 为 `nu\0l`（4 字节、无结尾 LF），排序为 `a-file` < `a/file` < `ct.pkg` < `nul.bin`
（`-` 0x2d < `/` 0x2f）。REV 构造的 `vector1/2/3` 目录与 conformance 数据逐文件 `diff` 为空
（vector2 的 `.git/`、`vendor/`、`.ctcache/` 是 runner 运行时才物化的排除项，见
`vector2.excluded.tsv`）。

**结论：E83-1 通过。**

## 4 E83-2 五字段硬错与 `ct get` 一致性

`p83_legacy` 的 9 条全绿（见 §2）。REV 另用一份自建 bad.index（含五字段旧行与多个坏行）
对照两条命令：

```console
$ /tmp/rev-ph83/ct-ast get --index /tmp/rev-ph83/indep/bad.index acme/old@1.0.0
ctc: index row for 'acme/old 1.0.0' is legacy (five fields); a six-field row is required
$ echo $?
1
$ /tmp/rev-ph83/ct-ast index verify /tmp/rev-ph83/indep/bad.index
...
line 9: legacy-five-field: index row for 'old 1.0.0' is legacy (five fields); a six-field row is required
...
$ echo $?
1
```

- 判定一致：两者都 exit 1，错误模板相同；`ct get` 用请求写法 `acme/old`，verify 用行内裸名
  `old`，契约 §4.4 已解释该差异（旧行没有 publisher 字段）；
- 失败后 `ct.lock` 与 store 均未出现（`lock=NO store=NO`）；
- 同文件六字段行照常安装（`p83_legacy` “a six-field row installs even when the file has legacy rows”）；
- MVS/latest 选中旧行时同样硬错（`p83_legacy` 的三条 MVS/latest 断言）。

**结论：E83-2 的行为条款通过**（跨仓前置未确认）。但卡 §3 的 E83-2 还写了“发布前置已由 index 仓确认”，
而 `issues/packages/pkg-16-external-baseline-and-schedule.md` 的 DEV 证据明确说“仍未由 index 仓
书面确认：五字段旧行清零时间表、CI 如何钉 `ct` 版本、shell 废弃条件”；卡 §7.4 也把跨仓确认
列为遗留。故 E83-2 的跨仓前置应记为**未确认**（不阻断行为判定，见 §12），卡 §3 的该句与
证据不一致，需卡主订正。

## 5 E83-3 / E83-4 只读与退出码

### 5.1 通过项

`p83_verify` 已覆盖：合法索引 exit 0；坏行 exit 1 并给行号/类别；不可读/缺省 exit 2；
未知子命令 exit 2；`--json` 单行、键序稳定；`-q`；单索引优先级；零 store/lock；
零 `git`/`sh`/`cc` 子进程；索引文件不变。

REV 独立复核（读-only HOME + 扩展 PATH shim）：

```console
$ mkdir -p /tmp/rev-ph83/indep/rohome2 && chmod 555 /tmp/rev-ph83/indep/rohome2
$ ( cd /tmp/rev-ph83/indep/proj3 && unset CT_INDEX; \
      HOME=/tmp/rev-ph83/indep/rohome2 CT_HOME=/tmp/rev-ph83/indep/rohome2/.ct \
      PATH=/tmp/rev-ph83/indep/bin3 /tmp/rev-ph83/ct-ast index verify /tmp/rev-ph83/indep/legal2.index )
index: /tmp/rev-ph83/indep/legal2.index
index verify: OK (1 rows)
$ echo $?
0
# HOME 前后文件列表一致；index cksum 不变；无 spawned-*；无 ct.lock
$ ( cd /tmp/rev-ph83/indep/proj3 && unset CT_INDEX CT_HOME HOME; /tmp/rev-ph83/ct-ast index verify )
ct-ast: no index file and no CT_INDEX/CT_HOME/HOME
$ echo $?
2
```

JSON 稳定性（同一个自建坏索引连跑两次 + 路径转义 + `CT_INDEX` 相对路径）：

```console
$ /tmp/rev-ph83/ct-ast index verify /tmp/rev-ph83/indep/bad.index --json > bad1.json
$ /tmp/rev-ph83/ct-ast index verify /tmp/rev-ph83/indep/bad.index --json > bad2.json
$ cmp -s bad1.json bad2.json && echo identical
identical
$ cat bad1.json
{"index":"/tmp/rev-ph83/indep/bad.index","ok":false,"rows":9,"valid":2,"invalid":7,"errors":[{"line":3,"kind":"identity","message":"index publisher 'local' must be non-empty, not 'local', without '/'"},{"line":4,"kind":"field-count","message":"index row has 3 fields; six are required"},{"line":5,"kind":"tag-version","message":"index tag 'v9.9.9' must be 'v1.0.0'"},{"line":6,"kind":"digest","message":"index digest must be sha256:<64 lowercase hex>"},{"line":8,"kind":"duplicate","message":"index row 'acme/zeta 1.0.0' appears more than once"},{"line":9,"kind":"legacy-five-field","message":"index row for 'old 1.0.0' is legacy (five fields); a six-field row is required"},{"line":10,"kind":"field-count","message":"index row has 7 fields; six are required"}]}
$ /tmp/rev-ph83/ct-ast index verify '/tmp/rev-ph83/indep/weird"name\index' --json
{"index":"/tmp/rev-ph83/indep/weird\"name\\index","ok":true,"rows":1,"valid":1,"invalid":0,"errors":[]}
# Python json.load 回读 index 字段与实参逐字相同
$ ( cd /tmp/rev-ph83/indep/proj && CT_INDEX=rel.index /tmp/rev-ph83/ct-ast index verify --json )
{"index":"rel.index","ok":true,"rows":1,"valid":1,"invalid":0,"errors":[]}
```

JSON 键序固定为 `index, ok, rows, valid, invalid, errors`；`errors` 每项为
`line, kind, message`，按行号升序；重复运行字节相同；路径不做绝对化。
**E83-3 通过。**

### 5.2 阻断项：非普通文件输入不返回 2（目录 → `OK (0 rows)`；FIFO → 挂起）

契约 §4.4 的退出码表（[`ct-pkg-get-contract.md:286`](../planning/ct-pkg-get-contract.md#L286)）写：

```text
0 全部合法；1 存在坏行；2 用法错误、索引不存在或不可读。
```

E83-4（[`phase83.md:78`](../design/phase83.md#L78)）要求“退出码 0/1/2 语义与契约 §7 一致”。
`ct index verify` 对**目录**（以及 `/dev/null`、指向目录的 symlink、`CT_INDEX` 指向目录、
`$CT_HOME/index/index` 是目录）返回 **0**，并打印 `OK (0 rows)`；`--json` 则输出 `"ok":true`：

```console
$ mkdir -p /tmp/rev-ph83/indep/dir.index
$ ( cd /tmp/rev-ph83/indep/proj2 && HOME=/tmp/rev-ph83/indep/home \
      CT_HOME=/tmp/rev-ph83/indep/home/.ct /tmp/rev-ph83/ct-ast index verify /tmp/rev-ph83/indep/dir.index )
index: /tmp/rev-ph83/indep/dir.index
index verify: OK (0 rows)
$ echo $?
0
$ ( cd /tmp/rev-ph83/indep/proj2 && HOME=/tmp/rev-ph83/indep/home \
      CT_HOME=/tmp/rev-ph83/indep/home/.ct /tmp/rev-ph83/ct-ast index verify /tmp/rev-ph83/indep/dir.index --json )
{"index":"/tmp/rev-ph83/indep/dir.index","ok":true,"rows":0,"valid":0,"invalid":0,"errors":[]}
$ echo $?
0
$ ( cd /tmp/rev-ph83/indep/proj2 && CT_INDEX=/tmp/rev-ph83/indep/dir.index /tmp/rev-ph83/ct-ast index verify )
index: /tmp/rev-ph83/indep/dir.index
index verify: OK (0 rows)
$ echo $?
0
$ ( cd /tmp/rev-ph83/indep/proj2 && HOME=/tmp/rev-ph83/indep/badhome \
      CT_HOME=/tmp/rev-ph83/indep/badhome /tmp/rev-ph83/ct-ast index verify )
index: /tmp/rev-ph83/indep/badhome/index/index
index verify: OK (0 rows)
$ echo $?
0
```

发布产物（第 7 节下载的 `ct-linux-x64.tar.gz`）同样复现：

```console
$ sh selfhost/run-linux-binary.sh /tmp/rev-ph83/release/unpack/ct index verify /
index: /
index verify: OK (0 rows)
$ echo $?
0
```

FIFO 则没有退出码——`ct index verify` 在 `fopen` 后阻塞在 `fgets`：

```console
$ mkfifo pipe.index
$ timeout 2 /tmp/rev-ph83/ct-ast index verify /tmp/rev-ph83/indep/pipe.index
fifo: TIMEOUT (verify blocks on a FIFO, no regular-file guard)
```

**代码定位**：`selfhost/ct-ast/tool/pkg/Pkg.h.ct:2674` 只做 `f = fopen(path, "r")`；
循环在 `:2688` 用 `fgets`；`:2803` 直接 `fclose(f)`，`:2838` 按 `nerr` 返回，**没有
`stat`/`S_ISREG` 也没有 `ferror(f)` 检查**。`fgets` 在目录/FIFO/设备上的读错误被当成
“文件结束”，空索引于是得到 `OK (0 rows)`。目录不是索引文件，读错误也不是合法的 0 行
索引；契约要求 exit 2，实际 exit 0（JSON 还给出 `ok:true`）。这是 CI 门禁的**假绿**，
且 FIFO 会让门禁挂起。

**期望**：对 `stat` 后非 `S_ISREG` 的输入直接 exit 2（stderr 给路径与原因）；循环后检查
`ferror(f)`，读错误同样 exit 2；`--json` 不得在 exit 2 时输出 `ok:true`。最小修复点在
`Pkg.h.ct:2674`/`:2803`；补一条 `p83_verify` 反例（目录/FIFO）。

**结论：E83-4 不通过。** 这是本轮判定 `REV: 不通过` 的唯一阻断项。

## 6 E83-5 conformance

`p83_conformance` 19 passed（§2）；数据形状被 runner 钉住（12 个 manifest case、3 个 digest
向量、legal/illegal 两个索引文件），shell 与 CT 共用同一份 `test/conformance/pkg/v1/` 数据。
`differences.md` 登记 8 条已知差异（D1–D8），`run.sh` 对未登记差异直接红，不存在静默跳过。
REV 另用 §3 的独立 Python 实现复算三向量，与 CT/shell 的期望值一致。
**E83-5 通过。**

## 7 E83-6 Linux x64 产物与 tag/Release

从 GitHub Release 下载并校验：

```console
$ gh release download v0.83.0 --pattern 'ct-linux-x64.tar.gz*' --dir /tmp/rev-ph83/release
$ cd /tmp/rev-ph83/release
$ shasum -a 256 ct-linux-x64.tar.gz
b04afe2e8efb214fdc73a1a374d053cab95789a5918014b06dc152f7f483ac39  ct-linux-x64.tar.gz
$ cat ct-linux-x64.tar.gz.sha256
b04afe2e8efb214fdc73a1a374d053cab95789a5918014b06dc152f7f483ac39  ct-linux-x64.tar.gz
$ tar -tzf ct-linux-x64.tar.gz
ct
ctc
$ file -b unpack/ct
ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, with debug_info, not stripped
```

`p83_dist --require` 用 QEMU Alpine 实跑 `unpack/ct -v`：`ct v0.83.0`（§2）。tag / Release /
版本一致：

```console
$ git cat-file -t v0.83.0
tag
$ git rev-parse v0.83.0^{commit}
958cede3654731858ab1fd0dc12530558a94bf5e
$ git for-each-ref refs/tags/v0.83.0 --format='%(taggername) %(taggerdate:iso) %(contents:subject)'
Sam X. Xu@macMini 2026-11-21 04:32:22 +0800 PH-83 closeout (958cede3)
$ git ls-remote origin 'refs/tags/v0.83.0*'
9a64f0040080346020ec8928dbe023dc745182ee	refs/tags/v0.83.0
958cede3654731858ab1fd0dc12530558a94bf5e	refs/tags/v0.83.0^{}
$ gh release view v0.83.0 --json tagName,isDraft,isPrerelease,assets
tagName=v0.83.0, isDraft=false, isPrerelease=false
asset ct-linux-x64.tar.gz digest=sha256:b04afe2e... (size 1226810)
```

五处 `CTC_VERSION` 均为 `0.83.0`（§8）；`git diff v0.83.0 HEAD` 为空（HEAD 合并后树与 tag
树一致）。**E83-6 通过。**

## 8 E83-7 版本 / golden / check-all / sanitizer

```console
$ for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
           selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
    grep -H '#define CTC_VERSION' "$f"; done
selfhost/l0/ctc.c:#define CTC_VERSION "0.83.0"
selfhost/l1/ctc.ct:#define CTC_VERSION "0.83.0"
selfhost/l2/core.ct:#define CTC_VERSION "0.83.0"
selfhost/l2/driver.ct:#define CTC_VERSION "0.83.0"
selfhost/ct-ast/main.ct:#define CTC_VERSION "0.83.0"

$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2193 relative links in 364 files, v0.83.0, 11 hard gates, 12 phase status,
5 适用版本 header(s), 2 superseded link(s), 6 signoff(s))
```

`g8` 的 9 条 legacy offset 告警均来自 `version-legacy-offsets.tsv`（v0.66.0–v0.74.0），
v0.83.0 的 `PH-83 closeout` 消息与 MINOR=83 相符（v0.83.0 本身无告警）。check-docs 的
2193/364 是本文件入库后的计数；卡 §7.3 的 2189/363 是本文件入库前的计数。

check-all（工作树，`TMPDIR=.temp/rev-ph83/all`）：

```console
$ TMPDIR=$PWD/.temp/rev-ph83/all bash selfhost/check-all.sh
...
== summary: 156 passed, 0 failed ==          # L0
== 169 checks, 0 failed ==                   # package manager
== summary: 153 passed, 0 failed ==          # archive
  ok    PH-83-S83b verify (E83-3/4: read-only, line numbers, JSON, 0/1/2)
  ok    PH-83-S83b legacy (E83-2: five-field hard error, per-row, six-field unaffected)
  ok    PH-83-S83c conformance (E83-5: shared data, CT vs shell, 3 digest vectors)
  ok    PH-83-S83d dist (E83-6: sha256, ELF x86-64, unpacked ct -v; 77 without dist)
== summary: 1549 passed, 0 failed, 4 skipped ==  # AST
== summary: 20 pass, 0 new, 0 pending, 0 regression ==  # acceptance（仅报告）
check-warnings: 490 ok, 0 failed
check-all: OK (11 hard gates green)
$ echo $?
0
```

与卡 §7.3 的 `1548 passed, 5 skipped` 相差 1：本轮工作树存在产物 `dist/`，`p83_dist`
因此由 skip 变 pass；archive 树无 `dist/` 时应回到 1548/5。两者均 0 failed。

sanitizer：

```console
$ TMPDIR=$PWD/.temp/rev-ph83/san bash selfhost/check-sanitizers.sh
...
check-sanitizers: OK (583 checks, no sanitizer report)
$ echo $?
0
```

golden 范围：

```console
$ git diff --name-only v0.82.0 v0.83.0 -- 'test/**/*.expected.*' | wc -l
51
$ git diff -U0 v0.82.0 v0.83.0 -- 'test/**/*.expected.*' \
    | grep -E '^[+-][^+-]' | grep -vE 'v0\.8[0-9]\.[0-9]'
（无输出）
```

51 个 expected/ABI banner 仅版本 token 变化，无非版本内容改动。**E83-7 通过。**

## 9 E83-8 回滚

未独立重跑完整 revert：在临时克隆中 `git revert b5873c40 2a0a0d38` 于
`selfhost/check-ast.sh` 与 `selfhost/ct-ast/main.ct` 冲突（后续 S83c/S83d/收口提交改了同一
门禁与版本行），需要人工解冲突；本轮不把卡 §7.1 的演练升级为独立证据。代码路径核对：
`ct get` 的 `pkg_index_lookup`/`get_one` 不调用 `ct_index_verify`；`make-dist.sh` 只读
`main.ct` 的 `CTC_VERSION` 并调用既有 bootstrap；撤回 S83b/S83d 不改变这两条路径。
**E83-8：未独立复跑（不阻断本次不通过结论，见 §12）。**

## 10 T-7 红证独立复跑

用 `git archive 1764b4d6` 重建 ct-ast（`ct-ast v0.82.0`），把三个红提交里的探针脚本与
conformance 数据放进该树后运行：

```console
$ sh test/ast/p83_verify.sh /tmp/rev-ph83/red83/ct-ast; echo $?
FAIL p83/verify: ...  # 22 条
p83_verify: (no OK)
1
$ sh test/ast/p83_legacy.sh /tmp/rev-ph83/red83/ct-ast; echo $?
FAIL p83/legacy: ...  # 5 条
1
$ sh test/ast/p83_conformance.sh /tmp/rev-ph83/red83/ct-ast; echo $?
FAIL p83/conformance: runner missing: test/conformance/pkg/run.sh
1
$ sh test/ast/p83_dist.sh /tmp/rev-ph83/red83/ct-ast --require; echo $?
FAIL p83/dist: no artefact at dist/ct-linux-x64.tar.gz (run selfhost/make-dist.sh)
1
```

FAIL 数 `22 + 5` 与卡 §6 的注记一致；四条均红。父提交链逐一核对：

```console
d22a5077^ = 1764b4d6   b5873c40^ = d22a5077
7cbd5792^ = b5873c40   f1a1146a^ = 7cbd5792
23c00b0b^ = f1a1146a   2a0a0d38^ = 23c00b0b
029d0d97^ = 2a0a0d38
```

T-7 成立；S83a 为纯文档 `no-test`，由本复核签收（§13）。

## 11 merge 后 `v0.82.1` 自洽 / 版本 / tag

```console
$ git cat-file -t v0.82.1
tag
$ git rev-parse v0.82.1^{commit}
c07ebfa885779e38f2fa98a95ae5fbc81c4b6d41
$ git for-each-ref refs/tags/v0.82.1 --format='%(taggername) %(taggerdate:iso) %(contents:subject)'
Sam X. Xu@macMini 2026-11-21 04:12:44 +0800 SH-103 fix (c07ebfa8)
$ git merge-base --is-ancestor v0.82.1 HEAD && echo ancestor
ancestor
$ git show v0.82.1:selfhost/ct-ast/main.ct | grep '#define CTC_VERSION'
#define CTC_VERSION "0.82.1"
$ git show v0.82.1:README.md | grep -o 'v0\.82\.[0-9]' | head -1
v0.82.1
$ git show v0.82.1:docs/history/phase-log.md | grep -n 'v0\.82\.1'
187:| v0.82.1 | SH-103 Linux 字段表自拷贝修复（2026-11-21） | ...
$ git ls-remote origin 'refs/tags/v0.82.1*'
7ff0cc8d2663ddfbcd7302d9f3662b9ee1b31844	refs/tags/v0.82.1
c07ebfa885779e38f2fa98a95ae5fbc81c4b6d41	refs/tags/v0.82.1^{}
```

- `v0.82.1` 是 annotated tag，指向 c07ebfa8；该提交树内 `CTC_VERSION`、README、phase-log 均为
  0.82.1，自洽；
- c07ebfa8 不是 958cede3 的祖先（v0.83.0 分支与 v0.82.1 分支从 029d0d97 分叉），但通过
  `5378850e` merge 成为 HEAD 的祖先；不要求线性，符合任务口径；
- merge 提交 `5378850e` 的第一父为 958cede3、第二父为 c07ebfa8；HEAD 树与 `v0.83.0` 树
  逐字节相同（`git diff v0.83.0 HEAD` 为空），即 merge 保留 v0.82.1 历史而冲突取 v0.83.0；
- 远端 tag v0.82.1 / v0.83.0 的 annotated 对象与解引用提交均与本地一致。

## 12 不阻断观察

1. **E83-2 的跨仓前置未确认（证据不一致）**：卡 §3 E83-2 写“发布前置已由 index 仓确认”，
   但 PKG-16 的 DEV 证据与卡 §7.4 都写明“仍未由 index 仓书面确认：五字段旧行清零时间表、
   CI 如何钉 `ct` 版本、shell 废弃条件”。行为判定不受影响，但该句应改为“待 index 仓确认”
   或从 E83-2 拆出，避免把未确认项记为已确认。
2. **`ct get` 对畸形 digest 的失败是静默的**：REV 用 `digest=sha256:ABCDEF` 的索引行测试，
   `ct get` 返回 1 但 stdout/stderr 均为空；verify 能给出 `digest` 行号与消息。建议 `ct get`
   在索引解析失败时至少打一行诊断（不改变退出码）。
3. **`--json` 与 `-q` 的组合未定义**：实现中 `--json` 忽略 `-q`（仍输出完整 JSON），契约未写
   该组合；建议在 §4.4 明确“`--json` 优先”。
4. **check-all 计数与卡 §7.3 的 1548/5 差 1**：本轮 `dist/` 存在，`p83_dist` 由 skip 变
   pass（1549/4）；archive 树无 `dist/` 时为 1548/5。两者均 0 failed，不是回归。
5. **E83-8 未独立重跑完整 revert**：见 §9；卡 §7.1 的演练记录与代码路径一致，但本轮未把
   它升级为独立证据。若后续修复 E83-4 时需要回滚演练，应重新执行并贴原始输出。
6. **`p83_verify` 的“unreadable”用例只覆盖不存在路径**：`p83_verify.sh:129` 用
   `$work/no-such.index`，没有目录/设备/FIFO 用例；本轮的阻断项正是从该测试盲区发现的。
   修复 E83-4 时应同时补目录与 FIFO 负例，否则探针仍可能假绿。

## 13 结论与交付

**REV: 不通过。**

- E83-1 通过：契约三向量经独立 Python 复算一致；§4.1.1/§4.4/§6.1 齐全，全文无 TBD。
- E83-2 行为通过：五字段按行硬错、与 `ct get` 模板一致、六字段不受影响、MVS/latest 同判；
  但“发布前置已由 index 仓确认”未成立（PKG-16 仍开放）。
- E83-3 通过：零网络/零子进程/零 store/lock；坏行给行号；JSON 稳定、单行、路径转义可解析。
- **E83-4 不通过**：目录、`/dev/null`、目录 symlink、`CT_INDEX` 指向目录、
  `$CT_HOME/index/index` 为目录均返回 exit 0 + `OK (0 rows)`（JSON `ok:true`）；FIFO 挂起；
  发布产物对 `/` 同样返回 0。契约 §4.4 要求“用法错误/索引不可读 → 2”，实现只 `fopen`，
  未 `stat`/`S_ISREG`、未查 `ferror`。
- E83-5 通过：19 passed；12 manifest / 3 digest / legal+illegal index；差异 8 条登记。
- E83-6 通过：Release 产物 sha256 匹配、解包 `ct -v` = v0.83.0；tag/Release/五处版本一致。
- E83-7 通过：check-all 11 门绿；sanitizer 583；g0/g8/check-docs 绿；51 golden 仅版本 token。
- E83-8 未独立复跑完整 revert（代码路径核对通过；见 §9/§12）。

**S83a 签收**：S83a 为纯文档任务，契约/矩阵经本复核独立验算（三向量、无 TBD、矩阵归属），
已在 `docs/design/phase83.md` §5 补 `签收: REVIEW 2026-11-21`。

**issue 状态**：`PKG-14`（只读 `ct index verify` 与 Linux x64 产物）置 `reopened`，
附最小复现与 `Pkg.h.ct:2674`/`:2803` 定位；PKG-12/13/15 未改状态（见 §12 第 1 条与
跨仓确认口径），PKG-16 仍开放。

本轮不改实现代码、不 push、不改 tag/Release。

## 14 第二轮复核（v0.83.1，2026-11-21）

> **REV: 通过**（PKG-14 已修复并独立复核；第一轮 `REV: 不通过` 保留在 §5.2/§13，历史不覆盖）

### 14.1 自举与 T-7

```console
$ git archive v0.83.1 | tar -x -C /tmp/rev831/src
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev831/ctc
$ /tmp/rev831/ctc selfhost/l1/ctc.ct -o /tmp/rev831/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/rev831/l1.c -o /tmp/rev831/l1
$ /tmp/rev831/l1 build selfhost/l2/driver.ct -o /tmp/rev831/l2src
$ cc -Wall -Wextra -std=c99 /tmp/rev831/l2src/*.c -o /tmp/rev831/l2
$ /tmp/rev831/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev831/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/rev831/astsrc/*.c -o /tmp/rev831/ct-ast
$ /tmp/rev831/ct-ast -v
ct-ast v0.83.1
```

T-7 父链：`c72349fe^ = 8014739e`、`f7db9a72^ = c72349fe`；`5378850e..8014739e` 的
`selfhost/` diff 为 0（8014739e 是第一轮 review 提交）。用 v0.83.0 archive 构建
（`ct-ast v0.83.0`）跑 `c72349fe` 的新 `p83_verify`，红证 8 条 FAIL、exit 1：

```console
$ sh /tmp/rev831/red/p83_verify.sh /tmp/rev-ph83/ct-ast
FAIL p83/verify: directory input
FAIL p83/verify: directory JSON
FAIL p83/verify: /dev/null input
FAIL p83/verify: directory symlink
FAIL p83/verify: CT_INDEX directory
FAIL p83/verify: CT_INDEX directory JSON
FAIL p83/verify: CT_HOME directory
FAIL p83/verify: FIFO input
$ echo $?
1
```

### 14.2 上轮反例逐项（v0.83.1 archive 构建）

全部使用 `/tmp/rev831/ct-ast`，`HOME`/`CT_HOME` 隔离；文本模式：

```console
$ ct-ast index verify /tmp/rev831/indep/adir
ct-ast: not a regular file: '/tmp/rev831/indep/adir'      # stderr
$ echo $?
2
$ ct-ast index verify /dev/null
ct-ast: not a regular file: '/dev/null'
$ echo $?
2
$ ct-ast index verify /tmp/rev831/indep/dirlink          # symlink -> dir
ct-ast: not a regular file: '/tmp/rev831/indep/dirlink'
$ echo $?
2
$ HOME=/tmp/rev831/indep/home CT_HOME=/tmp/rev831/indep/home/.ct \
    CT_INDEX=/tmp/rev831/indep/adir ct-ast index verify
ct-ast: not a regular file: '/tmp/rev831/indep/adir'
$ echo $?
2
$ HOME=/tmp/rev831/indep/badhome CT_HOME=/tmp/rev831/indep/badhome ct-ast index verify
ct-ast: not a regular file: '/tmp/rev831/indep/badhome/index/index'
$ echo $?
2
$ ct-ast index verify /dev/zero
ct-ast: not a regular file: '/dev/zero'
$ echo $?
2
```

JSON 模式（目录；其余来源同形）：

```console
$ ct-ast index verify /tmp/rev831/indep/adir --json
{"index":"/tmp/rev831/indep/adir","ok":false,"rows":0,"valid":0,"invalid":1,
 "errors":[{"line":0,"kind":"io","message":"not a regular file: '/tmp/rev831/indep/adir'"}]}
$ echo $?
2
```

FIFO（python3 5 秒看门狗；不再挂起）：

```console
$ mkfifo /tmp/rev831/indep/fifo.index
$ python3 ... # subprocess.run(timeout=5)
fifo rc: 2  out:  err: ct-ast: not a regular file: '/tmp/rev831/indep/fifo.index'
# 另一次 --json 运行：ok=false, line=0, kind=io；5 秒内返回
```

Unix socket 同样：

```console
$ ct-ast index verify /tmp/rev831/indep/sock.index
ct-ast: not a regular file: '/tmp/rev831/indep/sock.index'
$ echo $?
2
```

### 14.3 普通文件 symlink / 六字段回归

```console
$ ln -s /tmp/rev831/indep/legal.index /tmp/rev831/indep/legal.link
$ ct-ast index verify /tmp/rev831/indep/legal.link
index: /tmp/rev831/indep/legal.link
index verify: OK (3 rows)
$ echo $?
0
$ ct-ast index verify /tmp/rev831/indep/legal.link --json
{"index":"/tmp/rev831/indep/legal.link","ok":true,"rows":3,"valid":3,"invalid":0,"errors":[]}
$ echo $?
0
```

六字段行：`ct-ast index verify good.index` → `OK (1 rows)` exit 0；
`ct-ast get --index good.index acme/util@1.0.0` → exit 0，lock 的 digest 与索引行一致。
`p83_legacy` 9 条 ok；`ct get` 命中五字段旧行的消息仍与 verify 同模板。

### 14.4 Release v0.83.1

```console
$ gh release download v0.83.1 --pattern 'ct-linux-x64.tar.gz*'
$ shasum -a 256 ct-linux-x64.tar.gz
7265d00a9d0e93aabeb5a91ee06212c8ff8853430da8db9a595c13aa79749c35  ct-linux-x64.tar.gz
$ cat ct-linux-x64.tar.gz.sha256
7265d00a9d0e93aabeb5a91ee06212c8ff8853430da8db9a595c13aa79749c35  ct-linux-x64.tar.gz
$ tar -tzf ct-linux-x64.tar.gz
ct
ctc
$ run-linux-binary.sh unpack/ct -v
ct v0.83.1
$ sh test/ast/p83_dist.sh /tmp/rev831/ct-ast --require
...
p83_dist: OK
$ echo $?
0
```

tag / Release / 版本：

```console
$ git cat-file -t v0.83.1
tag
$ git rev-parse v0.83.1^{commit}
f7db9a72a64e32a3344e62728231e90e8042b0a5
$ git for-each-ref refs/tags/v0.83.1 --format='%(contents:subject)'
PKG-14 fix (f7db9a72)
$ git ls-remote origin 'refs/tags/v0.83.1*'
57dfbc5e... refs/tags/v0.83.1
f7db9a72... refs/tags/v0.83.1^{}
$ gh release view v0.83.1 --json tagName,isDraft,isPrerelease
tagName=v0.83.1, isDraft=false, isPrerelease=false
```

Release 资产 digest 与下载文件 sha256 相同；五处 `CTC_VERSION` 均为 `0.83.1`；
`git diff v0.83.1 HEAD` 为空。

### 14.5 ferror（QEMU Linux 产物）

用 v0.83.1 Release 的静态 Linux 产物在 QEMU Alpine 内实跑：

```console
$ run-linux-binary.sh ct index verify /proc/self/mem
ct: error reading the package index '/proc/self/mem'
$ echo $?
2
$ run-linux-binary.sh ct index verify /proc/self/mem --json
{"index":"/proc/self/mem","ok":false,"rows":0,"valid":0,"invalid":1,
 "errors":[{"line":0,"kind":"io","message":"error reading the package index"}]}
$ echo $?
2
$ run-linux-binary.sh ct index verify / --json
{"index":"/","ok":false,"rows":0,"valid":0,"invalid":1,
 "errors":[{"line":0,"kind":"io","message":"not a regular file: '/'"}]}
$ echo $?
2
```

`p83_verify` 在 macOS 上 `skip ferror (no /proc/self/mem on this host)`，Linux 上看门狗/
ferror 断言由上述 QEMU 实跑覆盖。

### 14.6 E83-1/3/5/6/7 回归与门禁

```console
$ sh test/ast/p83_legacy.sh /tmp/rev831/ct-ast      -> p83_legacy: OK
$ sh test/ast/p83_conformance.sh /tmp/rev831/ct-ast -> 19 passed, 0 failed; p83_conformance: OK
$ sh test/ast/p83_dist.sh /tmp/rev831/ct-ast --require -> p83_dist: OK
$ sh test/ast/p83_verify.sh /tmp/rev831/ct-ast      -> 34 ok + 1 skip; p83_verify: OK
```

E83-1 契约：`grep -ci TBD` = 0；§3.3/§4.1.1/§4.4/§6.1 齐全；三向量与 conformance
数据未变，REV 独立 Python 复算仍为 `4da5…` / `96c1…` / `4174…`。E83-3：p83_verify 的
零 store/lock、零 `git`/`sh`/`cc`、索引不变，以及 REV 的只读 HOME + PATH shim 均通过。
E83-5：19 passed，差异仍 8 条。E83-6：见 §14.4。E83-7：

```console
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (..., v0.83.1, 11 hard gates, 12 phase status, ...)
$ TMPDIR=$PWD/.temp/rev831/all bash selfhost/check-all.sh
...
== summary: 156 passed, 0 failed ==          # L0
== 169 checks, 0 failed ==                   # package manager
== summary: 153 passed, 0 failed ==          # archive
== summary: 1549 passed, 0 failed, 4 skipped ==  # AST
== summary: 20 pass, 0 new, 0 pending, 0 regression ==  # acceptance（仅报告）
check-warnings: 490 ok, 0 failed
check-all: OK (11 hard gates green)
$ echo $?
0
$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (583 checks, no sanitizer report)
$ echo $?
0
```

51 个 golden/ABI banner 仍只变版本 token；五处版本均为 `0.83.1`。

### 14.7 不阻断观察

1. 卡 §5 的 PKG-14 行写 `p83_verify: OK`（26），实际 v0.83.1 为 **34 ok + 1 skip**
   （macOS skip ferror）；§7.5 的“其余 26 条 + 8 新”与 34 一致，§5 的 26 是旧计数，
   建议订正（不阻断）。
2. E83-2 的跨仓前置仍未由 index 仓书面确认（PKG-16 仍开放）；行为判定通过，未阻断。
3. `ct get` 对畸形 digest 仍静默 exit 1（第一轮 §12 第 2 条），非 PKG-14 范围。
4. check-all 计数 `1549/4` 与卡 §7.3 的 `1548/5` 差 1：工作树 `dist/` 存在，`p83_dist`
   由 skip 变 pass；不是回归。
5. `--json` 与 `-q` 组合仍未在契约中定义（第一轮 §12 第 3 条），不阻断。

### 14.8 结论

**REV: 通过。** PKG-14 的修复独立复现：目录、`/dev/null`、目录 symlink、`CT_INDEX` 目录、
`$CT_HOME/index/index` 目录、FIFO、socket、`/dev/zero` 均 exit 2；`--json` 为 `ok:false` +
`line:0 kind:"io"`；FIFO 不挂起；普通文件 symlink 仍可读；ferror 在 QEMU Linux 产物上
exit 2；六字段与 legacy 行为不变；Release sha256 `7265d00a…`、`ct -v` = v0.83.1；E83-1/3/5/6/7
回归通过；check-all 11 门、sanitizer 583、g0/g8/check-docs 全绿。PKG-14 置 `verified`。
本轮不改代码、不 push。

## 15 v0.83.2 CI 回归复核（2026-11-21）

> **v0.83.2 CI 回归复核：通过**（PKG-14 保持 `verified`；第一/二轮记录保留在 §13/§14）

### 15.1 问题与修复

v0.83.1 的 `pkg_index_verify` 默认索引分支先令 `ip = path`（`$CT_HOME/index/index`），随后
`snprintf(path, sizeof path, "%s", ip)` 把 `path` 自拷贝进自身。重叠对象上的 `snprintf` 是
C 未定义行为：glibc 返回空串，`stat('')` 失败 → `CT_HOME` 默认用例 exit 2；macOS libc
恰好原地复制，故 macOS 绿（与 SH-103 字段表自拷贝同类）。v0.83.2 改为
`if (ip != path) snprintf(path, sizeof path, "%s", ip);`；`p83_verify` 增/强化两条断言：
`$CT_HOME/index/index` 目录的 stderr 必须带完整解析路径；默认 `CT_HOME` 的
`--json.index` 必须等于 `$CT_HOME/index/index`。

### 15.2 Linux glibc 容器（AlmaLinux 9.1 aarch64，glibc 2.34，gcc 11.5）

从 `git archive` 分别构建 v0.83.1 与 v0.83.2，同一容器、同一工作目录：

```console
# v0.83.1 二进制 + v0.83.2 的 p83_verify
$ sh test/ast/p83_verify.sh /root/ct-ast831
FAIL p83/verify: CT_HOME directory
FAIL p83/verify: CT_HOME default
FAIL p83/verify: CT_HOME default path
# 33 ok + 3 FAIL，exit 1

# v0.83.2 二进制
$ sh test/ast/p83_verify.sh /root/ct-ast832
...
ok   $CT_HOME/index/index being a directory exits 2 (with the resolved path)
ok   $CT_HOME default JSON carries the full resolved path
...
p83_verify: OK
# 36 ok，exit 0
```

默认路径的最小对照（合法 `$CT_HOME/index/index`）：

```console
$ HOME=/root/indep/home CT_HOME=/root/indep/home /root/ct-ast831 index verify --json
{"index":"","ok":false,"rows":0,"valid":0,"invalid":1,
 "errors":[{"line":0,"kind":"io","message":"cannot read the package index ''"}]}
$ echo $?
2
$ HOME=/root/indep/home CT_HOME=/root/indep/home /root/ct-ast832 index verify --json
{"index":"/root/indep/home/index/index","ok":true,"rows":1,"valid":1,"invalid":0,"errors":[]}
$ echo $?
0
```

三种来源路径（v0.83.2）：

```console
$ # 默认 $CT_HOME/index/index
{"index":"/root/indep/home/index/index","ok":true,...}          # rc=0
$ # CT_INDEX
{"index":"/root/indep/custom.index","ok":true,...}              # rc=0
$ # 显式文件
{"index":"/root/indep/explicit.index","ok":true,...}            # rc=0
$ # $CT_HOME/index/index 为目录
{"index":"/root/indep/badhome/index/index","ok":false,
 "errors":[{"line":0,"kind":"io","message":"not a regular file: '...'"}]}  # rc=2
$ # FIFO
ct-ast: not a regular file: '/root/indep/fifo'                  # rc=2，5s 内返回
```

`p83_legacy` 9 ok；`p83_conformance` 19 passed（最小 AlmaLinux 镜像需先装 `diffutils`，
否则 runner 的 `diff` 不存在会报空原因；装上后全绿，属环境前置，不是产品缺陷）。

### 15.3 Linux x86_64 容器 / macOS

x86_64 Alpine 容器（Linux，binfmt 运行 x86_64 Release 产物）：

```console
$ sh test/ast/p83_verify.sh /root/ct-release
p83_verify: OK          # 36 ok
$ sh test/ast/p83_dist.sh /root/ct-release --require
ok   sha256 matches 63e6c1e666c67d708fe05955eed4ea1c6c045a6867319f3b43d512b5b88e15ca
ok   the tarball contains ct and ctc only
ok   ELF 64-bit x86-64 ...
ok   unpacked ct -v prints 'ct v0.83.2'
ok   host compiler agrees on v0.83.2
p83_dist: OK             # 8 ok
```

macOS（archive 构建 v0.83.2）：`p83_verify: OK`，**35 ok + 1 skip**（`skip ferror (no
/proc/self/mem on this host)`）；`p83_dist` 的 `ct -v` 由 QEMU 验证为 `ct v0.83.2`。

### 15.4 Release v0.83.2

```console
$ gh release download v0.83.2 --pattern 'ct-linux-x64.tar.gz*'
$ shasum -a 256 ct-linux-x64.tar.gz
63e6c1e666c67d708fe05955eed4ea1c6c045a6867319f3b43d512b5b88e15ca  ct-linux-x64.tar.gz
$ cat ct-linux-x64.tar.gz.sha256
63e6c1e666c67d708fe05955eed4ea1c6c045a6867319f3b43d512b5b88e15ca  ct-linux-x64.tar.gz
$ tar -tzf ct-linux-x64.tar.gz
ct
ctc
$ run-linux-binary.sh unpack/ct -v
ct v0.83.2
```

tag / Release / 版本：

```console
$ git cat-file -t v0.83.2
tag
$ git rev-parse v0.83.2^{commit}
612fa65dea7ce6642f9eee5cb167cbc63bee9ff0
$ git for-each-ref refs/tags/v0.83.2 --format='%(contents:subject)'
PKG-14 Linux CT_HOME fix (612fa65d)
$ git ls-remote origin 'refs/tags/v0.83.2*'
d70c48ca... refs/tags/v0.83.2
612fa65d... refs/tags/v0.83.2^{}
$ gh release view v0.83.2 --json tagName,isDraft,isPrerelease
tagName=v0.83.2, isDraft=false, isPrerelease=false
```

Release 资产 digest 与下载文件 sha256 相同；五处 `CTC_VERSION` 均为 `0.83.2`；
`git diff v0.83.2 HEAD` 为空。

### 15.5 T-7 与 E83 回归 / 门禁

T-7：`d49982c6^ = fa6f8fba`、`612fa65d^ = d49982c6`；红提交只改
`test/ast/p83_verify.sh`，fix 提交的代码改动只落在 `Pkg.h.ct`/`main.ct`（`p83_verify` 在 fix 上 0 行 diff）。
红证在 glibc 容器复跑为 33 ok + 3 FAIL（`CT_HOME directory`/`CT_HOME default`/
`CT_HOME default path`），与卡 §7.6 一致。

E83-1/3/5/6/7 回归：

```console
$ p83_legacy: OK (9)             # Linux glibc 容器
$ p83_conformance: OK (19 passed) # Linux glibc 容器（装 diffutils 后）
$ p83_dist: OK (8)                # Linux x86_64 容器
$ bash tools/check.sh g0          -> g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8          -> g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py -> OK (2196 links / 364 files, v0.83.2, ...)
$ TMPDIR=$PWD/.temp/rev832/all bash selfhost/check-all.sh
  == summary: 156 passed, 0 failed ==          # L0
  == 169 checks, 0 failed ==                   # package manager
  == summary: 153 passed, 0 failed ==          # archive
  == summary: 1548 passed, 0 failed, 5 skipped ==  # AST
  == summary: 20 pass, 0 new, 0 pending, 0 regression ==  # acceptance（仅报告）
  check-warnings: 490 ok, 0 failed
  check-all: OK (11 hard gates green)
$ TMPDIR=$PWD/.temp/rev832/san bash selfhost/check-sanitizers.sh
  check-sanitizers: OK (583 checks, no sanitizer report)
```

51 个 golden/ABI banner 仍只变版本 token；E83-1 三向量/契约无 TBD；E83-5 数据未变。

### 15.6 不阻断观察

1. `p83_conformance` 在最小 AlmaLinux 容器里需要 `diff`（diffutils）；未装时 runner 报
   `FAIL index CT:` 空原因，装上后 19 passed。属容器环境前置，不是产品缺陷；CI 镜像已有
   `diff`。
2. E83-2 的跨仓前置仍未由 index 仓书面确认（PKG-16 仍开放）；行为判定通过，未阻断。
3. `ct get` 对畸形 digest 仍静默 exit 1（第一轮 §12 第 2 条），非 PKG-14 范围。
4. 卡 §7.6 的 Linux 红证用 v0.83.2 的测试脚本跑 v0.83.1 二进制（3 FAIL，含新增的
   `CT_HOME default path`）；若只用 v0.83.1 自带脚本则是 2 FAIL。两种口径都指向同一
   自拷贝缺陷，本复核两种都复现过。

### 15.7 结论

**v0.83.2 CI 回归复核：通过。** Linux glibc 容器上 v0.83.1 的 `CT_HOME` 默认路径自拷贝
（`index:""`、exit 2）在 v0.83.2 消失：默认/`CT_INDEX`/显式三种来源的 `--json.index`
均为完整解析路径，目录/FIFO 仍 exit 2；Linux glibc 36 ok、Linux x86_64 容器 36 ok、
macOS 35 ok + 1 skip；`p83_dist` 8 ok、`ct -v` = v0.83.2；Release sha256 `63e6c1e6…`；
E83-1/3/5/6/7 与 check-all/sanitizer/g0/g8/check-docs 全绿。PKG-14 保持 `verified`。
本轮不改代码、不 push。
