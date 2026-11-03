# TEST-16 · `ct check` 的 import 拒绝没有回归断言

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | Medium |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | [selfhost/check-semantics.sh:167](../../selfhost/check-semantics.sh#L167)；对照用例 [selfhost/check-ast.sh:2670](../../selfhost/check-ast.sh#L2670) |
| 状态 | 已修复（本轮，2026-11-03） |

## 现象

`ct check` 对含 `import` 的单元直接拒绝（exit 1），这是 Phase 19.4 的实际对外行为，但：

- `check-semantics.sh` 的 14 条断言里没有任何 import fixture；全文唯一出现 `import` 的地方是
  `:167` 的一句注释（「The trait lives in the same unit here; the imported-unit half of the check …」）；
- `check-ast.sh:2670` 的跨单元签名用例走 `build --emit-c` + `cmp expected.out`，钉的是 warning 文本
  与产物字节，**不是** `ct check` 的可失败路径。

因此「check 拒绝 import」既无正例也无负例，改动实现时不会有人发现。

## 证据

```text
$ grep -n "import" selfhost/check-semantics.sh
167:# The trait lives in the same unit here; the imported-unit half of the check ...
```

（仅注释，无探针）

```text
$ ct-ast check -I src src/main.ct
src/main.ct:1:1: error: 'import' is not supported in compile mode
rc=1
```

- `check-semantics.sh` 的四类发现各只覆盖单文件形态（arity / 实参类型 / 歧义 / impl 漂移）。
- `check-ast.sh:2670` 的断言形态是 `warning:` + `cmp`，不会因 check 行为变化而失败。

## 影响

Medium：这是新子命令的边界行为，且与 DOC-62 的文档修复配套。若未来把 check 扩到多文件（或只改报文
措辞），现有 12 道门禁全部绿，回归只能在人工复核时发现。

## 修复建议

1. 在 `check-semantics.sh` 增一条负例：复制一份含 `import` 的 `.ct`，断言 exit 1 且 stderr 含
   `'import' is not supported in compile mode`；
2. 同文件保留一条「纯单文件 check 通过」的正例作对照（现有 clean 用例可直接复用）；
3. 若 DOC-62 采纳专门的 import 提示，同步更新断言文本。

## 验证

- `bash selfhost/check-semantics.sh` 全绿，新断言在正常树上通过；
- 临时删除 import 拒绝分支（或在副本里放开），新断言应失败，证明它真的钉住了行为；
- `bash selfhost/check-all.sh` 仍为 `12 hard gates green`。

## 处置

**认可，已修。**

- 新增负例 fixture（`import other::Thing;` + `main`），断言 `exit 1` 且 stderr 含
  `'import' is not supported in compile mode`，见
  [check-semantics.sh:107-122](../../selfhost/check-semantics.sh#L107-L122)。
- 正例复用已有的 clean 用例（纯单文件 check 退出 0 且无输出），未新增重复 fixture。
- 建议 3 未触发：DOC-62 的代码侧专门提示未采纳，断言文本与现有实现一致。
- 反向验证：把该 fixture 的 `import` 行删掉后 check 退出 0，说明断言确实依赖 import 这条路径；
  `check-semantics.sh` 19 条断言全绿。
