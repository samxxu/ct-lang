# DOC-65 · README / 教程的 `ct compile` 行未说明「仅单文件、`import` 需 `ct build`」

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Medium |
| 锚点 | commit `c27da3d`（2026-11-06，`v0.19.1`+1） |
| 文件 | [README.md:37](../../README.md#L37) / [README.md:118](../../README.md#L118)（中英）、[tutorial.md:506](../../docs/tutorial.md#L506) / [tutorial.md:1064](../../docs/tutorial.md#L1064)（中英） |
| 状态 | 已修（2026-11-06，commit `82fab61`） |

## 现象

`ct check` 的表格行已经写明单文件边界（DOC-62 的修复）：

```text
| ct check <in.ct> | …（仅单文件单元，import 不被接受）… |
```

但同一张表里更靠前的 `ct compile` 行只写「单文件编译」，没有解释这个定位意味着
`import` 不被接受、也没有给出替代路径。教程里同样只有 `ct build … -I <dir>` 一行
（[tutorial.md:513](../../docs/tutorial.md#L513) / [tutorial.md:1071](../../docs/tutorial.md#L1071)），
`ct compile` 的 `-I` 既未列入表格，也未说明无效，而编译器 `--help` 仍宣称 compile 可用（SH-54）。

结果：用户只有踩到下面这条报错，才能反推出 compile 是「单单元、无依赖」模式：

```text
error: 'import' is not supported in compile mode
```

## 复现

```bash
$ grep -n 'ct compile' README.md docs/tutorial.md | head
37:| `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h` |
506:| `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h` |

$ ct compile test/modules/inc/main.ct -o /tmp/x.c
test/modules/inc/main.ct:1:1: error: 'import' is not supported in compile mode
```

`ct compile` 行的文本与是否支持 import 无关，读者无法从表格判断边界。

## 根因

- [DOC-62](../docs/doc62-check-import-undocumented.md) 的修复只覆盖了 `ct check` 一行，
  未顺手把同一张表里的 compile 行补齐；
- README / 教程的 `-I` 说明只挂在 build 行上，而 compile 的 `-I` 在实现中被静默丢弃（SH-54），
  文档没有可对应的口径；
- 语言规范里虽有“`ct compile` 不解析 import”（[language-spec.md:544](../../docs/language-spec.md#L544)），
  但位置在 `.m.ct` 生成物小节，普通 CLI 用户不会读到。

## 影响

- 想只编一个 `.ct` 但其中引用依赖包的用户，会先假设 compile 能配合 `-I`，然后被报错劝退；
- 想用 `ct compile` 做单文件语法/构建检查的用户，不知道应改用 `ct build`；
- 编辑器/LSP 场景的单文件编译体验无法从文档判断是否受支持。

## 修复建议

在 README 中英与 tutorial 中英的 compile 行各补一句，保持表格简短：

- 中文：

  ```text
  | `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h`；仅单文件单元，`import` 需 `ct build` |
  ```

- 英文：

  ```text
  | `ct <in.ct>` / `ct compile <in.ct>` | single-file compile: a plain `.ct` writes only the `.c`, a `.h.ct` input also writes `<in>.h`; single-file units only, `import` requires `ct build` |
  ```

若 SH-54 采纳「`-I` 在 compile 下报警/报错」，同一处再补半句 `-I` 仅 build 有效。
不建议为此改语言规范正文；规范里的现有句子保留即可。

## 验证

- 四张表（README 中/英、tutorial 中/英）都能检索到 compile 行的 `import` 与 `ct build`；
- `ct check` 行原有边界说明不变，两行口径一致；
- `python3 test/docs/check-docs.py` 通过；无需改 golden 或源码；
- `bash selfhost/check-all.sh` 12 道门禁全绿。

## 处置

**认可，README 与教程各中英两处，共四处已补齐。**

- 中文（[README.md:37](../../README.md#L37)、[docs/tutorial.md:506](../../docs/tutorial.md#L506)）：

  ```text
  单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h`；只接受**单文件单元**，
  `import` 需改用 `ct build`（`-I` 同理只对 build 生效，compile 下会提示被忽略）
  ```

- 英文（[README.md:118](../../README.md#L118)、[docs/tutorial.md:1064](../../docs/tutorial.md#L1064)）：
  补 `**single-file units only**, so import needs ct build`，并注明 `-I` 同样只对 build 生效。
- `-I` 的补充说明是本轮 SH-54 采纳 warning 后才成立的，因此两处一并写；教程句子较短，
  只保留「`-I` 同理只对 build 生效」。
- 未改语言规范正文（沿用建议）：[language-spec.md:544](../../docs/language-spec.md#L544) 的现有句子保留。
- `ct check` 行原有边界说明未动，两行口径一致。
- 提交：`82fab61`。
