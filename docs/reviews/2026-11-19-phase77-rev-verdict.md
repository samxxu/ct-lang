# v0-PH-77 收口复核（REV）

> **结论：`REV: 通过`**（附 4 项不阻断观察，见 §8）
> **复核对象**：`1aff4deb708a44d8dfd61b0667ce4168502c7ce2`
> （`docs(pkg): v0-PH-77 S0/S4 官方 ct/std 文档与 v0.77.0 收口`），tag `v0.77.0`。
> **复核者**：REV / rev-ph77；日期 2026-11-19。
> **方法**：只依据 tag 归档。用 `git archive v0.77.0 | tar -x -C /tmp/rev-ph77`
> 取源码，在 `/tmp/rev-ph77` 重新自举 L0→L1→L2→ct-ast；红证在 baseline
> `8a30a9f0` 的归档副本 `/tmp/rev-ph77-base` 上重建编译器复现（`ct-ast v0.76.1`）；
> 不使用工作树当前产物，也不采信提交正文的转述。
> **并行说明**：复核期间工作树只有另一会话的未跟踪目录 `battle/static-dispatch-1/`；
> 本报告全部验收都在归档副本上做，verdict 提交只含本文件。

## 1 环境与自举
```console
$ uname -m; uname -sr; cc --version | head -1; gcc --version | head -1; git --version
arm64
Darwin 27.2.0
Apple clang version 21.0.0 (clang-2100.4.1.1)
Apple clang version 21.0.0 (clang-2100.4.1.1)
git version 2.54.0 (Apple Git-157)

$ rm -rf /tmp/rev-ph77 && mkdir -p /tmp/rev-ph77 && git archive v0.77.0 | tar -x -C /tmp/rev-ph77 && cd /tmp/rev-ph77
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev-ph77-build/ctc
$ /tmp/rev-ph77-build/ctc selfhost/l1/ctc.ct -o /tmp/rev-ph77-build/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/rev-ph77-build/l1.c -o /tmp/rev-ph77-build/l1
$ /tmp/rev-ph77-build/l1 build selfhost/l2/driver.ct -o /tmp/rev-ph77-build/l2src
$ cc -Wall -Wextra -std=c99 /tmp/rev-ph77-build/l2src/*.c -o /tmp/rev-ph77-build/l2
$ /tmp/rev-ph77-build/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev-ph77-build/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/rev-ph77-build/astsrc/*.c -o /tmp/rev-ph77-build/ct-ast
$ /tmp/rev-ph77-build/ct-ast -v
ct-ast v0.77.0
```

四段 `cc` 编译日志（`l0.log` / `l1b.log` / `l2b.log` / `astb.log`）均为 0 字节，零警告；
归档的自举版本与 `CTC_VERSION` 一致。

## 2 六个探针（tag 归档 + 重编二进制）
```console
$ sh test/ast/p77_bare.sh /tmp/rev-ph77-build/ct-ast
ok   bare std resolves the built-in pin and ignores the index
ok   ct get acme/std stores the third-party identity
ok   bare hal is refused with the qualified spelling hint
ok   ct get acme/hal uses the index
ok   ct/hal is not pinned and asks for an index
ok   bare std and ct/std resolve the same (url, tag, sha256)
ok   a range outside the pin points at a URL
ok   ct/std locks as ct/std and stores under pkg/ct/std/<ver>
OK p77/bare (pin table, bare-name rule, official identity)

$ sh test/ast/p77_output.sh /tmp/rev-ph77-build/ct-ast
ok   text: source is url@version and the tag is on its own line
ok   quiet: name version url@version
ok   json: a spec field carries url@version
ok   text: a directory source is path@version
ok   quiet: a directory source is path@version
ok   json: a directory source has a spec field
OK p77/output (url@version in text, quiet and json)

$ sh test/ast/p77_migrate.sh /tmp/rev-ph77-build/ct-ast
ok   ct verify only warns on the legacy publisher
ok   the legacy lock and store still build offline
ok   ct install leaves the legacy lock byte-identical
ok   ct update prints the before/after migration line
ok   the lock writes one ct/std row and no std/std row
ok   the old store stays and the new one is added
ok   the migrated lock verifies without a warning and builds
ok   ct build never rewrites the migrated lock
ok   a lock with both identities is refused
ok   ct get refuses to double-write and points at ct update
OK p77/migrate (std/std -> ct/std, old store kept, lock never rewritten by install/build)

$ sh test/ast/p77_docs.sh
ok   package-guide documents the official identity and the built-in pins
ok   package-guide states the three name shapes
ok   package-guide names the pinned std version
ok   AGENTS package table uses ct/std and the pin table
ok   D-010 is linked from the guide
OK p77/docs (official identity, bare-name rule, pin table documented)

$ sh test/ast/p77_install.sh /tmp/rev-ph77-build/ct-ast
ok   install.sh recommends ct get ct/std (both places)
ok   tutorial, README and package-guide agree on the official command
ok   no document recommends the removed bare std form
ok   the documented ct get ct/std@0.19.0 succeeds
ok   the project builds and runs after the documented command
OK p77/install (install.sh / tutorial / README / package-guide agree and run)
```

