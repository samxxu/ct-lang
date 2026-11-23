# v0-PH-73 收口复核（REV）

> **结论：`REV: 通过`**（附 6 项不阻断观察，见 §8）
> **复核对象**：`ee1e06d7a2c0abac033af977f52d83a5c2b5b8dc`
> （`feat(ast): v0-PH-73 字段可见性与 ABI 收口（v0.72.0）`），tag `v0.72.0`。
> **复核者**：REV / rev-ph73；日期 2026-11-19。
> **方法**：只依据提交与 clean archive。用 `git archive ee1e06d7` 在 `/tmp/rev73-clean`
> 重新自举 L0→L1→L2→ct-ast；红证用 `git archive 7d8f484c` 在 `/tmp/rev73-base` 重建同一条
> 链复现，不采信转述。
> **并行说明**：复核期间 HEAD 已从 `ee1e06d7` 推进到 `ffc08538`（v0-PH-74），工作树另有未提交
> 改动。本报告对版本与树内容一律用 `git show ee1e06d7:` 或 clean archive 取证；verdict 提交
> 只含本文件，不触碰并行改动。

## 1 环境与自举

```console
$ uname -m; uname -sr; cc --version | head -1; git --version; gh --version | head -1
arm64
Darwin 27.2.0
Apple clang version 21.0.0 (clang-2100.4.1.1)
git version 2.54.0 (Apple Git-157)
gh version 2.104.0 (2026-11-12)
$ rm -rf /tmp/rev73-clean && mkdir -p /tmp/rev73-clean/src
$ git archive ee1e06d7 | tar -x -C /tmp/rev73-clean/src
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev73-clean/ctc
$ /tmp/rev73-clean/ctc selfhost/l1/ctc.ct -o /tmp/rev73-clean/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/rev73-clean/l1.c -o /tmp/rev73-clean/l1
$ /tmp/rev73-clean/l1 build selfhost/l2/driver.ct -o /tmp/rev73-clean/l2src
$ cc -Wall -Wextra -std=c99 /tmp/rev73-clean/l2src/*.c -o /tmp/rev73-clean/l2
$ /tmp/rev73-clean/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev73-clean/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/rev73-clean/astsrc/*.c -o /tmp/rev73-clean/ct-ast
$ /tmp/rev73-clean/ct-ast -v
ct-ast v0.72.0
```

红证基线同链自举（`git archive 7d8f484c` → `/tmp/rev73-base`），`-v` 为 `ct-ast v0.71.0`。

## 2 卡 §3/§6：三个探针逐条跑

clean `ee1e06d7` 树上全部 `rc=0`：

```console
$ sh test/ast/p73_export.sh /tmp/rev73-clean/ct-ast
OK p73/export (pub field surface)
exit=0
$ sh test/ast/p73_abi.sh /tmp/rev73-clean/ct-ast
OK p73/abi (duplicate struct refused)
exit=0
$ sh test/ast/p73_docs.sh /tmp/rev73-clean/ct-ast
OK p73/docs (field visibility documented)
exit=0
```

覆盖字段级 `pub` 的双视图与消费者私有字段构建失败、同名 struct 不同布局硬错、§4.11.2
文档锚点；与卡 §3 的 `verify` 列一致。

## 3 行为复核

### 3.1 公开视图只有 `pub` 字段，单元 `.c` 看全量

独立夹具（`/tmp/rev73-clean/indep`，非 v0-PH-73 探针）：`pub struct Mix` 含 `pub int fd;`、
`pub int id, flags;` 与私有 `int secret;`：

```c
struct Mix {
#ifdef CT_UNIT_PRIVATE
    int fd;
    int id, flags;
    int secret;
    char * name;
#else
    int fd;
    int id, flags;
#endif
};
```

```c
/* mix.c 开头 */
#define CT_UNIT_PRIVATE 1
#include "mix.h"
...
int Mix_peek(struct Mix *self) {
    struct Mix *_self = (struct Mix *)self;
    return (_self->secret + _self->flags);
}
```

公开头是 `#ifdef CT_UNIT_PRIVATE` 双视图；单元 `.c` 先定义宏再包含头，私有字段单元内可用；
`pub int id, flags;` 的两个 declarator 都进公开视图。

### 3.2 无字段 `pub` 的 struct 保持旧行为

