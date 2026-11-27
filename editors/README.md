# 编辑器插件已迁出

VS Code 插件（语法高亮、snippets、跳转索引）已迁至独立仓库：

- 源码与问题：<https://github.com/samxxu/ct-vscode>
- 安装：在 VS Code 扩展市场搜索 `ct-vscode`

本目录不再保留插件代码。插件版本线与 `ct` 编译器版本线独立；语言新增关键字/模式时，在 `ct-vscode` 仓同步语法并跑它自己的 `npm test`。

## 函子签名糖高亮契约（v1-PH-2 S3 / D-029）

插件侧按下面的最小契约同步，本仓不复制插件测试：

| 片段 | 高亮 | 说明 |
| --- | --- | --- |
| `(` … `)`（类型位置的函子参数表） | 类型片段 | 参数名可选，按普通参数名高亮；与表达式裸括号由上下文区分 |
| `=>`（类型位置） | 运算符 / 箭头 | 词法器本来就把它作为独立记号；闭包字面量复用同一记号 |
| `=>` 后的类型直到声明名 | 普通类型 | 展开为规范拼写 `R (*)(A, B)`；`(A,B) => R` 与 `int (*f)(int, int)` 是同一种类型 |

- **hover / 签名帮助**：显示规范拼写 `R (*)(A, B)`；参数名不进入展开。
- **错误定位**：缺 `)`/`=>`/`R`、嵌套函数指针、签名不符都由编译器给出源位置，
  编辑器只透传。
- **测试**：`ct-vscode` 的 `npm test` 增加 `=>` 与函子参数表两个 scope 断言；
  本仓 gate 6 已随插件迁出退役（见 [check-all](../selfhost/check-all.sh)）。
- 编译器侧语法与诊断的权威定义见 [language-spec §4.77](../docs/language-spec.md)
  与 [D-029](../docs/decisions/D-029.md)。

## `Str.print` / `Str.println` 高亮契约（v1-PH-2 S8c / D-030）

`print` / `println` 是 `lib/core` 的普通 `impl` 方法，**不是关键字**；语法高亮不需要
新增 scope，按既有的「标识符 + `.` + 方法名」规则即可。

| 片段 | 高亮 | 说明 |
| --- | --- | --- |
| `name.print()` / `name.println()` | 方法调用（与 `name.len()` 同档） | 接收者可以是 `Str` / `String` 的值；字面量需先绑定到 `Str` |
| `String` 上的同名调用 | 同上 | 语义是转发到 `as_str()`，高亮不区分 |

- **hover / 补全**：可选地显示一句话：「write `len` bytes to stdout, zero allocation」；
  权威定义见 [language-spec §4.78](../docs/language-spec.md)，裁定见 [D-030](../docs/decisions/D-030.md)。
- **测试**：`ct-vscode` 的 `npm test` 不需要新增断言（没有新关键字/新记号）；本仓
  gate 6 仍随插件迁出而退役。
