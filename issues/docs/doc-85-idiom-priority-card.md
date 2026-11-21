# DOC-85 · 惯用优先级卡：事实修正后入 `docs/idioms.md`

| 项 | 值 |
| --- | --- |
| 模块 | docs（读者路径 / 惯用法） |
| 定性 | 文档缺口 + 事实修正 |
| 严重度 | Medium |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [外部评审与惯用卡评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md) §2 |
| 状态 | **待办（先修事实，再与 D1 同批入库）** |

## 现象

外部《CT 惯用优先级卡》方向正确，但原稿有硬伤，不能直接入 `docs/idioms.md`：

| 原稿 | 问题 | 修正 |
| --- | --- | --- |
| “CT 是 C 的超集” | 与 DOC-76 冲突 | 改为“C 风格，但兼容承诺已收窄” |
| “指针只出现在 shim/MMIO/extern” | 指针在任何 `.ct` 合法 | “主要在 shim/硬件/逃生层；应用层先想 Str/切片/box” |
| `"42".to_int()` | 需 `import std::str::String;` | 补 import 前提；内置层不自动带 |
| “借用类型不能存（字段/容器/全局 = 硬错）” | `Vec<Str>` / `Option<Str>` / ADT 负载可编译；全局 `Str g = "x"` 也可编译 | struct 字段 / `Map` 键硬错；全局/容器/ADT 是借用视图风险 |
| “返回局部视图 = 硬错” | `Str` 逃逸无 lint（SH-106）；`T[]` 是 warning | 改为“T[] 有 `slice escape` warning；Str 无 lint” |
| “owning 自动释放” | 字段/全局/ADT payload 无自动 Drop；环泄漏 | 补边界 |
| “泄漏 = 告警（strict 包内 error）” | 实际是 `ct.pkg` 的 `leaks = warn\|error`，与 `c-boundary=strict` 无关 | 改为“`leaks=error` 可让 build 失败” |
| `foreach (v) { i, item }` | `i` / `item` 是**块内隐式绑定**，不是头列表；`{ i, item; }` 只是逗号表达式 | 正确写法 `foreach (v) { … i … item … }`；v0.84.1 数组与 Vec/Map 都绑定只读 `i` |
| 附录 briefing | 重复上述错误 | 同步修 |

## 期望

1. 按上表修正原稿，新增 `docs/idioms.md`；
2. 从 `docs/README.md` 与 `llm-guide.md` 的读者路径引入，避免“仓库一套、外部一套”；
3. 与 [DOC-86](doc-86-readme-v088-rewrite.md)（README 大改）同批施工；
4. 不把原稿直接复制入库；修正稿逐条对照本 issue。

## 验收

- 修正稿不再出现“超集”“只出现在”“一律硬错”“i, item”；
- 每个“首选/避免”条目可在 spec、guide 或实测找到出处；
- `check-docs` 绿；`idioms.md` 不重复 `language-spec` 的完整语法表。

## 非目标

- 不新增语言特性；
- 不改 `llm-guide.md` 的既有行为规矩（只加读者路径）。

## 关联

- [评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md)
- [DOC-86](doc-86-readme-v088-rewrite.md)
- [SH-106](../selfhost/sh106-str-view-escape-no-lint.md)
