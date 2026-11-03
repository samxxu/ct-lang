# DOC-59 · 教程的 CLI 速查表没有 `ct check`

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Low |
| 锚点 | commit `db4cae4`（2026-11-03，`v0.19.0`） |
| 文件 | [docs/tutorial.md:506-522](../../docs/tutorial.md#L506-L522)（英文 [L1063-1078](../../docs/tutorial.md#L1063-L1078)） |
| 状态 | 已修复（本轮，2026-11-03） |

## 现象

教程的「命令行速查」表列出了 `ct <in>` / `compile` / `build`（及各种开关）/ `get` / `update` /
`install` / `verify` / `-v` / `-h`，**没有 `ct check`**；中文表与英文表都一样。

## 证据

- 根 [README.md:39](../../README.md#L39)（英文 `:118`）已有：
  `ct check <in.ct>` —— 只跑受限语义检查、不写 `.c`，四类发现以 `error:` 报告，退出 1 / 0。
- 教程全文搜索 `ct check` 无结果（`grep -n "ct check" docs/tutorial.md`）。
- 教程把 `--diagnostics=json|text` 只描述为「告警格式（默认 text 写 stderr）」（`:515` / `:1072`），
  没有提到 check 模式下每个对象会带 `"severity":"error"`。

## 影响

`docs/README.md` 把教程定位为「第一次使用」的入口；新子命令只出现在 README 的表格里，
按教程走的人不会知道 `ct check` 存在，也不知道机器可读输出在 check 下的形态。

## 修复建议

1. 中文表在 `ct build` 行之后、`ct get` 之前加一行：
   `| \`ct check <in.ct>\` | 只跑受限语义检查、不写文件：arity / 实参类型 / 方法歧义 / impl 漂移以 \`error:\` 报告；有任何发现退出 1 |`
2. 英文表对应位置加同一行的英文版。
3. `--diagnostics` 两行各补半句：check 下 JSON 对象带 `"severity":"error"`；compile 下保持原状。

## 处置

**认可，已修。** 三条建议全部落地：

- 中文表新增 `ct check` 行，见 [docs/tutorial.md:508](../../docs/tutorial.md#L508)；英文表对应行见
  [docs/tutorial.md:1066](../../docs/tutorial.md#L1066)。
- `--diagnostics` 两行补上 check 下的语义（同批记录按错误报告、JSON 对象带 `"severity":"error"`），
  见 [docs/tutorial.md:516](../../docs/tutorial.md#L516) 与 [1074](../../docs/tutorial.md#L1074)。
- 措辞与根 README 的 `ct check` 行一致，并显式写出「及既有 leak / 借用类发现」，因为
  `set_strict` 覆盖的是所有 kind，而不只是 19.1-19.3 的四类。