同一夹具的 `pub struct Old { int a; int b; }`：头整份发射、无 `#ifdef`，`.c` 也不定义宏：

```c
struct Old {
    int a;
    int b;
};
```

卡要求的 `p39 r8` 与 `test/modules/split`：

```console
$ bash test/modules/p39_lib/r8_probe.sh /tmp/rev73-clean/ct-ast
p39_r8: OK
$ /tmp/rev73-clean/ct-ast build --emit-c test/modules/split/main.ct -o /tmp/rev73-clean/split
$ cc -Wall -Wextra -std=c99 /tmp/rev73-clean/split/*.c -o /tmp/rev73-clean/split.bin
$ /tmp/rev73-clean/split.bin
woof 7     # 与 test/modules/split/expected.out 一致
```

`split` 的 `Dog` 是 `use Speak` 结构且无字段 `pub`，生成头仍是整份布局、无 `#ifdef`；
`--emit-c` 产物与 `baseline.sha` 逐字一致（只归一化版本 token）。旧行为未破。

### 3.3 消费者读私有字段构建失败

```console
$ /tmp/rev73-clean/ct-ast build -I . pub.ct -o out/pub   # 读 m->fd
exit=0
$ /tmp/rev73-clean/ct-ast build -I . priv.ct -o out/priv # 读 m->secret
exit=1
priv.ct:6:20: error: no member named 'secret' in 'struct Mix'
```

### 3.4 带 `use Trait` 的 struct 暂不切分

独立夹具 `pub struct Dog { pub int n; int secret; } use Speak;`：

```c
struct Dog {
    int n;
    int secret;
    const struct Speak_vtbl *__speak_vptr;
};
```

无 `#ifdef CT_UNIT_PRIVATE`，`.c` 也不定义该宏——整份布局进入公开头，与 §4.11.2 一致。

## 4 红证/实现配对与 R2/R3 属性

```console
$ git log --oneline -5 ee1e06d7
ee1e06d7 feat(ast): v0-PH-73 字段可见性与 ABI 收口（v0.72.0）
92e3e3be test(ast): 接入 v0-PH-73 的 abi/docs 探针
504ab873 test(ast)+docs: v0-PH-73-R2/R3 ABI 冲突验收与字段可见性文档
1e08d0c9 feat(ast): v0-PH-73-R1 字段级 pub 决定导出面（LANG-9）
b1a742a4 test(ast): v0-PH-73-R1 红（字段可见性导出面）
$ git rev-parse b1a742a4^ 1e08d0c9^ 504ab873^ 92e3e3be^ ee1e06d7^
7d8f484c79b73a0c2da66f7feb486f03c4df1185
b1a742a4e05470363d41ef1de050a848b7952762
1e08d0c91d21b67bfc12ebb59d919ee29937b693
504ab873a0d13b6f82a6aafb22268e2e6b8bffc5
92e3e3be2f5770396d152ce9e6d3500515910657
$ git merge-base --is-ancestor 7d8f484c ee1e06d7 && echo yes
yes
```

| 提交 | 路径集合 | 结论 |
| --- | --- | --- |
| `b1a742a4`（红） | `A test/ast/p73_export.sh` | 只有测试夹具 |
| `1e08d0c9`（实现） | `check-ast.sh` + `Emitter.h.ct` + `Parser.h.ct` + `Symbols.h.ct` | 实现 + 接线 |
| `504ab873`（R2/R3） | `docs/language-spec.md` + `p73_abi.sh` + `p73_docs.sh` | 验收 + 文档 |
| `92e3e3be`（接线） | `check-ast.sh` | 只接线 |

R1 红/实相邻（`1e08d0c9^ = b1a742a4`），`p73_export.sh` 自红提交后未改。baseline 复跑：

```console
$ sh test/ast/p73_export.sh /tmp/rev73-base/ct-ast
FAIL p73/export: library did not build
  'cc' -std=c99 -I '.ctbuild' '.ctbuild/prog.c' '.ctbuild/s.c' '-o' 'out/prog'
  In file included from .ctbuild/prog.c:3:
  .ctbuild/s.h:10:5: error: unknown type name 'pub'
     10 |     pub int fd;
FAIL p73/export: private field leaked into the public view
exit=1
```

