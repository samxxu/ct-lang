# SH-6 · ct-ast 的 16 处「上限账本在 main.ct」注释已悬空，且 main.ct 内自相矛盾

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | **Medium** |
| 锚点 | commit `4ef8b68`（2026-10-21）；`main.ct` 以工作树当前内容为准（含未提交改动） |
| 文件 | [Symbols.h.ct:11-15](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L11-L15) 等 16 处；[main.ct:47-49](../../selfhost/ct-ast/main.ct#L47-L49) vs [:58-61](../../selfhost/ct-ast/main.ct#L58-L61) |
| 状态 | ✅ 已修复（2026-10-21；验证见 [issues/README.md](../README.md) 的「Phase 12 复审」一节） |

## 现象

### 1. 账本悬空

每个单元的头注释都写：

> Macros do not cross a unit boundary, so the caps are restated here; they must stay equal to … **in main.ct**.

但事实是：

- HEAD 里 24 个上限宏挂在 `main.ct`，**在 `main.ct` 内一次都没被使用**；
- 工作树改动把它们整块删掉之后，这 16 处注释指向的文件不再持有任何上限宏。

涉及：`frontend/sym/Symbols.h.ct`、`frontend/lex/Lexer.h.ct`、`frontend/module/{Map,Module,Unit}.h.ct`、`frontend/parse/{Parser,ParseSupport,Expr,Stmt,MapBuild}.h.ct`、`frontend/type/TypeCheck.h.ct`、`backend/emit/Emit.h.ct`、`backend/mem/Memory.h.ct`、`tool/{diag/diag,cache/Cache.h,driver/driver,pkg/pkg}.ct`。

### 2. main.ct 内自相矛盾

- `main.ct:47-49`：entry file「needs nothing but the version」；
- `main.ct:58-61`：「The caps its fields need stay in this unit's MAX_* list too」。

同一文件里一段说不需要、一段说必须留。

### 3. 相关但不独立的陈旧点

- `main.ct:51-87`：连续 8 段「X now lives in Y」重构流水账；
- `main.ct:2`：头注释仍写「Phase 9: the AST compiler」，只列 9.1–9.5a；
- `runtime/arena/Arena.h.ct:12-13`：节点种类文档说在 `main.ct`，实际在 `frontend/parse/{Parser,Expr,Stmt}.h.ct`；
- `frontend/module/Unit.h.ct:7-9`：说 caps「restated here」，该文件没有任何 `#define`，全是字面量；
- 头注释文件名与真实文件名不一致：`Symbols.h.ct`→`sym.h.ct`、`Map.h.ct`→`map.h.ct`、`Unit.h.ct`→`unit.h.ct`、`Arena.h.ct`→`arena.h.ct`。

## 影响

「唯一的数值真相」这句话指向一个空文件，后续维护者改动上限时无法判断该同步哪些单元；`main.ct` 的两段注释则直接给出相反指令。

## 修复建议

1. 把 `frontend/sym/Symbols.h.ct` 定为**唯一权威清单**（它已持有全部 10 个上限），其余单元注释改为「与 `frontend/sym/Symbols.h.ct` 的 MAX_* 保持一致」；
2. 删除 `main.ct:47-49` 与 `:58-61` 中的矛盾段，合并为一句准确说明；
3. 顺带处理第 3 节的四点（流水账压缩、头注释更新到 Phase 12.1、Arena/Unit 措辞、文件名对齐）。

## 验证

- `grep -rn 'in main.ct\|main.ct keeps\|stay equal to main' selfhost/ct-ast` 无命中；
- 16 处注释的引用目标统一为 `frontend/sym/Symbols.h.ct`；
- `bash selfhost/check-all.sh` 仍 `OK (8 hard gates green)`，且无 golden 变化。
