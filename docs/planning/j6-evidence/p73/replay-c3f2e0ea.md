# P-7.3 在 HEAD `c3f2e0ea` 的重放（C-4 / S5a-0）

baseline: c3f2e0ea

> 日期：2026-11-20
> 执行：DEV（证据/原型，隔离副本 `/tmp/p73-replay`）
> 目的：verdict.md §4.2 的 C-4 —— 在 HEAD 上重放 P-7.3 最小切片，`test/p73/run.sh` 必须 16/16。
> 主仓未改 `selfhost/**`、`lib/std/**`、`test/**`；本文件是主仓唯一新增。

## 0. 结论

| 项 | 结果 |
| --- | --- |
| 3 处冲突 | 人工解决，规则见 §3；两侧特性都保留 |
| `bash test/p73/run.sh` | **16 passed, 0 failed**，退出码 **0** |
| 原始输出 | §4（完整粘贴） |
| 未覆盖项 | §6；C-4 只证明 P-7.3 最小切片在 HEAD 可重放，不证明 P-7.4 全量 |

## 1. 环境与基线

```console
$ uname -m
arm64
$ cc --version | head -1
Apple clang version 21.0.0 (clang-2100.4.1.1)
$ sw_vers
ProductName:            macOS
ProductVersion:         27.2.1
BuildVersion:           26B131

$ git -C /Users/samxx/dsh-ws/ct-lang rev-parse HEAD
c3f2e0ea03913d0afe62f9e0ef7e218a9eb92434
$ git -C /tmp/p73-replay log --oneline -2
a342c33e P-7.3 prototype rebased onto c3f2e0ea (3 conflicts resolved)
c3f2e0ea docs(ph80): D-013 施工入口修订（USER 签收）
```

`c3f2e0ea` 与 verdict §4 写的 `6665f01a` 只差三个文档提交（battle、D-013、卡/计划），
`git diff --stat 6665f01a..c3f2e0ea -- selfhost lib/std test` 为空，因此冲突面相同。

## 2. 命令

```console
$ rm -rf /tmp/p73-replay
$ git clone -q --no-checkout /Users/samxx/dsh-ws/ct-lang /tmp/p73-replay
$ cd /tmp/p73-replay
$ git checkout -q c3f2e0ea
$ git config user.email dev@local && git config user.name dev
$ git checkout -q -b prototype

# 2.1 夹具：p73-rebased-*.patch 只含 8 个源码文件（selfhost/** + lib/std/Str.h.ct），
#     不含 test/p73/**；夹具从原 p73.patch 取（全是新文件，无冲突）。
$ git apply --include='test/p73/*' --include='.gitignore' \
      /Users/samxx/dsh-ws/ct-lang/docs/planning/j6-evidence/p73/p73.patch

# 2.2 源码：在 HEAD 上做 3-way，得到 3 个冲突
$ git apply --3way \
      /Users/samxx/dsh-ws/ct-lang/docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch

# 2.3 人工解决 3 个冲突后提交（见 §3）
$ git add -A
$ git commit -qm 'P-7.3 prototype rebased onto c3f2e0ea (3 conflicts resolved)'

# 2.4 从零构建 + 跑 P-7.3 夹具
$ bash test/p73/run.sh
$ echo $?
0
```

> 为什么用 clone 而不是 `git archive`：`git apply --3way` 需要基线 blob（`5736f0d5`）在对象库里。
> 先 `git archive` + `git init` 时只得到失败输出 `repository lacks the necessary blob to perform
> 3-way merge`，随后退回直接应用并报同样的 3 个 `patch does not apply`。clone 保留完整历史，
> 3-way 才能把冲突摊开成 `<<<<<<<` / `>>>>>>>` 供人工解决。

### 2.1 应用原始输出

```console
$ git apply --3way docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch
Applied patch to 'lib/std/Str.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/backend/emit/Emitter.h.ct' with conflicts.
Applied patch to 'selfhost/ct-ast/frontend/module/Module.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/frontend/parse/Expr.h.ct' with conflicts.
Applied patch to 'selfhost/ct-ast/frontend/parse/Parser.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/frontend/parse/Stmt.h.ct' with conflicts.
Applied patch to 'selfhost/ct-ast/frontend/type/TypeCheck.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/tool/driver/Driver.h.ct' cleanly.
$ git status --porcelain | head
 M .gitignore
M  lib/std/Str.h.ct
UU selfhost/ct-ast/backend/emit/Emitter.h.ct
M  selfhost/ct-ast/frontend/module/Module.h.ct
UU selfhost/ct-ast/frontend/parse/Expr.h.ct
M  selfhost/ct-ast/frontend/parse/Parser.h.ct
UU selfhost/ct-ast/frontend/parse/Stmt.h.ct
M  selfhost/ct-ast/frontend/type/TypeCheck.h.ct
M  selfhost/ct-ast/tool/driver/Driver.h.ct
?? test/p73/
```

## 3. 三处冲突与解决

冲突都是「HEAD 的 PH-79 切片/切片逃逸改动」与「P-7.3 字面量绑定」落在同一位置；两侧语义正交，
解决规则一律是**两侧都保留，只决定顺序**。