红证正文与实跑一致；baseline 为红提交父提交且是 `HEAD` 祖先。

R2/R3 属性：

- R2：`p73_abi.sh` 在 baseline `7d8f484c` 已绿（`OK p73/abi`，`rc=0`），实现提交未新增该
  行为；卡 §6 写「既有行为验收」属实。两个 `struct T` 布局不同，构建立即拒绝并命名
  `duplicate struct 'T'`。
- R3：`p73_docs.sh` 在 baseline 上四条断言全红（`exit=1`），`ee1e06d7` 全绿；§4.11.2 由
  `504ab873` 新增（`+13` 行），属文档任务，无实现提交。

## 5 语言规范 §4.11.2 与实现一致

（`docs/language-spec.md` 行 809–819 与 clean `ee1e06d7` 产物对照）

| 规范句 | 实现/实测 |
| --- | --- |
| 至少一个字段 `pub` 时，公开头只发射 `pub` 字段 | 3.1 `mix.h`：`#else` 分支只有 `fd`/`id, flags` |
| `.c` 先 `#define CT_UNIT_PRIVATE 1` 再包含头，头内 `#ifdef` 给全量 | 3.1 `mix.c` 与 `mix.h` 逐字对应 |
| 无字段 `pub` 的 struct 保持旧行为 | 3.2 `old.h`：整份布局、无 `#ifdef`、`.c` 无定义 |
| 带 `use Trait` 的 struct 暂不切分 | 3.4 `uses.h`：整份布局、无 `#ifdef` |
| 消费者读私有字段构建期失败 | 3.3 `error: no member named 'secret'` |
| 不透明句柄 `pub struct Conn;` + `Conn *` API | 前置声明可解析；impl 单元一并 build 后构建/链接成功 |

`.abi.h`：`write_abi_header` 只写 ABI 版本/哈希、函数原型与 opaque 前置声明，不含字段布局，
「`.abi.h` 同理只反映公开面」成立（见 §8.6）。

## 6 版本与 tag

```console
$ for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
>          selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
>   printf '%s ' "$f"; git show ee1e06d7:"$f" | grep -c 'CTC_VERSION "0.72.0"'; done
selfhost/l0/ctc.c 1
selfhost/l1/ctc.ct 1
selfhost/l2/core.ct 1
selfhost/l2/driver.ct 1
selfhost/ct-ast/main.ct 1
$ git cat-file -t v0.72.0
tag
$ git rev-parse v0.72.0 'v0.72.0^{commit}'
5f3ff1e8541342a3230f328e91650b12949e0621
ee1e06d7a2c0abac033af977f52d83a5c2b5b8dc
$ git tag -l -n1 v0.72.0
v0.72.0         v0-PH-73 closeout (ee1e06d)
$ git ls-remote --tags origin 'refs/tags/v0.72.0*'
5f3ff1e8541342a3230f328e91650b12949e0621	refs/tags/v0.72.0
ee1e06d7a2c0abac033af977f52d83a5c2b5b8dc	refs/tags/v0.72.0^{}
$ git branch -r --contains ee1e06d7
  origin/HEAD -> origin/main
  origin/main
```

annotated tag、peeled commit = 收口提交、远端 tag 对象与 peeled 值均与本地一致；message 含
`v0-PH-73` 与 sha 前 7 位（裸 `v0-PH-73` 为 phase-ID 迁移 blocker 下的 legacy 形态）。五处落点与
`README.md`/`docs/README.md`/`docs/history/phase-log.md` 的 v0.72.0 一致；G0 与 check-docs 绿：

```console
$ bash tools/check.sh g0 | tail -1
g0: OK (block 1.17.0, session-map present)
$ python3 test/docs/check-docs.py | tail -3
spec pin: skipped (master spec draft 1.17.0)
check-docs: OK (1876 relative links in 313 files, v0.72.0, 11 hard gates, 12 phase status, 3 适用版本 header(s))
design window: ok (12/12)
```

## 7 CI

run：<https://github.com/samxxu/ct-lang/actions/runs/44461759806>
`headSha = ee1e06d7a2c0abac033af977f52d83a5c2b5b8dc`，`workflowName=ci`，`status=completed`，
`conclusion=success`，三个 job 全部 success：

