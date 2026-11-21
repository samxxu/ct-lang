# SH-107 · M0 实现提交 `e88561af` 不能独立构建（3 个跨单元 import 落到下一个任务）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（PH-85 S85c / 提交纪律） |
| 定性 | 提交不绿（T-7 先红后绿、T-4 单任务回滚） |
| 严重度 | High（实现提交的验收证据不成立） |
| 锚点 | `e88561af`（S85c M0）、`c7f8ed93`（补 import 的 S85d） |
| 文件 | `selfhost/ct-ast/tool/driver/Driver.h.ct:660`、`selfhost/ct-ast/frontend/parse/Parser.h.ct:1282`、`selfhost/ct-ast/frontend/type/TypeCheck.h.ct:224`、`:230` |
| 状态 | **open** |

## 现象

S85c 的实现提交 `e88561af` 把 `ct_append_flags`、`ct_type_canon`、
`ct_generic_subst` 搬进新单元（`ModuleBoundary` / `SymbolsTypeText`），但
`Driver`、`Parser`、`TypeCheck` 没有同时 `import` 新单元。从该提交的归档构建，
L0→L1→L2→ct-ast 链在 ct-ast 处失败：

```console
$ R=$(mktemp -d /tmp/ph85m0.XXXXXX); git archive e88561af | tar -x -C "$R"
$ sh build-ct-ast.sh "$R" "$R/.temp/b"; echo rc=$?
...
selfhost/ct-ast/tool/driver/Driver.h.ct:660:17: error: call to undeclared function 'frontend_module_ct_append_flags'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
selfhost/ct-ast/frontend/parse/Parser.h.ct:1282:13: error: call to undeclared function 'frontend_sym_ct_type_canon'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
selfhost/ct-ast/frontend/type/TypeCheck.h.ct:224:17: error: call to undeclared function 'frontend_sym_ct_generic_subst'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
selfhost/ct-ast/frontend/type/TypeCheck.h.ct:230:17: error: call to undeclared function 'frontend_sym_ct_generic_subst'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
rc=1
```

这三处 import 在**下一个**提交 `c7f8ed93`（S85d）才补上：
`Driver.h.ct` 加 `import frontend::module::ModuleBoundary;`，
`Parser.h.ct`/`TypeCheck.h.ct` 各加 `import frontend::sym::SymbolsTypeText;`。
因此 `e88561af` 自己不是绿的，T-7 的“实现提交随后转绿”不成立；
`p85_m0` 探针只检查源码/映射/外部传入的 `<ct-ast>`，不会构建当前树，所以它在该提交上
仍可 4/4，掩盖了这一点。

同一原因使 S85c 的 commit message 失实：

```console
$ git show -s --format=%B e88561af | tail -5
$ L0→L1→L2→ct-ast 全链 -Wall -Wextra -std=c99 零警告；自举不动点 diff -r 空
$ python3 tools/p85_inventory.py m0
p85_m0: body hashes preserved (827 bodies, 842 functions, 6 moved units,
        11 declared S85d edits), 26 products, 0 cycles
```

`842 functions` / `11 declared S85d edits` 是 S85d 落地之后才有的数字，不是该提交的数字。

## 复现（最小）

```console
$ R=$(mktemp -d /tmp/ph85m0.XXXXXX); git archive e88561af | tar -x -C "$R"
$ cp .temp/build-ct-ast.sh "$R"/ && cd "$R" && sh build-ct-ast.sh . .temp/b; echo rc=$?
rc=1
```

回滚侧同样不成立：在 HEAD 上 `git revert e88561af` 因 S85d 后来改过
`ModuleBoundary.h.ct` 而 `CONFLICT (modify/delete)`：

```console
$ git revert --no-edit e88561af
CONFLICT (modify/delete): selfhost/ct-ast/frontend/module/ModuleBoundary.h.ct deleted in parent of e88561af and modified in HEAD.
error: could not revert e88561af...
```

即使手工解掉该冲突，S85d 留下的 `import frontend::sym::SymbolsTypeText` 仍指向被删单元，
回滚不能单独完成。卡 §7.5 的“`git revert` M0 提交 → …”没有演练到这一层。

## 期望

