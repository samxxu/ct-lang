# 第十五批特性：浮点字面量（2026-10-30）

> 锚点：`f6a21db`（第十四批收口），工作树干净。
> 本规格只做**浮点字面量**的词法与发射：`float` / `double` / `long double` 作为类型词早就可用，
> 但 `1.5` 这样的值写不出来。

## 1. 实测现状

- `d = 1.5;` 报 `expected a field or method name`：词法器没有小数点扫描，
  `1.5` 被切成 `1` `.` `5`，`.` 被当成成员访问。
- 数字 token 只保留 `toknum`（`long`），发射时按 `%ld` 十进制重印（`0x1F` → `31`、
  `0755` → `493`）。浮点值既放不进 `long`，`f` / `L` 后缀也会丢。
- `sizeof` / `const_ok` / 类型推断都只认整数节点。

## 2. 决策

- **D-1 词法**：数字分支里出现小数点或指数就按浮点扫描——`<digits> '.' <digits>?`、
  可选 `<e|E> [+-]? <digits>`、可选后缀 `f` / `F` / `l` / `L`；另加 `.5` 这种以点开头的
  形式（`...` 已在前面单独成词，不冲突）。浮点 token 把**原文**存进 `toktext` 并置
  `tokfloat = 1`。
- **D-2 整数不受影响**：`1...5` 里的小数点判定要求下一个字符不是 `.`，因此三连点仍是
  范围 / 变参记号，整数继续走 `toknum` 的十进制、八进制、十六进制读取与十进制发射。
- **D-3 节点 54 `N_FNUM`**：`text` 存字面量原文，发射时原样输出，因此 `2.25f` 保留
  `f`、`3.5L` 保留 `L`、`1e9` 保留指数写法。
- **D-4 不是整数常量**：`const_ok` 不认 `N_FNUM`，所以 `case 1.5:` 报
  `a case label must be an integer constant`（位域宽度、枚举值同理），与 C 的要求一致。
- **D-5 范围外**：十六进制浮点（`0x1p3`）不扫（文档写明）；浮点参与 `printf` 的格式串
  仍是用户自己的事。

## 3. 影响面

- 改：`frontend/lex/Lexer.h.ct`（`tokfloat` 字段、小数 / 指数 / 后缀扫描、`.5` 分支）、
  `frontend/parse/Expr.h.ct`（`N_FNUM`、数字分支按 `tokfloat` 分流）、
  `backend/emit/Emitter.h.ct`（`N_FNUM` 一支）。
- **impl 方法预算**：不新增方法（255/256）。
- 不动：`TypeCheck`（浮点字面量不参与类型推断，与整数一致）、`ctc.c` / `l1` / `l2`、
  `CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/40_float_literal`：`1.5`、`2.25f`、`3.5L`、`.5`、`1.5e3`、浮点除法、
  `(int)9.99` 截断、`%.2f` / `%.1Lf` 输出。
- 新增负例：`float_case`（`case 1.5:`）。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