| job | 结果 | 关键行 |
| --- | --- | --- |
| `ubuntu-gcc` | success | `check-all: OK (11 hard gates green)` |
| `macos-clang` | success | `check-all: OK (11 hard gates green)` |
| `ubuntu-clang-smoke` | success | L0 / AST / warning-free 三步全 success |

`ubuntu-gcc` AST 段：

```text
ok    v0-PH-73-R2 abi (duplicate struct refused)
ok    v0-PH-73-R3 docs (field visibility)
ok    v0-PH-73-R1 export (pub field surface)
== summary: 1511 passed, 0 failed, 0 skipped ==
check-all: OK (11 hard gates green)
```

`macos-clang`：同样三条 `v0-PH-73-*` 全 `ok`，`summary: 1505 passed, 0 failed, 5 skipped`，
`check-all: OK (11 hard gates green)`。`ubuntu-clang-smoke`：AST 段三条 `v0-PH-73-*` 全 `ok`、
`1505 passed, 0 failed, 5 skipped`，另跑 L0（`154 passed, 0 failed`）与 warning-free。

## 8 不阻断观察（建议后续处理）

1. **红证格式**：`b1a742a4` 正文只有一行结论，没有 T-7 要求的命令、原始输出与退出码；
   `baseline` 与红/绿父关系正确，REV 已在 §4 独立复现。建议把命令与输出补进 issue 或卡片。
2. **本机完整 `check-ast.sh` 的 4 条红是并行撞车，不是代码缺陷**：完整跑得
   `1503 passed, 4 failed, 4 skipped`，集中在 p41/p43/p44/p45 诊断；这些探针把 stderr 固定
   写到 `/tmp/p41e.err` 等共享路径，复核期间 v0-PH-74 会话并行跑同一套探针导致串读。四条单独
   复跑全绿：`p41/errors: 9 passed`、`p43/errors: 4 passed`、`p44/errors: 11 passed`、
   `p45/contract: 6/6`。CI 与本报告结论不受影响。
3. **`1507 passed` 口径**：收口正文写 `check-ast 1507 passed`，与 CI 的 `ubuntu-gcc 1511/0/0`、
   `macos-clang 1505/0/5` 不同；1507 应是本机 macOS（4 skip）数。建议标注口径或引用 CI 数。
4. **偏离条款文字矛盾（存量）**：`AGENTS.md` 0.3 写「v0-PH-62 起恢复 `d = 0`」，但同段
   `v0-PH-62 → v0.61.0（d=1）`、`v0-PH-64 → v0.63.0（d=1）`，本卡 `72（v0-PH-73，d=1）` 也按 d=1
   收口；版本链 `v0-PH-66→v0.65.0 … v0-PH-73→v0.72.0` 与 d=1 自洽。建议统一为「永久偏移 1」。
5. **`.h.ct` 之外的字段级 `pub` 未拒绝**：普通 `.ct` 单元的
   `pub struct S { pub int a; int b; }` 会发射 `#ifdef CT_UNIT_PRIVATE` 头段，但该单元 `.c`
   不定义宏，`s.b` 到 `cc` 阶段才报 `no member named 'b'`。规范已把字段级 `pub` 限定在
   `.h.ct`，不阻断；建议解析期报错。
6. **R1 实现跨两个提交**：`1e08d0c9` 是主体，`ee1e06d7` 另含 5 行 `CT_UNIT_PRIVATE` 触发
   条件收紧。红/实相邻成立、门禁全绿，但收口提交不再是纯版本/文档。另 `504ab873` 同时承载
   R2/R3 两任务，不能按提交单独回滚（T-4 粒度偏粗）；属小型批处理，不阻断。

## 9 未覆盖声明

- 未在本机完整跑 `bash selfhost/check-all.sh`；11 道门禁以 `ee1e06d7` 的 CI run
  `44461759806` 为准，本机另跑三个 `p73_*`、`p39 r8`、`split`、`g0`、`check-docs.py` 与
  `check-ast.sh`（4 条红见 §8.2，已单独复跑澄清）。
- 未逐条展开 `ubuntu-clang-smoke` 全部日志，只核对三个 step 的 success 与 AST 段三行。
- 按用户限定，本次提交只含本 verdict，不 push；v0-PH-74 未提交改动与 `battle/static-dispatch-1/`
  未跟踪目录均未触碰。
