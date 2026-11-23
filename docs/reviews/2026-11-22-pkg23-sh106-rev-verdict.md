# PKG-23 / SH-106 复核（REV，2026-11-22）

> **结论：PKG-23 `reopened`（T-4）；SH-106 `verified`。**
> HEAD `c1b54d2f`（v0.88.2，未 push/tag）；PKG-23 `00eb6df1`（v0.88.1）、
> SH-106 `c1b54d2f`（v0.88.2）。
>
> 方法：只依据提交与 clean archive。用 `git archive` 在 `/tmp` 重新自举
> L0→L1→L2→ct-ast，不使用工作树产物与工作树二进制；红证用 `git archive`
> 基线重建二进制、把落地后的探针交给基线。私有 `TMPDIR`。工作树另有他人
> 未提交的 `docs/reviews/2026-11-21-full-review-v0.88.0-disposition.md`，
> 本复核未使用、未提交。未 push、未改实现、未打 tag。

## 0 结论

| issue | status | 依据 |
| --- | --- | --- |
| PKG-23 | **reopened** | 功能面 5/5 绿、红证可复现、成功路径/锁行/digest 不变；但 `git archive 00eb6df1` 的 `selfhost/check-ast.sh:1330` 引用不存在的 `test/ast/p106_str_escape.sh`（SH-106 钩子混入 PKG-23 提交），归档不可独立运行 check-ast；`git revert c1b54d2f` 后同一行仍指向已删除文件。违反 T-4。见 §2.4。 |
| SH-106 | **verified** | `p106_str_escape.sh` 28/28；红证 15 条可复现；9 负例 + 7 正例；`ct build` warning / `ct check`、`--types` error 与 E79-6 同口径；`allow-escape` 同行豁免；五处版本、51 banner、p80/p81/p82、g0/g8/g6/check-docs/warnings/sanitizer 全绿；提交只含 SH-106 自己的路径。见 §3。 |

## 1 环境与独立构建

```console
$ git rev-parse HEAD
c1b54d2f5be91c41cfa6dde5450e8e13ee22ba4d
$ cc --version | head -1 && python3 --version
Apple clang version 21.0.0 (clang-2100.4.1.1) / Python 3.15.2
$ mkdir -p /tmp/rev-final/{p23,sh106}/src
$ git archive 00eb6df1 | tar -x -C /tmp/rev-final/p23/src
$ git archive c1b54d2f | tar -x -C /tmp/rev-final/sh106/src
```

两条同链自举（产物落 `/tmp/rev-final/{p23,sh106}/build`，链上 stderr 全空）：
`cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc` → `./ctc selfhost/l1/ctc.ct -o l1.c`
→ `cc l1.c -o l1` → `./l1 build selfhost/l2/driver.ct -o l2src` → `cc l2src/*.c -o l2`
→ `./l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o astsrc` → `cc astsrc/*.c -o ct-ast`。

```console
$ /tmp/rev-final/p23/build/ct-ast -v   →  ct-ast v0.88.1
$ /tmp/rev-final/sh106/build/ct-ast -v →  ct-ast v0.88.2
```

## 2 PKG-23

### 2.1 功能绿（clean archive `00eb6df1`）

```console
$ sh test/ast/pkg23_git_diag.sh /tmp/rev-final/p23/build/ct-ast
ok   an unreachable remote names network/proxy and gives a retry action
ok   a corrupt cache names the cache path, rm -rf and --refresh
ok   a missing pinned tag is classified as remote tag/object missing
ok   an authentication failure is classified and credentials are redacted
ok   --refresh discards the corrupt cache and fetches the pin again
OK pkg23 (network, corrupt cache, missing tag, auth, refresh)   EXIT=0
```

origin 不符（测试脚本未覆盖该分支完整文案）：

```console
$ HOME=/tmp/rev-final/origin/home ct-ast get std
ctc: cache for 'ct/std' has a different origin
  expected: https://github.com/ct-pkg/std
  recorded: https://evil.example/ct/std
  cache: /tmp/rev-final/origin/home/.cache/ct-pkg/ct/std
  next: rm -rf '/tmp/rev-final/origin/home/.cache/ct-pkg/ct/std' and retry, or run 'ct get --refresh ct/std@0.19.0'
EXIT=1
```

