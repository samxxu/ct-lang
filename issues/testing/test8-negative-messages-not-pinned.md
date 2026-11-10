# TEST-8 · 12 个负例只断言「有位置」，消息文本可静默漂移

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | Medium |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [selfhost/check-ast.sh:1020-1030](../../selfhost/check-ast.sh#L1020-L1030)、[test/ast/errors](../../test/ast/errors) |
| 状态 | 已修复（2026-10-31 落地；2026-11-10 复核：12 条消息仍在 check-ast.sh 的 pair 表内） |

## 现象

`test/ast/errors/*.ct` 的通用循环只要求非零退出且 stderr 匹配
`^[^:]+:[0-9]+:[0-9]+: error: `，**不断言消息文本**：

```sh
for f in test/ast/errors/*.ct; do
    …
    elif grep -Eq '^[^:]+:[0-9]+:[0-9]+: error: ' "$work/bad-$b.err"; then
        ok "$b (rejected with a positioned diagnostic)"
```

68 个夹具中 **56 个**另有 `"fixture|message"` pair 循环把文本钉死
（[:1036-1379](../../selfhost/check-ast.sh#L1036-L1379)）；剩下 **12 个**只有位置断言。
`grep` 在 `check-ast.sh` 中对这 12 个名字的命中数为 **0**：

```text
assign_target · bitops_assign_target · extern_function · map_bad_arg · map_bad_arity ·
map_bad_method · map_dup · map_unknown_arg · map_unknown_trait · missing_semi ·
undeclared_var · unknown_trait
```

## 证据

```bash
$ for n in assign_target bitops_assign_target extern_function map_bad_arg map_bad_arity \
           map_bad_method map_dup map_unknown_arg map_unknown_trait missing_semi \
           undeclared_var unknown_trait; do
      printf '%s: ' "$n"; grep -c "$n" selfhost/check-ast.sh
  done
# 全部为 0
```

## 影响

消息措辞是 ct-ast 的对外契约（`docs/language-spec.md`、`AGENTS.md` §4 都规定格式与小写风格）。
这 12 条若被改写（例如 `undeclared variable 'x'` → `unknown name 'x'`），门禁仍全绿，文档与实现
会悄悄分叉；诊断质量回归也没有任何自动信号。与 [TEST-10](test10-build-cli-errors-untested.md)
叠加后，负例覆盖的整体强度被高估（56/68 精确，其余只算「拒了」）。

## 修复建议

照现有 pair 循环扩表：把这 12 个夹具各加一条 `"<fixture>|<message>"`，消息文本**由真实二进制输出生成**，
禁止手写。若某条消息本就不稳定（含路径或计数），则在该条上注明原因并保留位置断言。

## 验证

扩表后逐条用 `ct-ast` 编对应 `.ct`，stderr 包含表中文本；`bash selfhost/check-ast.sh` 317+12 全绿；
`bash selfhost/check-all.sh` 九关全绿。

## 处理（2026-10-31）

已修复：12 条消息在 `check-ast.sh` 的 batch 37 段钉死；同一段另补了 `identifier_too_long` 的新消息。
