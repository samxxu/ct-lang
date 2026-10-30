# 第二十一批特性：长初始化器（2026-10-30）

> 锚点：`1fefdc1`（第二十批收口），工作树干净。
> ctc.c 探针的第四个缺口：`static const char *kw[] = { … };`（第 446 行）报
> `initializer is too long`。

## 1. 实测现状

- 花括号初始化器被整段捕获进节点的 `text` 字段（160 字节），重写后的文本也写回
  同一字段；`rewrite_init_text` 的单项缓冲同样是 160 字节。
- 关键字表、消息表这类长列表因此直接报错，尽管它们是完全普通的 C。
- 节点的 `text` 只有 160 字节是全局契约（`frontend/sym/Symbols.h.ct` 列的值），
  为一个入口单独放大整个节点池并不划算。

## 2. 决策

- **D-1 存进字符串池**：捕获并重写后的文本写进 arena 的字符串池（与字符串字面量
  同一机制）。`N_RAW` 用 `aux = 1` 标记「文本在池里」，`num` 存池内偏移；
  `aux = 0` 仍然表示拼写就在 `text` 中（宏常量、函数名等 verbatim 情形）。
- **D-2 缓冲上限**：单个初始化器捕获 4 KiB，重写后 16 KiB（接口装箱会加长），
  单个列表项 4 KiB。
- **D-3 不静默截断**：超过任一上限仍报 `error: initializer is too long`。
- **D-4 三个入口一致**：文件作用域全局（`Parser`）、局部 `static` 声明（`Stmt`）、
  复合字面量（`Expr`）都用同一套池化写法，发射端只在两处读取。

## 3. 影响面

- 改：`frontend/parse/Parser.h.ct`（全局初始化器）、`frontend/parse/Stmt.h.ct`
  （局部 `static`）、`frontend/parse/Expr.h.ct`（复合字面量）、
  `frontend/type/TypeCheck.h.ct`（单项与重写缓冲）、
  `backend/emit/Emit.h.ct`（`emit_raw_init` 与 `emit_expr` 的 `N_RAW` 两支读取）。
- **impl 方法预算**：不新增方法（255/256）。
- 不动：`Symbols` / `ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/46_long_init`：29 条关键字表、10 条 struct 表、一条超过 160 字节的
  单个列表项、局部 `static` 的 20 条表；四者都要完整发射（`sizeof` 与末项取值交叉验证）。
- 本批不新增诊断。
- 探针复跑：ctc.c 的报错点从第 446 行推进到第 2474 行附近。真实缺口是相邻的
  `for (i = lpo + 1, end = rp; i < end; )` —— `for` 首句里的逗号表达式；把该行拆成
  两句后即可通过，留给第二十二批。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