### 2.2 红证复现（baseline `4edc70e9`，`600e6595` 的父提交）

```console
$ git archive 4edc70e9 | tar -x -C /tmp/rev-final/base463/src   # 同链自举 → ct-ast v0.88.0
$ sh test/ast/pkg23_git_diag.sh /tmp/rev-final/base463/build/ct-ast
FAIL pkg23: network diagnostic
  ctc: git fetch of 'https://github.com/ct-pkg/std' failed
FAIL pkg23: corrupt-cache diagnostic
  ctc: cache for 'ct/std' has a different origin; remove '.../.cache/ct-pkg/ct/std' and retry
FAIL pkg23: missing-tag diagnostic
  ctc: git checkout of 'v0.19.0' failed
FAIL pkg23: authentication diagnostic
  ctc: git fetch of 'https://github.com/ct-pkg/std' failed
FAIL pkg23: --refresh diagnostic
  ctc: unknown option '--refresh'
FAIL pkg23: --refresh did not reach the pinned-digest check
EXIT=1
```

### 2.3 成功路径 / 锁行 / digest（干净 HOME，真实网络）

```console
$ HOME=/tmp/rev-final/home-get2 ct-ast get std
resolved   ct/std 0.19.0
  source   https://github.com/ct-pkg/std@0.19.0
  tag      v0.19.0
  commit   ae8dd94f205b8350114c8d827c1ce3b9fb8e314c
  store    /tmp/rev-final/home-get2/.ct/pkg/ct/std/0.19.0
  digest   sha256:432086f0ec6c9ef3cdce5e24d465924d207e81d04f97595518d6e7d584ddaa79
  action   installed
$ cat ct.lock
# ct-lock 2
ct/std 0.19.0 git https://github.com/ct-pkg/std ae8dd94f205b8350114c8d827c1ce3b9fb8e314c . sha256:432086f0ec6c9ef3cdce5e24d465924d207e81d04f97595518d6e7d584ddaa79
$ diff /tmp/rev-final/proj-base/ct.lock /tmp/rev-final/proj-get2/ct.lock && echo IDENTICAL
IDENTICAL
$ HOME=/tmp/rev-final/home-get2 ct-ast get std | tail -1
1 package(s): 0 installed, 1 reused
```

失败路径不写锁、不残留 `.ct-pkg.err`；`--refresh` 只删目标包、保留同根 sibling
（`other/marker` 仍在），重建后到达 pinned-digest 检查。

### 2.4 提交独立性（blocking，T-4）

`00eb6df1` 的 `selfhost/check-ast.sh` 同时加了 PKG-23 与 SH-106 两个钩子；
SH-106 的文件直到 `c1b54d2f` 才存在：

```console
$ git cat-file -e 00eb6df1:test/ast/p106_str_escape.sh; echo $?
fatal: path 'test/ast/p106_str_escape.sh' exists on disk, but not in '00eb6df1'
128
$ git blame -L 1325,1335 00eb6df1 -- selfhost/check-ast.sh
00eb6df12 ... 1325  # SH-106: the borrowed `Str` view escape lint ...
00eb6df12 ... 1330  if sh test/ast/p106_str_escape.sh "$work/ct-ast" ...
$ sh test/ast/p106_str_escape.sh /tmp/rev-final/p23/build/ct-ast
sh: test/ast/p106_str_escape.sh: No such file or directory      EXIT=127
$ bash selfhost/check-ast.sh          # 00eb6df1 archive，私有 TMPDIR
  FAIL  SH-106 Str view escape: sh: test/ast/p106_str_escape.sh: No such file or directory
== summary: 1570 passed, 7 failed, 5 skipped ==                     EXIT=1
```

（另 6 条是 archive 环境项：p85/p87/p88 的 `fatal: not a git repository` 与
v0-PH-77 external 外部探针；不是 PKG-23。SH-106 这条是提交内容缺陷，换 clone 同样红。）
回滚侧同样不成立：

```console
$ git checkout c1b54d2f && git revert --no-edit c1b54d2f   # /tmp 临时克隆
$ grep -n p106_str_escape selfhost/check-ast.sh
1330:if sh test/ast/p106_str_escape.sh "$work/ct-ast" ...
$ sh test/ast/p106_str_escape.sh ...; echo $?                  → 127
```