五支离线探针退出码均为 0。`p77_external.sh` **跑成（联网，未 skip）**（exit 0）：

```console
$ sh test/ast/p77_external.sh /tmp/rev-ph77-build/ct-ast
ok   ct get std succeeds with a clean HOME and no index
ok   the lock is ct/std and the store is pkg/ct/std/<ver>
ok   the fetched tree matches the pinned digest
ok   ct get std and ct get ct/std write the same lock
ok   the official index row matches the built-in pin
OK p77/external (clean-HOME pin, both spellings, index row matches)
```

外部探针在干净 `HOME`/`CT_HOME` 下从零 clone `ct/std`，实测成功，因此 E77-1 的
“无索引成功”与 E77-8 的“另一台干净 HOME”均属于实测而非离线形状推断。

## 3 E77-1…E77-8 逐项对照（[卡 §4](../phases/v0-PH-77/card.md#4-退出判据)）
| 判据 | 证据 | 结果 |
| --- | --- | --- |
| E77-1 | 外部探针：`ct get std succeeds with a clean HOME and no index`；锁行 `ct/std 0.19.0 git https://github.com/ct-pkg/std …`；store `pkg/ct/std/0.19.0` | ✅ |
| E77-2 | 外部探针：`ct get std and ct get ct/std write the same lock`（`cmp -s` 两锁逐字节相同）；离线 `p77_bare` 另比对两者 pin 诊断逐字节相同 | ✅ |
| E77-3 | `p77_bare`：索引含 `std 0.9.9 acme` 时裸 `std` 仍走 pin（digest mismatch 证明 pin 应答）；`acme/std` 取第三方；裸 `hal`/`acme` 硬错并提示 `<publisher>/<name>` | ✅ |
| E77-4 | `p77_output`：文本 `source url@version`、`tag` 单列；`--quiet` 每行 `name version url@version`；`--json` 含 `"spec":"<url>@<version>"`（目录源同样成立） | ✅ |
| E77-5 | `p77_migrate`：打印 `migrate std/std 0.3.2 -> ct/std 0.19.0`；旧 store `pkg/std/std/0.3.2` 与新 store 并存；`ct verify` 只告警；旧锁离线 `ct build` 成功；`ct install`/`ct build` 前后锁逐字节不变；双身份与重复写入均硬错 | ✅ |
| E77-6 | `p77_install`：install.sh 两处、tutorial、README、package-guide 统一 `ct get ct/std@0.19.0`；文档命令实测成功并 build+run；无 `ct get std` 失败写法 | ✅ |
| E77-7 | 独立跑 `tools/check.sh g8` 绿、`test/pkg/run.sh` 147/0；DEV 的 `.temp/p77/check-all-final.log` 汇总 `check-all: OK (11 hard gates green)`；`p77_external` 覆盖 pin/索引一致性；归档 `install.sh` 只依赖 `curl`/`tar`/`cc`，无新增 git/index 安装依赖 | ✅（check-all 采用 DEV 最终日志 + 本报告独立 1–2 gate，见 §9） |
| E77-8 | `ct-pkg/std` v0.19.0 清单 `publisher = ct`、`version = 0.19.0`；索引行六字段含 `ct`；本次干净 HOME `ct get ct/std`（外部探针）成功并匹配 pin 摘要 | ✅ |

