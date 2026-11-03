# DOC-62 · README / 教程未说明 `ct check` 拒绝 `import`

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Medium |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | [README.md:39](../../README.md#L39)（英文 [L118](../../README.md#L118)）；[docs/tutorial.md:508](../../docs/tutorial.md#L508)、[L1066](../../docs/tutorial.md#L1066) |
| 状态 | 文档已修；代码侧建议不采纳（本轮，2026-11-03） |

## 现象

`ct check` 复用 `compile_main`，因此继承了「compile 单文件模式拒绝 `import`」的限制。但 README 的
`ct check` 行与教程中英两张 CLI 速查表都只写「只跑受限语义检查、不写文件」，没有说明该输入限制。

用户按 `ct build` 的心智对模块入口（如 `src/main.ct`）运行 `ct check` 时，得到的报错指的是 `import`
而不是源码本身的问题。

## 证据

```text
$ ct-ast check -I src src/main.ct
src/main.ct:1:1: error: 'import' is not supported in compile mode
rc=1
```

- `ct check` 的退出码在「有语义发现」与「输入不被支持」两种情况下都是 1，无法区分。
- 教程 `docs/tutorial.md:508` / `:1066` 是 DOC-59 新增的 `ct check` 行，同样没有 import 说明。
- `check-semantics.sh` 的 14 条断言里也没有 import fixture（见 TEST-16）。

## 影响

Medium：这是新入口的第一道使用门槛。用户会误以为模块源码有错，或在「检查失败」和「不支持」之间
反复排查；对照 `ct build` 的行为（支持 `import`）更容易误解。

## 修复建议

1. README 中英 `ct check` 行补半句：「只接受不含 `import` 的单文件单元」；
2. 教程中英两张表同补；
3. 可选（代码侧，需另行决策）：让 check 对含 `import` 的输入给专门提示，
   `ct check does not support import; use ct build`，与 SH-49 的输入限制处理方式一致。

## 验证

- 改后 README 与教程四处文案一致，且都点明 import 限制；
- `ct check` 对普通单文件行为不变（四类探针仍 exit 1，clean 用例 exit 0）；
- `bash selfhost/check-semantics.sh` 全绿。

## 处置

**建议 1、2 认可并已修；建议 3 不采纳。**

- README 中英两行补「仅单文件单元，`import` 不被接受」/ `single-file units only; import is not
  accepted`，见 [README.md:39](../../README.md#L39) 与 [L118](../../README.md#L118)。
- 教程中英两张表同补，见 [docs/tutorial.md:508](../../docs/tutorial.md#L508) 与
  [L1066](../../docs/tutorial.md#L1066)。
- 建议 3 不做专门提示的理由：`ct check` 之所以拒绝 import，是因为它根本没有多单元模式（报告 R-01）。
  专门文案会在功能补齐时整条删掉，而现在这条 `'import' is not supported in compile mode` 与该限制
  一一对应；TEST-16 已把这段文本钉住，避免措辞与文档再次脱节。若将来采纳 R-01，应当同时改实现、
  两处文档与 TEST-16 这条负例。
- 验证：12 道门禁全绿；`check-semantics.sh` 19 条断言全绿（含新增 import 负例）。