即 `git revert c1b54d2f` 后门禁仍引用已删除文件，违反 T-4「单任务回滚后其他任务的
门禁不受影响」。PKG-23 的 `test(ct-ast): PKG-23 红`（`600e6595`）也不在实现的父提交
（中间隔 5 个无关提交），严格 T-7 形式同样不满足；红证本身可复现（§2.2）。

### 2.5 `--refresh` 的 `rm -rf` 路径

- 注入：`git_name` 只取 URL 最后一段，`sh_quote` 单引号化后才拼进 `system()`；
  用 `https://127.0.0.1:1/$(touch /tmp/rev-final/PWNED; echo x)` 实测无 `PWNED`，
  失败信息里的 URL 也按字面输出。
- 越界：`https://h/..`（`..`）与 `https://h/.`（`.`）会让 `cache` 解析成
  `~/.cache/ct-pkg/..` / `~/.cache/ct-pkg/.`，即 cache 根之外/根本身；实测
  `rm` 拒绝 `.`/`..`（`rm: "." and ".." may not be removed`），未删除任何东西。
  因此**当前不可利用**，但代码没有自己强制「严格位于 root 内」，只依赖 `rm` 的
  兜底。建议组合 `cache` 后校验 `name`/`cache_pub` 非空且不等于 `.`/`..`、不含
  `/`，或对 `cache` 做 `realpath` 后断言前缀为 `root/`。
- 同根 sibling、失败路径、无 `--refresh` 复用均正常（§2.3）。

### 2.6 判定

功能交付通过，但 `00eb6df1` 不是可独立运行门禁的提交（T-4），且回滚 SH-106 会留下
悬空钩子。置 `reopened`；最小修法见 §4。

## 3 SH-106

### 3.1 clean archive `c1b54d2f`：28/28

```console
$ sh test/ast/p106_str_escape.sh /tmp/rev-final/sh106/build/ct-ast
ok   ret_local / ret_temp / ret_local_var / ret_local_get / ret_view_slice
ok   bind_temp / assign_temp / ret_u16str / ret_str_slice        # 9 负例
ok   ret_local / ret_temp / bind_temp (ct check / --types reports an error)
ok   ret_literal / owner_scope / ret_param / ret_field / ret_global /
     ret_immortal_owner / allow_escape                            # 7 正例
ok   owner_scope / ret_param / allow_escape (check and --types clean)
p106_str_escape: OK
```

### 3.2 红证复现（baseline `1ea0502a`）

```console
$ git archive 1ea0502a | tar -x -C /tmp/rev-final/base1ea/src   # 同链自举 → ct-ast v0.88.0
$ sh test/ast/p106_str_escape.sh /tmp/rev-final/base1ea/build/ct-ast
FAIL p106/escape: ret_local / ret_temp / ret_local_var / ret_local_get /
     ret_view_slice / bind_temp / assign_temp / ret_u16str / ret_str_slice
     → warning missing / ct check / --types accepted            # 15 条负例红
ok   ret_literal / owner_scope / ret_param / ret_field / ret_global /
     ret_immortal_owner / allow_escape                           # 13 条正例绿
EXIT=1
```

15 条负例红、13 条正例绿，与 issue「红证」节一致。`1ea0502a` 是实现前提交且是
`HEAD` 的祖先；但 SH-106 没有独立的 `test(...) 红` 提交（夹具随 `c1b54d2f` 一起
落地），严格 T-7 形式不成立；红证内容本身已独立复现，按既有评审惯例记为
**非阻断形式项**。

### 3.3 REV 新增反例（不在原 16 夹具内）