## 4 外部一致性（pin 表 / 索引 / manifest）
```console
$ curl -fsSL https://raw.githubusercontent.com/ct-pkg/index/main/index | grep '^std '
std 0.19.0 ct https://github.com/ct-pkg/std v0.19.0 sha256:432086f0ec6c9ef3cdce5e24d465924d207e81d04f97595518d6e7d584ddaa79

$ sed -n '/static const char \*const pnames/,/^    };/p' selfhost/ct-ast/tool/pkg/Pkg.h.ct
    static const char *const pnames[] = { "std" };
    static const char *const pvers[]  = { "0.19.0" };
    static const char *const purls[]  = { "https://github.com/ct-pkg/std" };
    static const char *const ptags[]  = { "v0.19.0" };
    static const char *const pshas[]  = {
        "sha256:432086f0ec6c9ef3cdce5e24d465924d207e81d04f97595518d6e7d584ddaa79"
    };

$ curl -fsSL https://raw.githubusercontent.com/ct-pkg/std/v0.19.0/ct.pkg | grep -E '^(name|publisher|version|ns-root|requires) ='
name = std
publisher = ct
ns-root = .
version = 0.19.0
requires = ct >= 0.67.0
```

| 字段 | 官方索引 `std` 行 | 内置 pin | 一致 |
| --- | --- | --- | --- |
| name | `std` | `std` | ✅ |
| version | `0.19.0` | `0.19.0` | ✅ |
| publisher | `ct` | 调用点硬编码 `"ct"`（表中无独立列，见 §8 O-2） | ✅（行为等价） |
| url | `https://github.com/ct-pkg/std` | 同左 | ✅ |
| tag | `v0.19.0` | `v0.19.0` | ✅ |
| sha256 | `432086f0…daa79` | 同左 | ✅ |

## 5 提交卫生
```console
$ git log --oneline -4
1aff4deb docs(pkg): v0-PH-77 S0/S4 官方 ct/std 文档与 v0.77.0 收口
d72c17ee feat(ast): v0-PH-77 官方包身份、pin 表、输出与旧锁迁移
7772e214 test(ast): v0-PH-77-S0..S5 红
8a30a9f0 docs(tutorial): v0-PH-76 标题改为已实现

$ git rev-parse 7772e214^ d72c17ee^
8a30a9f05fa50107fec7a05ad7dc16411b2e1d37
7772e21431b08e16f7d9162705a8f8d985614dde

$ git merge-base --is-ancestor 8a30a9f0 HEAD && echo yes
yes

$ git show --name-only --format= 1aff4deb | grep -c '^battle/'
0

$ git log --oneline -1 d16d6ffa
d16d6ffa fix(ast): SH-92 void 跳 `$x` 在 `$` 处拒绝（v0.76.1）
```

- 红提交 `7772e214` 的父是 baseline `8a30a9f0`，实现提交 `d72c17ee` 的父是红提交；
  顺序为 `8a30a9f0 → 7772e214 → d72c17ee → 1aff4deb`，满足 6.6 T-7。
- baseline 是 `HEAD` 的祖先（`merge-base --is-ancestor` 为真）。
- `1aff4deb` 路径集合不含 `battle/`；`d16d6ffa` 是此前的 v0-PH-76/SH-92 fix（v0.76.1），
  不是 v0-PH-77 的交付或回归，不在本卡范围。
- 版本 bump 带入的 51 个 golden/expected 仅 banner 版本 token 变化：对
  `1aff4deb^..1aff4deb` 的 `test/cases`、`test/modules` 逐行过滤 `v0.76.x`/`v0.77.0`
  后无其他增删行。