| # | 文件 | ours（HEAD） | theirs（P-7.3 patch） | 解决 |
| --- | --- | --- | --- | --- |
| 1 | `selfhost/ct-ast/backend/emit/Emitter.h.ct:1412` | P-7.2 的 `g_slice_used` 与 `emit_slice_helpers` 前置声明 | `emit_string_literals` 的完整定义 | 先保留 P-7.2 两个声明，再放 `emit_string_literals`；删除中间与尾部冲突标记 |
| 2 | `selfhost/ct-ast/frontend/parse/Expr.h.ct:318` | `ExprTypes` 里的 `slice_view_from_array`（PH-79/SH-100） | `lit_coerce`（P-7.3） | 两个 trait 方法都保留：`slice_view_from_array` 在前，`lit_coerce` 在后 |
| 3 | `selfhost/ct-ast/frontend/parse/Stmt.h.ct:2304` | 切片逃逸 lint + `slice_view_from_array` 调用 | `lit_coerce` 调用 + 「Phase 32 S5」注释 | 顺序改为 ① `lit_coerce` → ② 切片逃逸 lint → ③ `slice_view_from_array` → ④ Phase 32 注释；随后接原有的 Phase 43 类型判定 |

解决后自检：

```console
$ grep -n '<<<<<<<\|=======\|>>>>>>>' \
    selfhost/ct-ast/backend/emit/Emitter.h.ct \
    selfhost/ct-ast/frontend/parse/Expr.h.ct \
    selfhost/ct-ast/frontend/parse/Stmt.h.ct
# 无输出；退出码 1
$ git diff --stat c3f2e0ea prototype | tail -1
 29 files changed, 1006 insertions(+), 111 deletions(-)
```

第 3 处顺序的理由：`lit_coerce` 只改写裸字面量的期望类型，`slice_view_from_array` 只改写数组值；
三者互斥（`N_STR` vs `N_VAR`/`N_SLICE_RANGE`），顺序不影响语义，但把 `lit_coerce` 放在最前与
patch 原意一致，切片 lint 仍能在转换前看到原始节点。

## 4. 原始输出（`bash test/p73/run.sh`）

```console
$ bash test/p73/run.sh
== toolchain ==
PASS bootstrap chain L0 -> L1 -> L2 -> ct-ast
== positives ==
PASS abi (compile + warning-free cc + expected stdout)
PASS methods (compile + warning-free cc + expected stdout)
PASS drop (compile + warning-free cc + expected stdout)
PASS cstr (compile + warning-free cc + expected stdout)
PASS vec (compile + warning-free cc + expected stdout)
PASS drop_ptr (compile + warning-free cc + expected stdout)
== build mode ==
PASS build mode (separate Str.c/drop.c, warning-free, same stdout)
== ASan drop ==
PASS drop under ASan (no UAF/overflow; live counter reaches 0)
== ASan sensitivity (expected failure) ==
PASS ASan sensitivity (deliberate post-release read -> heap-use-after-free)
== negatives ==
PASS neg_immutable (rejected: read-only subscript)
PASS neg_data_write (rejected: read-only subscript)
PASS neg_data_assign (rejected: assignment target is not assignable)
PASS neg_data_cstr (rejected: expected 'const char *', got 'struct Str')
PASS neg_utf16 (rejected: UTF-16 string literal is not implicit)
PASS neg_ptr_write (rejected: String/Str is immutable)

summary: 16 passed, 0 failed
$ echo $?
0
```

`run.sh` 自己从 L0 种子构建 L0→L1→L2→ct-ast（`test/p73/.build`），不读主仓已有二进制；
`CT_STD_DIR` 指向副本的 `lib/std`。

## 5. 可机检字段

```console
$ grep -n '^baseline: ' docs/planning/j6-evidence/p73/replay-c3f2e0ea.md
1:baseline: c3f2e0ea
$ grep -n '^summary: 16 passed, 0 failed' docs/planning/j6-evidence/p73/replay-c3f2e0ea.md
# 命中的是 §4 原始输出里的那一行
$ git merge-base --is-ancestor c3f2e0ea HEAD; echo $?
0
```

## 6. 未覆盖项（不得读成「P-7.4 通过」）

1. **只重放 P-7.3 最小切片**：旧 owning `Str` 仍被替换，`std::str::Str` 限定名并存未证（C-5 `coexist.md` 另证）；
2. **自动 retain 未做**：按值参数/返回/字段的自动 retain 不在 P-7.3；C-5 `asan.md` 用显式协议 + 说明；
3. **`box<String>`、`Map<...,String>`、真实 UTF-16** 不在本切片（`box` 属 PH-81；其余见 C-5）；
4. **既有测试套件不全绿**：11 个 `test/ast` + 1 个 example 消费者仍用旧 `Str`，属 P-7.4-3 迁移清单；
5. 本重放是 macOS/Apple clang 21 一次实测；`run.sh` 用 `CC` 可换编译器，但本文件只声明这次的原值；
6. 冲突解决是人工语义判断，不是 patch 作者的上游产物；解决后的树只在 `/tmp`，未 push、未打 tag。