```console
$ ct-ast build /tmp/rev-final/probes/cross_proc.ct    → exit 0；check → exit 0
# 参数视图经 relay 静默；missed() 的局部 owner 视图经 relay 转手也静默（跨过程边界）
$ ct-ast build /tmp/rev-final/probes/arr_cases.ct     → exit 0；check → exit 0
# arr[i].as_str() / r->names[0].as_str() 不误报；pick_local() 局部数组元素静默
$ ct-ast build /tmp/rev-final/probes/u16_paths.ct
u16_paths.ct:6:12: warning: borrowed 'U16Str' view escapes 'return': the local
  'U16String' owner's lifetime ends with this frame; ...            exit 0
# fresh() 的 to_utf8()（新分配）与 from_param(p) 静默
$ ct-ast build /tmp/rev-final/probes/owner_scope2.ct  → exit 0；check → exit 0
```

结论：跨过程转手不误报（参数 relay 静默）；局部 owner 经调用转手是已声明的漏报边界；
`arr[i].as_str()` 的参数/字段/数组元素形态不误报；U16 负例报 `U16Str`、`to_utf8`
新分配不报；owner 在作用域的安全形态 0 误报。局部数组元素返回的静默与诚实清单
「按容器存储处理」一致，记为残余风险而非本 issue 漏项。

### 3.4 严重度 / allow-escape / JSON

```console
$ ct-ast build ret_local.ct -o ...        # warning, exit 0
ret_local.ct:5:12: warning: borrowed 'Str' view escapes 'return': ...
$ ct-ast check ret_local.ct               # error, exit 1
ret_local.ct:5:12: error: borrowed 'Str' view escapes 'return': ...
$ ct-ast check --types ret_local.ct       # error, exit 1（同上）
$ ct-ast build ret_local.ct --diagnostics=json
{"warnings":[{"type":"str_escape","file":"...","line":5,"col":12,"message":"borrowed 'Str' view escapes 'return': ..."}]}
$ ct-ast check ret_local.ct --diagnostics=json
{"warnings":[{"severity":"error","type":"str_escape",...}]}
```

与 E79-6 完全同口径（独立复跑 `int[]` 返回局部数组）：

```console
$ ct-ast build e79_ret_slice.ct           # warning, exit 0
e79_ret_slice.ct:5:12: warning: slice escape: 'return' hands back a view of a local array
$ ct-ast check e79_ret_slice.ct           # error, exit 1
e79_ret_slice.ct:5:12: error: slice escape: 'return' hands back a view of a local array
```

`/* ct: allow-escape */` 与返回表达式/`return` 同行时豁免（build/check 均静默）；
写在上一行不豁免（仍 warning）。`p79_places.sh` 全绿（E79-6 不变）。

### 3.5 版本、banner、断言、门禁

```console
$ for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
           selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do grep CTC_VERSION "$f"; done
#define CTC_VERSION "0.88.2"   ×5
$ grep -rl '0\.88\.2' test/cases test/modules | wc -l     → 51
$ grep -rn '0\.88\.1' --include='*.c' --include='*.ct' --include='*.h' \
      --include='*.expected.*' selfhost test              → 空
$ bash tools/check.sh g0  → g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8  → g8: OK (PN-2 version coherence; 9 legacy offsets)
$ bash tools/check.sh g6  → g6: OK (283 issues; open=43 verified=220 reopened=1
                            rejected=10 deferred=8 superseded=1)
$ python3 test/docs/check-docs.py
check-docs: OK (2601 relative links in 401 files, v0.88.2, 11 hard gates, ...)
$ bash selfhost/check-warnings.sh   → check-warnings: 502 ok, 0 failed
$ bash selfhost/check-sanitizers.sh → check-sanitizers: OK (588 checks, no sanitizer report)
$ sh test/ast/p79_places.sh ...     → p79_places: OK（E79-6 不变）
$ p80_docs / p80_retain / p81_box / p82_docs → 全部 OK
```

`p80/p81/p82` 的版本断言已随本提交从 `0.88.1` 改为 `0.88.2`（三条脚本，
`grep` 复核无残留旧值）。`check-all` 见 §3.6。

### 3.6 提交范围与 PKG-23 冲突

