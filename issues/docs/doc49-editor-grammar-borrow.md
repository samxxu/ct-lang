# DOC-49 · 新语法 `borrow` / `Handback` 未同步编辑器语法，`check-grammar.py` 也没有对应断言

| 项 | 值 |
| --- | --- |
| 严重度 | Medium（违反 AGENTS §6 的强制同步项；高亮缺失与 `own` 的既有处理不一致） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [editors/vscode/syntaxes/ct.tmLanguage.json:218-222](../../editors/vscode/syntaxes/ct.tmLanguage.json#L218-L222)、[editors/vscode/test/check-grammar.py:231-233](../../editors/vscode/test/check-grammar.py#L231-L233)；规定见 [AGENTS.md:178-180](../../AGENTS.md#L178-L180) |
| 状态 | 已修（2026-11-01）：`ct.tmLanguage.json` 新增 `ct-borrow` / `ct-borrow-param` / `ct-trait-builtin` 并入 `patterns`；`check-grammar.py` 断言 31→33 全绿 |

## 现象

AGENTS §6：「语法有变必须同步 `editors/vscode/syntaxes/ct.tmLanguage.json`，并跑
`python3 editors/vscode/test/check-grammar.py`（31 项断言，必须全绿）」。

`borrow` 是本轮新增的上下文关键字（与 `own` 同类：只在行首/参数首位生效），但：

- `ct.tmLanguage.json` 里有 `ct-own` 规则（`:218`，`^[ \t]*(own)\b` → `storage.modifier.own.ct`），
  **没有** `ct-borrow`，也没有 `Handback` 的 trait 名规则；
- `check-grammar.py` 只断言了 `own Box *b -> ct-own`（`:231-233`），没有 borrow 的对应断言；
- 因此九道硬关卡全绿并不能说明编辑器侧跟上了新语法。

`git status` 中 `editors/` 无任何改动。

## 证据

```text
$ grep -n "borrow" editors/vscode/syntaxes/ct.tmLanguage.json
（无匹配）
$ grep -n "ct-own" editors/vscode/syntaxes/ct.tmLanguage.json
218:    "ct-own": {
219:      "match": "^[ \\t]*(own)\\b",
```

## 建议

1. 照 `ct-own` 复制一条 `ct-borrow`（`^[ \t]*(borrow)\b` → `storage.modifier.borrow.ct`），
   并入 `patterns` 的 `include` 列表；
2. 参数位形态（`f(borrow T *r)`）需要一条不锚行首的规则，或把 `borrow` 加进已有的参数修饰符集合；
3. `check-grammar.py` 加两条断言（行首声明 + 参数注解），把断言数从 31 提到 33，
   并同步 README / AGENTS 里写的断言数；
4. `Handback` 与 `Drop` 一起加进内置 trait 的高亮集合（当前 `Drop` 也没有，可一并补）。
