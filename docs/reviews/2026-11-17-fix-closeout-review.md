# 2026-11-17 修复批次收口复核包（SH-86 / SH-87 / SH-88 / TEST-19）

| 项 | 值 |
| --- | --- |
| 性质 | 复核包（给 REV）；**不写 `verified`**，状态词归 REV（5.4） |
| 范围 | `v0.62.1`（SH-86）、`v0.63.1`（SH-88）、`v0.63.2`（SH-87）、TEST-19 与其 lint |
| 基线 | `cbff2209`（v0.63.2 收口）+ `447cb0dd`（lint） |
| 复核者 | REV（单会话 deviation 下仍按 5.4 分权：DEV 只写在处置段） |

## 1 复核前置：构建一次 ct-ast

```bash
cd /path/to/ct-lang
W=/tmp/review; mkdir -p "$W"/{l2src,astsrc}
cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o "$W/ctc"
"$W/ctc" selfhost/l1/ctc.ct -o "$W/l1.c"
cc -Wall -Wextra -std=c99 "$W/l1.c" -o "$W/l1"
"$W/l1" build selfhost/l2/driver.ct -o "$W/l2src"
cc -Wall -Wextra -std=c99 "$W/l2src"/*.c -o "$W/l2"
"$W/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$W/astsrc"
cc -Wall -Wextra -std=c99 "$W/astsrc"/*.c -o "$W/ct-ast"
"$W/ct-ast" --version    # 期望 ct-ast v0.63.2
```

## 2 逐条复核

| 条目 | 应得结论 | 命令 | 期望输出（本次实测） |
| --- | --- | --- | --- |
| SH-86 | 数组/const 的 vptr 静态写入、无 constructor、多维硬错 | `"$W/ct-ast" test/ast/287_trait_array_vptr_init/prog.ct -o /tmp/r287.c && cc -std=c99 -Wall -Wextra -c /tmp/r287.c && grep -c 'constructor' /tmp/r287.c` | `cc` 退 0；`grep` 计数 `0` |
| SH-86 | 多维 trait 数组在 `ct` 阶段硬错 | `"$W/ct-ast" test/ast/errors/trait_array_multidim.ct -o /tmp/r.c; echo $?` | 退 1，stderr 含 `a multi-dimensional array cannot hold trait-carrying values` |
| SH-87 | 层函数直调拉 `Str`、`struct Struct` 不拉、>262143 B 不截断 | `bash test/ast/p64_on_demand.sh "$W/ct-ast"` | `OK p64ond` |
| SH-88 | 20 位字面量不触发 UBSAN | `CC=gcc bash selfhost/check-sanitizers.sh` | `check-sanitizers: OK (580 checks, no sanitizer report)`（约 10 分钟） |
| TEST-19 | x86-64 与 arm64 输出一致 | `bash test/ast/check_eval_order.py` | `eval-order: 1265 sources, 0 order-dependent print calls` |
| 全量 | 11 道硬门禁 | `bash selfhost/check-all.sh` | `check-all: OK (11 hard gates green)`；`check-ast` 1463/0 |

x86-64 对照（TEST-19 的正例；需要 podman 与 amd64 模拟）：

```bash
mkdir -p .temp/r241
CT_STD_DIR="$PWD/lib/std" "$W/ct-ast" test/ast/241_map_str_key/prog.ct -o .temp/r241/241.c
podman run --rm --arch amd64 -v "$PWD/.temp/r241":/w docker.io/library/gcc:13 \
  bash -c 'cd /w && gcc -std=c99 241.c -o a && ./a > out.txt'
diff -u test/ast/241_map_str_key/prog.expected.out .temp/r241/out.txt   # 期望无差异
```

只挂 `$PWD` 的子目录：podman 在 macOS 上不共享 `/tmp`。

## 3 证据索引（提交）

| 条目 | test 红提交 | 实现提交 | 版本 |
| --- | --- | --- | --- |
| SH-86 | `566f8e1b` | `b6ca8396` | v0.62.1（tag 已推） |
| SH-88 | —（`check-sanitizers` 的红即负例，见提交正文） | `c25e2b76` | v0.63.1（tag 已推） |
| SH-87 | `47f7c339` | `8a7069b7` | v0.63.2（tag 已推） |
| TEST-19 | —（CI 日志即红证） | `75fd5ff7` + lint `447cb0dd` | 不占版本（`test-fix`） |

CI：`ci` 在 `cbff2209` 上三 job 全绿（`ubuntu-gcc` / `ubuntu-clang-smoke` / `macos-clang`）；
`nightly` 手动 dispatch 后 `sanitizers` 与 `fuzz` 全绿。

## 4 未覆盖声明（8.2）

- **红证签名**：四个条目的红证均由 DEV 自签，无独立 VERIFY 签字（`deviation: single-session-workflow`）；
  本包只提供可重跑命令，签字仍由 REV 完成。
- **平台**：`check-all` 在 macOS（Apple clang 21）与 podman Ubuntu 24.04（gcc 13.3、clang 18.1）跑过；
  GitHub 上 `macos-clang` 为 CI 绿，但本机未复跑该 runner 的 Xcode 版本。
- **x86-64**：只在 TEST-19 的单个夹具上用 `podman --arch amd64` 验证；其余门禁未在 x86 上重跑。
- **packages**：`host` / `target-aarch64` 两个 job 仍 `if: false`（等外部包 0.1.0），不在本包范围。
- **硬件 pilot**：REQ-HW-020/021 未做，需真实板卡与厂商工具链。

## 5 结论与下一步

1. REV 按第 2 节逐条重跑后，决定是否把 SH-86 / SH-87 / SH-88 / TEST-19 的状态写成 `verified`；
   本包不改任何 `status` 字段。
2. 若有条目复核不过，按 5.4 由 REV 写 `reopened` 并附失败复现；DEV 按 V-3 处置，不重复 +PATCH。
3. 下一批工作建议：`packages.yml` 的 0.1.0 解封（外部包仓）、硬件 pilot 的 H0 冻结。