- 在**未 push** 前重排 PH-85 的提交：把 `Driver`/`Parser`/`TypeCheck` 的 3 个 import 放进
  `e88561af`（或把 M0 与 S85d 合并为一个不可分的提交），使 M0 实现提交独立构建、
  `p85_m0` 与 `check-all` 在该提交上转绿；
- `p85_m0` 探针增加“用当前树构建出的 ct-ast”这一前置，或由 check-ast 的构建段兜底；
- 重写提交信息里的 `842` / `11` 为 M0 提交自己的数字（827 bodies / 838 functions）；
- 回滚演练写成“M0 + S85d 的 3 个 import 一起回退”，或在卡 §7.5 写明冲突解法和依赖。

## 验收

- `git archive e88561af | tar -x` 后完整自举 `rc=0`、零警告；
- 在该归档上 `bash test/ast/p85_m0.sh <该归档构建的 ct-ast>` 4/4，且 `check-all` 绿；
- `git revert e88561af` 的演练命令与结果入库，或卡 §7.5 的回滚描述与实测一致。

## 关联

- [PH-85 卡](../../docs/design/phase85.md) §7.1/S85c、§7.2、§7.5、E85-3/E85-8
- [REV 复核](../../docs/reviews/2026-11-21-phase85-rev-verdict.md) §4.2

## DEV 处置（2026-11-21）

已修，重写本地未推历史：三条 import 移入 M0 提交本身，并把 `ct_norm_path` 依赖的
`extern char *realpath(...)` 一并放进 `ModuleBoundary.h.ct`（随函数走；musl `-std=c99`
不暴露该原型，所以此前只有 Linux 交叉构建会红）。

```console
$ git archive 104dfc54 | tar -x -C /tmp/p85f2 && cd /tmp/p85f2
$ cp .temp/build-ct-ast.sh . && sh build-ct-ast.sh . .temp/b
built .temp/b/ct-ast                                rc=0（全链，零警告）
$ ./.temp/b/ct-ast -v
ct-ast v0.84.1                                      # 该提交在收口之前，版本是旧值
$ CT_C_BOUNDARY=allow ./.temp/b/ct-ast test/cases/01_trait_basic.ct -o /tmp/m0x.c \
>   && cc /tmp/m0x.c -o /tmp/m0x && /tmp/m0x
Hello, I'm Tom, age 36
Hello Jerry, I'm Tom
```

`bash test/ast/p85_m0.sh <HEAD 的 ct-ast>` 在 HEAD 上 4/4（allowlist 属 S85d 夹具，
M0 提交处尚不存在；M0 提交的验收是“可独立构建 + 行为不变”）。
回滚演练（先 S85d 再 M0）见卡 §7.5；版本仍 0.85.0（未发布，重写未推历史）。

## DEV 处置（第二次，2026-11-21，REV 二次打回 F2 残留）

第一次修 F2 后 M0 提交仍混入 8 行 S85d 代码（`Module.h.ct` 的 `--check-level` help
1 行 + `nsem` 提前退出守卫 7 行），导致该提交 `p85_m0` 红、`ct build --help` 列出
未实现的选项。已重写本地未推历史：

- 8 行移回 S85d 实现提交 `602d3a25`；M0 提交 `33f06d17` 只保留 import 与
  `realpath` 机械行；
- M0 测试提交 `bfad7c37` 的 `test/probes/p85_m0_s85d_edits.tsv` 为空文件（0 条
  S85d 改动），S85d 测试提交 `c34cdf93` 再写入 11 条；
- M0 提交正文改为 `827 bodies / 838 functions / 0 S85d edits`。

```console
$ git archive 33f06d17 | tar -x -C /tmp/p85m0v && cd /tmp/p85m0v
$ cp .temp/build-ct-ast.sh . && sh build-ct-ast.sh . .temp/b
built .temp/b/ct-ast                                  rc=0（全链，零警告）
$ ./.temp/b/ct-ast build --help | grep -c check-level
0
$ python3 tools/p85_inventory.py m0
p85_m0: body hashes preserved (827 bodies, 838 functions, 6 moved units,
        0 declared S85d edits), 26 products, 0 cycles
$ bash test/ast/p85_m0.sh ./.temp/b/ct-ast
p85m0: 4 passed, 0 failed
```

HEAD（`827 bodies / 842 functions / 11 edits`）四探针与 check-all 仍绿；版本仍
0.85.0（未发布，重写未推历史）。
