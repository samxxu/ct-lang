# SH-47 · 容量触顶的报错不点名结构体 / 声明，只给一个行号

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 诊断） |
| 严重度 | Low（位置可用，但大文件里要自己回推是哪个 struct 触顶） |
| 锚点 | commit `dab1b71`（`v0.16.2`，2026-11-02） |
| 文件 | [Parser.h.ct:1109](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1109)、[:1124](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1124) |
| 状态 | 已修（2026-11-02，`v0.16.3`）：文案改为 `too many fields in struct '<name>' (limit 64)`，`check-ast.sh` 断言同步；行号维持当前字段行（见台账处置记录） |

## 现象

第 65 个字段越界时报错只写「记录里字段太多」，没有结构体名、没有上限值：

```text
$ ct big.ct -o big.c ; echo $?
big.ct:66:1: error: too many fields in a record
ctc: 1 error(s) generated
1
```

`66:1` 是该 struct 的收尾 `}`，不是触顶字段；文件里有多个 struct 时，用户仍要自己数。
第三方评估 §3.9 / CT-CAP-01 的建议是「报出文件 / 声明与触顶项」。

## 影响

- 大文件 / 生成式源码（字段多的记录很常见）排障成本高；
- 同类上限（`MAX_PARAMS` / `MAX_VARS` / `MAX_TRAITS` 等）的文案风格也不统一，均未点名宿主。

## 修复建议

1. 文案改为 `too many fields in struct '<name>' (limit 64)`，行号用 struct 的**声明行**
   （`Parser.h.ct` 解析 struct 时手里已有名字与起始行）；
2. 顺带核对其他容量诊断，至少加「上限值」；是否加 `--max-fields` 属能力变更，另行决定；
3. 门禁：现有 65 字段探针（`test/ast/errors` 侧或 `check-ast.sh` 的容量段）改为断言新文案，
   并保留非零退出。

## 验收

- 上面的探针报错含 `struct 'Big'` 与 `limit 64`；
- 未触顶的 64 字段记录不受影响；
- 九关全绿。

## 关联

- [SH-29](sh29-max-fields-silent-drop.md)：越界曾静默丢弃（已修）；本条只剩文案质量
- [SH-6](ct-ast-stale-cap-comments.md)：上限账本注释的陈旧问题
