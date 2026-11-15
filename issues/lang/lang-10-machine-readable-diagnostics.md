# LANG-10 · 诊断输出缺少机器可读格式（能力需求，非缺陷）

| 项 | 值 |
| --- | --- |
| 模块 | lang（工具链 / 可调试性） |
| 类型 | **feature request**（能力缺口，不是缺陷） |
| 严重度 | Medium |
| 优先级 | **P2** —— 不挡功能，但三处消费方都在靠字符串匹配，属「门禁可能静默变绿」的系统性风险 |
| 状态 | open |
| 锚点 | `v0.53.1`（`2fd55841`） |

## 现状

诊断只有一种输出：`file:line:col: error: message`（stderr），warning 由 `-Wall` 风格开关控制。
所有消费方都只能按文本匹配：

- **门禁**：`grep 'warning:'` 统计条数，零 warning 门禁即以此判定「一条都没发」；
- **编辑器插件**：按正则抓 `file:line:col:`，改文案或改列号语义就抓不到；
- **CI**：同上，且无法区分「诊断类型」（例如把 v0.53.1 的 `string literal is too long`
  与普通语法错分开统计）。

## 风险（为什么不是小事）

1. **改文案即静默**：把 `warning:` 改成 `warning[L40-5]:`、或把通道从 stderr 改 stdout，
   门禁从「红」直接变「绿」，且没有任何地方会报错；
2. **诊断不再发出也绿**：漏发一条本该发的诊断时，文本门禁的计数只会变少，
   如果门禁只断言「不含 warning」，它同样静默通过；
3. **编辑器无法稳定取位置/级别/类型**：文案里掺了 `'`、`::`、路径含空格时正则容易截断。

## 请求

提供一个**由命令行开关启用**的机器可读格式，默认人读输出逐字节不变：

```sh
ct-ast check --diag-format=json file.ct     # 每行一个对象，便于流式处理
```

```json
{"format":1,"file":"lib/lib.h.ct","line":6,"col":5,"severity":"error","code":"L38-3","message":"defer is not allowed in a .h.ct unit"}
```

要求：

| 项 | 约定 |
| --- | --- |
| 必填字段 | `file` / `line` / `col` / `severity`（error/warning/note）/ `code` / `message` |
| 兼容约定 | `format` 是整数版本；**新增字段不升版本**，删除/改义才升；未知字段消费者必须忽略 |
| 通道 | JSON 走 stdout（或 `--diag-output=path`），人读诊断仍走 stderr |
| 默认 | 不加开关时输出与人读格式**逐字节一致**（既有 golden 不受影响） |
| 退出码 | 与所在模式现有语义一致，不因格式切换改变 |

## 受益方（三处，不是单一内部需求）

1. **门禁**：`check-warnings` 改为按 `severity` 计数，不再 grep 文案；「零 warning」变成可证伪的断言。
2. **编辑器插件**：直接映射到 LSP `/diagnostics` 的字段，无需正则。
3. **CI**：可按 `code` 分组统计、做趋势、按诊断类型设置阈值。

## 临时做法（待本能力落地后替换）

ct-sse 侧的门禁目前用 `grep 'warning:'` 判零 warning——等于把「文案是契约」当成了事实。
本条落地后应替换为读取 JSON 的 `severity` 字段；在那之前该 grep 是已知的脆弱点，
文案变更时必须同步改门禁（写在 ct-sse 的门禁脚本注释里）。

## 验收判据（双向）

| # | 判据 | 命令 |
| --- | --- | --- |
| D1 | 同一批负例下 JSON 诊断条数 == 人读诊断条数 | 对 `test/ast/errors/**` 全量比对 |
| D2 | 每条都有稳定的 `code`，同一诊断在不同文件下 `code` 相同 | 抽样 10 条手工核对 |
| D3 | 不加开关时产物逐字节不变 | `check-goldens` 全绿 |
| D4 | 故意把某条诊断文案改掉，门禁仍能红（证明不再依赖文案） | 临时改文案跑一次 |

## 范围外

- 不做 LSP server；
- 不做诊断国际化；
- 不改现有诊断的文案与语义（只加通道）。

## 2026-11-15 复核：能力已部分落地，拆成三块

HEAD `v0.53.1` 重建 `ct-ast` 实测：

| 面 | 实测 | 现状判定 |
| --- | --- | --- |
| 警告通道的 JSON | `ct check --types --diagnostics=json` 输出 `{"warnings":[{"severity":"error","type":"type_mismatch","file":...,"line":3,"col":18,...}]}` | **已实现**；缺夹具与负例，记 **D**（补证据，不新开能力） |
| 解析错误的 JSON | `ct check --diagnostics=json parse.ct` 仍输出 `parse.ct:1:1: error: unexpected token`（stderr，纯文本） | **A bug**：usage 全局宣称 `--diagnostics=text\|json`，解析通道静默回退文本 |
| 字段级位置 | `Symbols.h.ct:232-238` 的 `Field{name,type,dims}` 无 `line/col`；结构体字段相关诊断只能回到 struct 行 | **B 新特性**：要动前端模型，归 PH-58 |

因此本条不再整体按 feature 排期：解析错误 JSON 进 patch（与 LANG-3 的诊断判据共用夹具），
字段位置进 PH-58，警告 JSON 只补夹具复验。原「请求」与「验收判据」保留作为能力全量目标。