**红证独立复跑**（baseline `8a30a9f0` 归档重编为 `ct-ast v0.76.1`，跑 tag 里的新探针）：

```console
$ for t in p77_bare p77_output p77_migrate p77_docs p77_install; do
>   sh test/ast/$t.sh /tmp/rev-ph77-base-build/ct-ast; echo "$t exit=$?"; done
...
FAIL p77/bare: bare std with an index
  ctc: 'std' is ambiguous; write ct/std or acme/std
FAIL p77/bare: bare hal
  a third-party bare name was accepted
FAIL p77/bare: E77-2 resolution
  > ctc: no index resolver for 'ct/std'
FAIL p77/bare: ct get std@0.3.2
  ctc: no tag of 'std' satisfies '0.3.2'
p77_bare exit=1
p77_output exit=1
p77_migrate exit=1
p77_docs exit=1
p77_install exit=1
```

五支探针在 baseline 上全部红（exit=1），与 `7772e214` 正文的红证方向一致；
在 `1aff4deb` 上全部绿（§2）。

## 6 版本、tag 与门禁
```console
$ for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
>          selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
>   printf '%-28s ' "$f"; grep -m1 '#define CTC_VERSION' "$f"; done
selfhost/l0/ctc.c            #define CTC_VERSION "0.77.0"
selfhost/l1/ctc.ct           #define CTC_VERSION "0.77.0"
selfhost/l2/core.ct          #define CTC_VERSION "0.77.0"
selfhost/l2/driver.ct        #define CTC_VERSION "0.77.0"
selfhost/ct-ast/main.ct      #define CTC_VERSION "0.77.0"

$ git cat-file -t v0.77.0
tag
$ git rev-parse v0.77.0 v0.77.0^{}
58fb3c5d9ae54de065d07dd0f1cf3a35a380da77
1aff4deb708a44d8dfd61b0667ce4168502c7ce2
$ git ls-remote --tags origin 'v0.77.0*'
58fb3c5d9ae54de065d07dd0f1cf3a35a380da77	refs/tags/v0.77.0
1aff4deb708a44d8dfd61b0667ce4168502c7ce2	refs/tags/v0.77.0^{}
$ git cat-file -p v0.77.0
object 1aff4deb708a44d8dfd61b0667ce4168502c7ce2
type commit
tag v0.77.0
tagger Sam X. Xu@macMini <samxxu@gmail.com> 1795091358 +0800

v0-PH-77 closeout (1aff4de)
```

`1aff4deb` 含 `README.md` / `docs/README.md` / `AGENTS.md` / `docs/history/phase-log.md`
的 v0.77.0 记录，版本落点一致。

```console
$ bash tools/check.sh g8
g8: warn: v0.66.0 v0-PH-67: legacy offset MINOR=66 (ledger)
g8: warn: …（v0.67.0–v0.73.0 共 7 行同类 warn，略）
g8: warn: v0.74.0 v0-PH-75: legacy offset MINOR=74 (ledger)
g8: OK (PN-2 version coherence; 9 legacy offsets)

$ bash test/pkg/run.sh
== summary: 147 passed, 0 failed ==
PKG_EXIT=0

$ tail -3 .temp/p77/check-all-final.log
check-all: OK (11 hard gates green)
check-all rc=0
```

## 7 诚实性：DEV 声明逐条核对
> 来件称“4 项风险声明”，实际列出 5 条；以下按 5 条逐条核。

