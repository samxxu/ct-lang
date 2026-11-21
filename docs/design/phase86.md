# Phase 86 — v1-pre：词法器重写

> **状态：完成（v0.86.0）**（2026-11-21 立项并开卡；2026-11-21 收口）。
> **签收：EDITOR 2026-11-21**（主编统一签收；卡作者 REQ）。
> **施工闸门**：PH-85 已收口（v0.85.0，E85-2 有条件通过/D-018）；本卡按 D-018 的
> per-function 结论执行。
> **前置**：PH-85；[D-017](../decisions/D-017.md)（两级判据、token `Str` 生命周期）。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase86.md`。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-86（legacy 文件 `phase86.md`） |
| 目标 | 词法器下沉到最终形态：token 为源缓冲的 `Str` 视图，零拷贝；NUL/长度契约统一 |
| 范围 | token 表示、词素生命周期、`strcmp`/`printf` 迁移、错误路径（`?`/errdefer）、goldens |
| 非目标 | 改词法规则/关键字/诊断文本；解析器/检查器/发射器重写（PH-87/88）；M1 精细切分 |
| 交付物 | 词法器重写、`test/ast/p86_*`、spec/tutorial 片段、度量报告 |
| 任务清单 | §2（S86a–S86d） |
| 退出判据 | E86-1…E86-8（§3） |
| version-minor | 86（PH-86，`d=0`） |
| 已知风险 | R86-1…R86-5（§4） |

## 1 需求与边界

### 1.1 token 与生命周期（D-017 B4）

- token 文本 = **源缓冲的 `Str` 视图**（`ptr+len`），不复制、不保证 NUL；
- 源缓冲生命周期覆盖整个解析阶段；任何超出该窗口的持有都是违约；
- 现有 `strcmp` / `printf("%s")` / `strdup` 系统性迁移：
  - 比较改长度比较；
  - C 边界改 `cstr()`（调用方 free）；
  - 诊断/输出改带长度或先转 `String`。

### 1.2 等价判据（D-017 A1）

- 测试语料发射产物逐字节不变；
- 编译器自身实现的发射 C 允许差异；验收 = 自举不动点 + ASan + 行为测试；
- 诊断文本（错误/警告）不变。

### 1.3 边界

- 不改词法规则、关键字集合、token 种类；
- 不改解析器/检查器/发射器；跨子系统接口保持；
- 不顺手做文件精细切分（M1 留 v1.1）。

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S86a token 视图 | token 文本改 `Str` 视图；生命周期断言 | `p86_tokens` | M |
| S86b C API 迁移 | `strcmp`/`printf`/`strdup` → 长度比较/`cstr()` | `p86_capi` | M |
| S86c 错误路径 | `?`/errdefer 改造；诊断文本不变 | `p86_errors` | M |
| S86d 文档/度量 | spec/tutorial 词法片段；行数/耗时报告 | `p86_docs` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；
S86d 可写 `no-test:`，由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E86-1 | token 为源缓冲 `Str` 视图；无逐 token 拷贝；生命周期覆盖解析阶段 |
| E86-2 | NUL 相关 C API 已迁移；`cstr()` 仅在 C 边界使用且调用方释放 |
| E86-3 | 测试语料发射逐字节不变；编译器自身发射差异按两级制处理 |
| E86-4 | 诊断文本与既有负例一致；行为测试/ASan 通过 |
| E86-5 | `check-all` 全绿；无新增警告 |
| E86-6 | 行数/编译耗时报告入库（对照 PH-85 spike） |
| E86-7 | spec/tutorial 的词法/字符串边界段落同步；示例可编译或为明确负例 |
| E86-8 | 单卡回滚：词法器可退回旧实现，接口不变 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R86-1 | token 生命周期越界悬垂 | 源缓冲覆盖解析阶段；ASan；负例 |
| R86-2 | 非 NUL 文本误用 C API | 迁移清单 + grep 门禁；`cstr()` 唯一出口 |
| R86-3 | 零拷贝后比较/输出变慢 | 长度比较；spike 基线；必要时局部缓存 |
| R86-4 | 顺手改词法规则 | 非目标写死；diff 审阅只批等价 |
| R86-5 | 与 M0 单元边界冲突 | M0 已完成；本卡只改函数体 |

回滚：单卡回滚；token 接口保持，解析器无需同步改动。

## 7 收口（2026-11-21，v0.86.0）

**状态：完成。** 签收：EDITOR 2026-11-21（收口证据见 §7.2；S86c 的范围裁定待
REVIEW 在 [battle/p86-errorpath](../../battle/p86-errorpath/verdict.md) 签字）。

### 7.1 任务红绿（T-7）

| 任务 | `test(…) 红` | 实现 | 红证（baseline `1e2c30f7`） | 绿证 |
| --- | --- | --- | --- | --- |
| S86a token 视图 | `10f3378e` | `3c41b5b7` | `p86tokens: 11 passed, 18 failed` | `p86tokens: 29 passed, 0 failed` |
| S86b C API 迁移 | `82322670` | `7425d28d` | `p86capi: 14 passed, 6 failed`（toktext 728 / strcmp 458 / strncmp 6 / strlen 10 / emitted toktext） | `p86capi: 20 passed, 0 failed` |
| S86c 错误路径 | `ba860576` | `11432e0a` | `p86errors: 10 passed, 13 failed`（审计/证据未写） | `p86errors: 23 passed, 0 failed` |
| S86d 文档/度量 | `a7265a67` | `b40e6b1c` | `p86docs: 2 passed, 21 failed` | `p86docs: 23 passed, 0 failed` |
| 探针接线 | — | `32e0d5f1` | — | check-ast 四条 p86 探针 |
| PH-85 快照探针适配 | — | `f21176c5` | `P85_BASELINE=0000…` 三条全红 | `p85inventory 9/0`、`p85m0 4/0`、`p85spike 14/0` |

### 7.2 退出判据 E86-1…8（原始输出）

| ID | 断言 | 命令 | 原始输出 |
| --- | --- | --- | --- |
| E86-1 | token 为源缓冲 `Str` 视图；无逐 token 拷贝；生命周期覆盖解析 | `bash test/ast/p86_tokens.sh .temp/p86b/ct-ast .temp/p86b/astsrc` | `p86tokens: 29 passed, 0 failed` |
| E86-2 | NUL 相关 C API 已迁移；`cstr()` 仅在 C 边界且调用方释放 | `bash test/ast/p86_capi.sh …` | `p86capi: 20 passed, 0 failed` |
| E86-3 | 测试语料逐字节不变；自身发射按两级制 | `corpus-manifest` + 自举 | `diff -q` 空（66 文件）；`diff -rq self86b self86b2` 空 |
| E86-4 | 诊断文本与既有负例一致；行为/ASan 通过 | `bash test/ast/p86_errors.sh …` | `p86errors: 23 passed, 0 failed`（345 条 exit+sha256、8 条逐字） |
| E86-5 | `check-all` 全绿；无新增警告 | `bash selfhost/check-all.sh` | `check-all: OK (11 hard gates green)`；check-ast `1565 passed, 0 failed, 5 skipped`；`check-warnings: 500 ok, 0 failed` |
| E86-6 | 行数/编译耗时报告入库（对照 PH-85 spike） | `bash test/ast/p86_docs.sh …` | `p86docs: 23 passed, 0 failed`；[p86_metrics](p86_metrics.md)：391→458 行、1053.2→1080.2 ms |
| E86-7 | spec/tutorial 词法/字符串边界同步；示例可编译 | 同上 | tutorial §19 示例编译运行输出 `hello, world` |
| E86-8 | 单卡回滚：词法器可退回旧实现，接口不变 | 反向应用 `3c41b5b7`/`7425d28d` 后重建 | 链构建 rc=0；`01_hello` 输出 `hello ast`；66 语料逐字节一致 |

E86-8 回滚命令（在 `HEAD` 归档上反向应用两个源码提交）：

```console
$ git archive HEAD | tar -x -C /tmp/p86roll
$ git show 7425d28d --format= | (cd /tmp/p86roll && git apply -R)
$ git show 3c41b5b7 --format= | (cd /tmp/p86roll && git apply -R)
$ sh .temp/build-ct-ast.sh /tmp/p86roll /tmp/p86rollbuild    # rc=0
$ /tmp/p86rollbuild/ct-ast test/ast/01_hello/prog.ct -o /tmp/hello.c && cc … && /tmp/hello.bin
hello ast
$ python3 tools/p85_inventory.py --root . corpus-manifest --ct … | diff test/probes/p85_corpus_sha.tsv -
(exit 0；无输出)
```

### 7.3 S86c 范围裁定（`?`/errdefer）

卡 §2 要求 S86c 做 `?`/errdefer 改造；实做改为“错误出口清单 + 诊断逐字不变”，
理由与证据见 [p86_errors.md](p86_errors.md) §3 与
[battle/p86-errorpath](../../battle/p86-errorpath/verdict.md)：

1. ct-ast 由 L2 引导构建，L2 没有 PH-40/PH-44 的下降；源码写 `?`/errdefer 会
   原样发射、`cc` 失败（`test/probes/p86_bootstrap_evidence.txt`）；
2. 词法器无错误通道（D-018 引 p85_spike §3 #5），本卡不新造；
3. 唯一 `own` 资源 `read_file` 的源缓冲改 `Result`/`?` 会动跨子系统接口。

这是**判据降级**，不是“通过”：E86-4 的字面目标（诊断不变）已由 345 条对照 +
8 条词法边界负例满足；`?`/errdefer 的“改造”未发生。PH-87/88 的同名判据建议 REQ
在开卡前裁定（先补引导层，或降级为 `no-test` 文档项），本卡不代决。

### 7.4 例外与未覆盖（诚实）

| # | 项 | 处置 |
| --- | --- | --- |
| 1 | token 视图类型是 `TokView`，不是 `lib/std` 的 `Str` | L2 引导链不认识 std 层；PH-81 又禁止 `Str` 作为 struct 字段。`TokView` 与 `Str` 同布局 `{ptr,len}`，字节零拷贝；见 Lexer 头注释 |
| 2 | 整数 T_NUM 的 token 文本仍是“上一个 token”的视图 | 旧 `toktext` 的既有行为；`int f(1)` 的 `expected a type (tok 2 '(')` 依赖它。为诊断逐字不变而保留，`p86_errors/stale_num_diag` 钉住 |
| 3 | `?`/errdefer 未改造 | §7.3；battle/p86-errorpath 待 REVIEW |
| 4 | 源缓冲进程内不释放 | 既有行为；视图生命周期因此覆盖解析；AST 只存 `tok_copy` 副本 |
| 5 | 精细文件切分（M1） | 非目标，v1.1 S1 |
| 6 | ASan/UBSan | 由 `selfhost/check-sanitizers.sh` 覆盖；本卡新增路径为视图读写与 `tok_copy`，随全量 sanitizer 跑 |

### 7.5 全门禁（原始输出）

```console
$ bash selfhost/check-all.sh
check-all: OK (11 hard gates green)                      # 7m35s
  == summary: 1565 passed, 0 failed, 5 skipped ==        # check-ast
  # 5 skips = 本机无 QEMU/Renode/GDB/FreeRTOS 资产，探针显式 skip
$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (586 checks, no sanitizer report)   # ASan+UBSan，S86b tip
$ bash selfhost/check-warnings.sh
check-warnings: 500 ok, 0 failed
$ bash selfhost/check-goldens.sh
check-goldens: OK (no regression, and the self-hosted rebuild agrees)
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2351 relative links in 382 files, v0.86.0, 11 hard gates,
                12 phase status, 6 适用版本 header(s), 2 superseded link(s),
                10 signoff(s))
```

- sanitizer 在 S86b tie 运行；此后只动 `CTC_VERSION`/文档，代码相同（E86-5 的
  “无新增警告”由 check-warnings 的 500/0 覆盖）。
- `dist/`（gitignored）用 `selfhost/make-dist.sh --out "$PWD/dist" --cross
  .temp/ph83/zig/zig --no-smoke` 重建到 0.86.0；`p83_dist.sh` 的 `ct -v` 与宿主
  一致。第一次 check-all 因本地 dist 还是 0.85.0 在 p83/dist 失败，重建后复跑 11/11
  ——这是本地产物过期，不是源码回归。
- 版本落点五处 `CTC_VERSION`、51 个 golden/ABI banner、README/docs/README 与
  AGENTS 的当前版本同收口提交更新到 `0.86.0`。
