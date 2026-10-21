# SH-5 · ct-ast 中存在 27 个定义后从未使用的宏

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | **Medium** |
| 锚点 | commit `4ef8b68`（2026-10-21）；`main.ct` 以工作树当前内容为准 |
| 文件 | [Parser.h.ct:33-42](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L33-L42)、[Emit.h.ct](../../selfhost/ct-ast/backend/emit/Emit.h.ct)、[Memory.h.ct:21](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L21)、[pkg.ct:20](../../selfhost/ct-ast/tool/pkg/pkg.ct#L20) |
| 状态 | ✅ 已修复（2026-10-21；验证见 [issues/README.md](../README.md) 的「Phase 12 复审」一节） |

## 现象

宏不跨翻译单元，所以每个单元各自 `#define` 自己用到的上限与节点种类。但一批宏定义后在该单元内**一次都没出现**：

| 文件 | 未使用符号 |
| --- | --- |
| `frontend/parse/Parser.h.ct` | `N_ARROW` `N_ASSIGN` `N_BLOCK` `N_BREAK` `N_CONT` `N_DECL` `N_DECLS` `N_DELETE` `N_DEREF` `N_EXPR` `N_FOR` `N_IF` `N_INDEX` `N_MEMBER` `N_POST` `N_RET` `N_VAR` `N_WHILE`（18 个）、`MAX_MAPS` |
| `backend/emit/Emit.h.ct` | `N_PROG` `N_PARAM` `N_METHOD` `N_TRAIT` `B_ADD` `U_NOT` `P_DEC` |
| `backend/mem/Memory.h.ct` | `MAX_SCOPE`、`N_RET` |
| `tool/pkg/pkg.ct` | `MAX_PATH` |

共 27 个。该单元实际使用的 11 个节点种类是 `N_FIELD` `N_FUNC` `N_GLOBAL` `N_IMPL` `N_METHOD` `N_PARAM` `N_PP` `N_PROG` `N_RAW` `N_STRUCT` `N_TYPEDEF`。

## 复现

```bash
for f in $(find selfhost/ct-ast -name '*.ct'); do
  for n in $(grep -o '^#define [A-Z_][A-Z_0-9]*' "$f" | awk '{print $2}'); do
    c=$(grep -c -w "$n" "$f"); [ "$c" -le 1 ] && echo "UNUSED $f $n"
  done
done
```

## 影响

- 每个单元抄一份全量节点种类，使「新增节点种类」需要在多处同步（见 SH-6 的账本问题）；
- 读者无法从宏块判断该单元究竟消费哪些种类，实际依赖要靠通读代码才能确认。

## 修复建议

只保留本单元出现的宏；删除前逐个确认 `grep -c -w <NAME> <file>` 为 1。删除属纯代码整理，**不得移动任何 golden**。

## 验证

- 上述脚本输出为空；
- `bash selfhost/check-all.sh` → `check-all: OK (8 hard gates green)`；
- `git status` 不出现 `*.expected.*` 变化。
