# SH-53 · 容量触顶诊断不点名上限值与单元

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | Low |
| 锚点 | commit `c27da3d`（`v0.19.1` + 1 commit，2026-11-03）；本机 `ct v0.19.1` 复现 |
| 文件 | [Symbols.h.ct:259](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L259)、[:292](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L292)、[:474](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L474)；[ParseSupport.h.ct:248](../../selfhost/ct-ast/frontend/parse/ParseSupport.h.ct#L248)、[:286](../../selfhost/ct-ast/frontend/parse/ParseSupport.h.ct#L286) |
| 状态 | 已修复（2026-11-10 复核：四类容量诊断均点名单元与上限，`check-ast.sh` 的 cap 段有断言） |

## 现象

`MAX_FUNCS` / `MAX_STRUCTS` / `MAX_PARAMS` / `MAX_VARS` 触顶时，报文只有类别与行号，不写上限值、
不写单元名。SH-47 已经把字段上限改成 `too many fields in struct '<name>' (limit 64)`，但其余容量
诊断没有跟上同一范式。

## 证据

```text
$ ct compile many.ct -o many.c
many.ct:258:1: error: too many functions
```

（`many.ct` 为 300 个单行函数 + `main`；`MAX_FUNCS = 256`，见 `Symbols.h.ct:24`。）

源码中的五处文案：

```text
Symbols.h.ct:259        "too many variables"
Symbols.h.ct:292        "too many variables"
Symbols.h.ct:474        "too many structs"
ParseSupport.h.ct:248   "too many functions"
ParseSupport.h.ct:286   "too many parameters"
```

外部评估 §4.2 / S2 与 SH-47 的「影响」都指出同一问题；本轮实测确认报错行是该类别结束处，
大文件里无法直接判断是哪个声明触顶。

## 影响

Low：不影响编译结果，但生成式源码（函数 / 结构体成批生成）排障成本高；与已修好的 SH-47 文案风格
不一致，读者会以为只有字段上限有细节。

## 修复建议

1. 统一文案：`too many functions in unit '<name>' (limit 256)`、`too many structs ... (limit 128)`、
   `too many parameters ... (limit 16)`、`too many variables ... (limit 4096)`；
2. 单元名优先取当前解析单元（`unit` / 文件名）；拿不到时退化为 `in this unit`；
3. 行号尽量指向触顶项（第 257 个函数 / 第 129 个 struct 的声明行），而不是收尾 `}`；
4. 现有负例（`test/ast/errors/**` 或 `check-ast.sh` 容量段）同步断言新文案；
5. 「把固定上限改为动态扩容」是能力决策，不在本条范围（关联 `SH-1` / `SH-48`）。

## 验证

- 300 函数 / 140 struct / 17 参数 / 超量变量的探针均报 `limit N` 与单元名；
- 未触顶用例不受影响；
- `bash selfhost/check-ast.sh` 与 `bash selfhost/check-all.sh` 全绿。

## 处置（2026-11-10 复核）

本条修复已在后续轮次落地，只是状态行没有回填：

- `ParseSupport.h.ct:255` 报 `too many functions in unit '<name>' (limit N)`；
  `Symbols.h.ct:679` 报 `too many structs in unit '<name>' (limit N)`；
  `Symbols.h.ct:434/476` 报 `too many variables in unit '<name>' (limit N)`；
  `check-ast.sh:3800` 起报 `too many parameters in unit '<name>' (limit 16)`。
- `check-ast.sh` 的 `capacity limits (generated)` 段（[3781-3810](../../selfhost/check-ast.sh#L3781-L3810)）
  用 `cap_check` 同时断言非零退出与完整文案（含单元名与上限）。
- 未做：「行号指向触顶声明行」仍按现状落在类别收尾处；固定上限改动态扩容属能力决策（SH-1 / SH-48）。
