# TEST-14 · `check-semantics.sh` 的失败信息取错退出码，且 compile 不变性只覆盖一类

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | Low |
| 锚点 | commit `db4cae4`（2026-11-03，`v0.19.0`） |
| 文件 | [check-semantics.sh:76-81](../../selfhost/check-semantics.sh#L76-L81)、头部声明 [L8-L14](../../selfhost/check-semantics.sh#L8-L14)、compile 探针 [L171-L179](../../selfhost/check-semantics.sh#L171-L179) |
| 状态 | 已修复（本轮，2026-11-03） |

## 现象

一、`$?` 取错对象：

```bash
if "$work/ct-ast" check "$work/clean.ct" >"$work/clean.out" 2>"$work/clean.err" \
        && [ ! -s "$work/clean.out" ] && [ ! -s "$work/clean.err" ]; then
    ok "check: a clean unit exits 0 and prints nothing"
else
    bad "check: clean unit" "exit $?; $(cat "$work/clean.err")"
fi
```

`else` 里的 `$?` 是 **最后一个 `[ -s … ]`** 的状态，不是 `ct-ast` 的退出码。若 `ct-ast` 退出 1
但没有 stderr（例如只返回非零而不打印），`$?` 会是 0，失败信息写成 `exit 0`。

二、头部声明比断言宽：

```text
#   - the same unit through `ct compile` still exits 0 with `warning:` lines
#     and still writes its `.c`, so the 19.1-19.3 policy is unchanged.
```

但 `:171-179` 只拿**歧义**单元做编译对照；arity、实参类型、impl 漂移都没有「compile 仍退出 0 +
`warning:`」的镜像断言（`check-ast.sh` 里各自只有 compile 侧 grep，没有 check/compile 成对的断言）。

## 影响

低，仅影响失败诊断的可读性与门禁声明的可信度；不会漏报真实回归（`ct-ast` 非零仍会进 `else`）。

## 修复建议

1. 改成先执行再判：

   ```bash
   "$work/ct-ast" check "$work/clean.ct" >"$work/clean.out" 2>"$work/clean.err"
   rc=$?
   if [ "$rc" -eq 0 ] && [ ! -s "$work/clean.out" ] && [ ! -s "$work/clean.err" ]; then
   ```

   其余四处已使用 `rc=$?` 的写法，保持一致。
2. 要么按四类各补一条 compile 对照，要么把头部第 13 行收窄为「以歧义为例」。

## 处置

**认可，两条建议都按「补全」而非「收窄」处理。**

- 失败信息取错退出码：clean 探针改为先执行、再 `rc=$?`，`if` 里判 `$rc`，见
  [check-semantics.sh:76-82](../../selfhost/check-semantics.sh#L76-L82)。其余探针本来就是 `rc=$?` 写法。
- compile 不变性从「只拿歧义单元对照」扩到四类全覆盖：`for name in arity atype amb drift` 循环，
  每类断言 `exit 0` + `.c` 非空 + 有 `warning:` + 无 `error:`，见
  [check-semantics.sh:191-205](../../selfhost/check-semantics.sh#L191-L205)；歧义的精确措辞再单列一条。
- 头部声明随之改为 `the same units through ct compile`（不再是 `the same unit`），见
  [check-semantics.sh:13](../../selfhost/check-semantics.sh#L13)。
- 断言数从 8 增至 14（+2 条 SH-49、+3 条新增 compile 对照、+1 条歧义措辞单列）：

```
check-semantics: OK (14 assertions)
```