| 声明 | 与代码/卡是否一致 | 依据 |
| --- | --- | --- |
| 离线成功未自动化 | **属实** | 离线 `p77_bare` 的裸 `std` 用例只证明“pin 被应答”（digest mismatch 错误含 pin sha），成功路径只在联网 `p77_external` 中实测；离线硬门禁不自动验证 bare `ct get std` 的成功 clone |
| `p77_external` 网络不可达时 skip 77 | **属实** | 脚本在 git/curl 缺失或索引不可达时 `exit 77`，`check-ast.sh` 以 `skip` 记、不判红；本次网络可达，实测 exit 0，未 skip |
| 迁移不改 `ct.pkg` 范围 | **属实** | `pkg_update_v2` 只读 `ct.pkg`，只写 `ct.lock`；`p77_migrate` 迁移后 `ct.pkg` 原样。注意：因此 `ct.pkg` 若写旧拼法不会被改写（E77-5 未要求） |
| 裸名不查索引 | **属实** | `get_spec` 无斜杠分支只调 `pkg_pin_lookup`，从不读 `have_index`/`CT_INDEX`；`p77_bare` 以索引含 `acme/std` 仍走官方 pin 验证 |
| `README.en` 未同步 | **属实** | `README.en.md:44` 仍写 “a bare name may resolve through `--index` / `CT_INDEX`”，与新契约 §2.2“裸名只查 pin 表、不查索引”相反；E77-6 枚举的四份中文文档不含 `README.en`，故卡未把它写成完成 |

未发现“把未做写成完成”的条目：§3 的 E77-1…E77-8 均有本轮实测或代码/日志证据；
上表第 1、5 条是 DEV 主动声明的残余，不是隐藏缺口。

## 8 观察项（不阻断）
- **O-1 `README.en` 仍写旧解析规则**（DEV 已声明）。`README.en.md:44` 的
  “bare name may resolve through `--index` / `CT_INDEX`”与 D-010 #2/§2.2 相反；
  第 75 行 `ct get std` 本身仍是合法官方裸名，但不是规范写法。建议后续文档 fix
  （按 6.7 V-4 属纯文档，不单独 bump PATCH；若作为缺陷立案则按 V-3）。
- **O-2 pin 表无显式 `publisher` 列**。`pkg_pin_lookup` 的五个数组只有
  name/version/url/tag/sha；`ct` 身份由两处 `fetch_git(..., "ct", ...)` 硬编码，
  并有 `publisher != ct` 的硬错兜底。行为满足 E77-1/E77-8，但与卡 §2.5
  “条目至少含 `publisher = ct`”的字面表述不完全一致；建议卡或代码择一对齐。
- **O-3 external 探针读 `master` 分支**。脚本用
  `raw.githubusercontent.com/ct-pkg/index/master/index`，而索引仓默认分支是 `main`；
  本次两者都返回同一 `std` 行（均 HTTP 200），故通过。若 `master` 退役，探针会
  以“无 std 行”skip 而不再验证一致性；建议改用 `main`。
- **O-4 external 网络抖动可能被记成 hard fail 而非 skip**。DEV 的
  `.temp/p77/check-all.log`（20:18）曾在 `p77_external` 打印
  `ok ct get std succeeds…` 后失败；20:27 的 final 日志与本轮独立运行均 exit 0。
  失败分类依赖 `network_skip` 的错误正则，建议放宽为“取包阶段的网络类非零一律 77”。
  该现象不影响 final 状态与 tag 内容。

## 9 未覆盖声明
- 未由 REV 重跑完整 `selfhost/check-all.sh`（11 道门禁）：采用 DEV 的
  `.temp/p77/check-all-final.log` 最终汇总，并独立跑了 `tools/check.sh g8`、
  `test/pkg/run.sh` 与六个 p77 探针（含联网 external）。
- 未跑 QEMU/Renode 硬件类验收（与本卡无关）。
- 外部一致性以本机联网实测为准；未在“无网络”环境复跑 external（该路径按设计 skip）。
- `README.en` 的不同步是已声明的残余，未在本轮代改（越界角色与范围）。

## 10 结论
**`REV: 通过`**。E77-1…E77-8 均有独立证据；提交顺序、baseline 红证、tag 对象/peeled/
远端、五处版本与 G8/包用例均符合；DEV 的风险声明与代码/卡一致，未发现把未做写成完成。
O-1…O-4 为不阻断观察，建议后续单独处置。
