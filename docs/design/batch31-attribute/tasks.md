# 任务：GNU `__attribute__((…))`（第三十一批）

依据：`docs/design/batch31-attribute/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 存储与捕获

- `runtime/arena/Arena.h.ct`：`Node.attr`（`-1` = 无，否则字符串池偏移）。
- `frontend/sym/Symbols.h.ct`：`Fn.attr`。
- `frontend/parse/Parser.h.ct`：`ParseOps::attr_pool`（token 原文、连续组、数字用 `toknum`）。
- `frontend/parse/ParseSupport.h.ct`：`add_func` 新建行清 `attr`；形参属性并入 `pdim`。

## [x] T2 六个调用点

- `parse_func`：函数原型 / 定义（参数表之后）、全局变量（声明符之后、`=` 之前）。
- `parse_params`：形参名/维度之后。
- `parse_field_def`：字段维度之后（位域宽度之后发射）。
- `parse_typedef`：别名之后；记录类型分支与 `parse_record_def` 的重复位置报错。
- `parse_record_def` / `parse_enum_def`：`}` 之后。

## [x] T3 发射

- `Emit.h.ct`：`emit_proto`、`N_FUNC`（`)` 后）、形参、`N_FIELDS`/`N_FIELD`（含位域）、
  全局、`N_TYPEDEF`、`N_STRUCT`/`N_UNION`/`N_ENUM` 尾部；typedef 记录统一放别名之前。

## [x] T4 fixture、负例、关卡与文档

- `test/ast/54_attribute`、`test/ast/errors/{attribute_unterminated,attribute_duplicate}.ct`。
- `check-ast.sh`：头注释 + batch 31 的精确消息断言。
- `docs/language-spec.md`：新增 §4.36（中英对称）；顶部「C 形式覆盖」不再列未实现项；
  §4.23 / §4.26 的「范围外」改为「无」。
- `docs/roadmap.md`：Post-Phase-12 补记第二十九 / 三十 / 三十一批（中英）。
- README 中英两处能力说明同步。
- 提交拆分：`feat(codegen): accept GNU __attribute__((…))`、
  `docs(spec): record __attribute__ and the last C-form gap`。不 bump 版本。