`c1b54d2f` 的路径集合（88 文件）= SH-106 源码 3 文件 + 16 个 p106 夹具 + 51 个
golden/ABI banner + 五处版本/README/AGENTS/test README + spec/guide/phase-log/
p88_metrics + p80/p81/p82 版本断言；没有别的任务的文件。与 PKG-23 的版本冲突已
解决：PKG-23 占 v0.88.1，SH-106 顺延 v0.88.2；五处、51 banner、p80/p81/p82、
README/docs/AGENTS/test README 全部 0.88.2，代码/golden 无 0.88.1 残留。
`c1b54d2f` 未包含 `selfhost/check-ast.sh` 的 SH-106 钩子——钩子在 `00eb6df1`，
这正是 §2.4 的 T-4 缺陷；重写历史时把该 11 行移入 `c1b54d2f` 即同时修复两 issue
的回滚独立性。

```console
$ TMPDIR=... CT_DIST=/tmp/rev-final/absent.tar.gz bash selfhost/check-all.sh
  FAIL  v0-PH-77-S5 external: ok   ct get std succeeds with a clean HOME and no index
...
== summary: 1576 passed, 1 failed, 5 skipped ==      # check-ast
FAIL: 8) AST compiler (...) (exit 1)
check-all: FAIL (at least one hard gate failed)
```

本环境 `check-all` 为 **10/11**：唯一红是 v0-PH-77-S5 external（第二次 `ct get
ct/std` 的 clone 在 180s 超时；且官方 index 的第一条 `std` 行已变成 `0.20.0`
— `std 0.20.0 ct ... v0.20.0 sha256:60d2e7dd…`，探针 `head -1` 取首行后与内置
pin 0.19.0 比较，E77-8 因此红；index 里仍有 0.19.0 行，属探针取行口径的陈旧，
不是 SH-106/PKG-23）。同一份 check-ast 里 `PKG-23 git diagnostics` 与
`SH-106 Str view escape` 都是 ok；其余 10 门（g0/g8 前置、test/run 156、
goldens、archive、m2a、tour、grammar 179、pkg 153、warnings 502/0、semantics、
check-docs）全绿。DEV 声称的 11/11 在本次运行因外部 index 漂移/网络未复现，
属环境与既有探针问题，不改变 SH-106 的判定；`CT_DIST` 指向不存在路径是为跳过
工作树里陈旧的 `dist/` 产物（DEV 的收口命令同样如此）。

### 3.7 判定

功能、反例、严重度、豁免、版本、门禁、提交范围均通过；置 `verified`。T-7 缺独立红
提交、以及钩子在 `00eb6df1` 的提交放置问题，见 §2.4/§4，不改变功能判定。

## 4 最小修法（不改实现，只重写本地历史）

`00eb6df1` 与 `c1b54d2f` 都是未 push 的本地提交，最小修法是一次交互 rebase：

1. `00eb6df1`：删除 `selfhost/check-ast.sh` 中 SH-106 的 11 行块（注释 +
   `if sh test/ast/p106_str_escape.sh ...`），只留 PKG-23 块；
2. `c1b54d2f`：补回同一 11 行块（它本来就该属于 SH-106）；
3. 如需严格 T-7，再把 `c1b54d2f` 拆成 `test(ct-ast): SH-106 红`（探针 + 该钩子）与
   `fix(ct-ast): SH-106 ...` 两个提交，红提交只含探针/夹具/钩子；
4. 重写后重跑 `git archive <new-00eb6df1>` + `check-ast`（应不再有 SH-106 FAIL）与
   `git archive <new-c1b54d2f>` + `p106`（28/28）；因 sha 变化，需按新 sha 重新
   记录本复核与 PKG-23 的红/绿证。

只加“补提交”无法修复 `00eb6df1` 这个历史归档的独立性（补提交只影响 HEAD），
所以这里必须重写本地历史；`00eb6df1`/`c1b54d2f` 均未 push/tag，无外部影响。

## 5 未覆盖声明

PKG-23 认证分支仍用 git 测试替身（未起真实 401），proxy/TLS 按 git 原文匹配；
未 pin 的第三方 range 失败仍报 `no tag ... satisfies`，不在本 issue 路径内。
SH-106 不做跨过程分析（非目标）；局部数组元素视图返回按容器存储静默，与诚实清单
一致；`U16String.to_utf8()` 的新分配边界未做跨方法分析。`--refresh` 的 `.`/`..`
目标依赖 `rm` 兜底而非代码强制；当前未观察到越界删除，但建议按 §2.5 加校验
（另立 hardening，不阻塞本 issue 的功能判定）。
