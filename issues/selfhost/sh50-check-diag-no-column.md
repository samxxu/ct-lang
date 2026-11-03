# SH-50 · `ct check` 的语义诊断缺列号，与 `file:line:col:` 契约不符

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | Medium |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | [Diag.h.ct:304](../../selfhost/ct-ast/tool/diag/Diag.h.ct#L304)（`sem_error` 家族，`307/310/313/316/319/322` 同形）；parser 对照 [L77](../../selfhost/ct-ast/tool/diag/Diag.h.ct#L77) |
| 状态 | 已修复（本轮，2026-11-03） |

## 现象

Phase 19.4 的四类语义发现统一走 `Diag.h.ct` 的 `sem_error` 家族，格式串是 `"%s:%d: %s: …"`——只有
文件与行，没有列。parser 侧的 `diag_error`（`:77`）用的是 `"%s:%d:%d: error:"`，三段齐全。

于是 `ct check` 成为唯一不满足「`文件:行:列: error:`」契约的诊断通道。

## 证据

```text
$ ct-ast check drift.ct
drift.ct:3: error: signature mismatch ...
rc=1
```

```text
$ ct-ast --diagnostics=json check drift.ct
{"file":"drift.ct","line":3,"severity":"error",...}
```

JSON 里同样没有 `col`。

- 契约出处：[README.md:44](../../README.md#L44)（英文 [L123](../../README.md#L123)）；
- 历史同源问题 SH-9 已修 parser 侧，语义诊断是残留；
- `Diag.h.ct:304,307,310,313,316,319,322` 共 7 处 `fprintf(tf, "%s:%d: %s: …")`。

## 影响

Medium：编辑器 / IDE 只能跳到行首，无法把光标定位到具体 token；与同一工具其它诊断的格式不一致，
按统一正则解析诊断的工具会在 check 输出上解析失败。四类发现中最需要定位的是「实参类型不兼容」
与「trait 方法歧义」，都指向具体实参，缺列的影响最明显。

## 修复建议

1. 语义诊断携带触发 token 的起始列，text 改为 `"%s:%d:%d: %s: …"`；
2. JSON 增 `col` 字段（字段名与 parser 侧一致，避免两套 schema）；
3. `check-semantics.sh` 的 14 条断言各补「报文含列号」的校验；
4. 保留 `ct compile` 侧的 warning 文案不变（那是外部契约，另议）。

## 验证

- 四类探针（arity / 实参类型 / 歧义 / impl 漂移）的 text 报文均为 `file:line:col: error:`；
- `--diagnostics=json` 的每个对象含数值 `col`；
- `bash selfhost/check-semantics.sh` 与 `bash selfhost/check-all.sh` 全绿；
- `check-ast.sh` 中依赖 compile warning 文本的断言不受影响。

## 处置

**认可，已修。四条建议全部落地。**

- `Warn` 增 `int col`（[Diag.h.ct](../../selfhost/ct-ast/tool/diag/Diag.h.ct)），四个 `record_*`
  与四个 `ct_*_warn` 原语增加 `col` 参数；leak / borrow 类记录 `col=0`。
- text 输出在 `emit` 里统一构造位置前缀：`strict && col > 0` → `file:line:col:`，否则 `file:line:`；
  JSON 同样只在 strict 下追加 `"col":N`。因此 **compile / build 的文本与 JSON 字节不变**（D19-4 的
  外部契约，建议 4）。
- 列号来源：parser 侧在方法名 token（impl 漂移）与调用点标识符 token（arity / 实参类型 / 歧义）处取
  `tokstart - lstart + 1`；`ParseSupport` 与 `Expr` 的 `arity_warn` / `type_warn` / `amb_warn`、
  `arity_check` / `argtype_check` 相应加参数。
- 验证：`check-semantics.sh` 从 14 条增至 19 条——四类各加一条 `file:line:col: error:` 断言、JSON 断言
  加 `"col":`、compile 对照追加「不得出现 `file:line:col: warning:`」；`check-all.sh` 12 道全绿
  （含 `check-ast.sh` 的字节对比）。
