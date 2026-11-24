# SH-120 · `Str.h.ct` 一单元四类型：String/Str 留 `lib/core`，U16 对进 `lib/core/utf16`（namespace `core::utf16`）

| 项 | 值 |
| --- | --- |
| 模块 | lib/core（内置层单元布局） |
| 定性 | 结构/规范违规（不是运行时缺陷） |
| 严重度 | **Medium**（当前行为正常；拆分触及内置层硬编码、命名空间与自举产物） |
| 锚点 | `38fa7f80`（`v1.0.0-29`，2026-11-24） |
| 文件 | `lib/core/Str.h.ct:48-71`；`selfhost/check-ast.sh:307-318`；`selfhost/ct-ast/frontend/module/Module.h.ct:161-165,2223-2243`；`selfhost/ct-ast/tool/driver/Driver.h.ct:368-377`；`selfhost/ct-ast/frontend/parse/Expr.h.ct:6428`、`Stmt.h.ct:4853` |
| 状态 | open |
| 结论 | **违规成立。** 所有者 2026-11-24 最终口径：`String` / `Str` 拆成两个文件但**不改目录**（仍在 `lib/core/`，`namespace core`）；只有 U16 对进入 `lib/core/utf16/`，并使用 `namespace core::utf16;` 以满足“目录 = 命名空间”。U16 的公开名因此变为 `core::utf16::U16String` / `core::utf16::U16Str`，是**破坏性命名变更**，必须带迁移说明。 |

## 现象

`lib/core/Str.h.ct` 一个 `.h.ct` 单元同时声明了：

- `ct_str_hdr`（第 48 行，共享 8 字节 refcount 头；辅助记录，按规则可同文件）
- `String`（第 53 行，UTF-8 owning 主类型）
- `Str`（第 58 行，UTF-8 borrowed 主类型）
- `U16String`（第 66 行，UTF-16 owning 主类型）
- `U16Str`（第 71 行，UTF-16 borrowed 主类型）

`lib/core/README.md` 也明写内置层是五个单元，`Str.h.ct` 承载
“`String` / `Str` + `U16String` / `U16Str`”。这不是临时备注，是当前布局。

## 规则与证据

- `docs/glossary.md:113`：每个单元以主类型命名，**一个单元一个主类型**，附属记录类型可同文件。
- `docs/package-guide.md:43`：源码单元遵守「一单元一主类型」；**单元目录 = 命名空间**。
- `docs/language-spec.md:741`：`.h.ct` 文件名与主类型同名是仓库约定；`selfhost/check-ast.sh` 的
  unit-name lint 只扫 `selfhost/ct-ast/**`，用户工程不受检查。
- `lib/core/README.md`：内置层“五个单元”，`Str.h.ct`（Phase 80：`String` / `Str` + UTF-16 对）。

**为什么一直没红**：`selfhost/check-ast.sh:307-318` 的 lint 只做两件事——只扫
`selfhost/ct-ast/**`，且只检查“文件名在文件里有同名类型”。它不扫 `lib/core`，也不检查
“主类型只能有一个”；所以 `Str.h.ct` 即使带四个类型也会通过。

## 使用面审计（2026-11-24）

“U16 没什么地方在用”**不成立**，但外部样例确实为零：

| 范围 | 含 `U16String` / `U16Str` 的文件 |
| --- | --- |
| `selfhost/ct-ast/**` | **12** |
| `test/ast/**` | **8**（`p80_*`、`p106_str_escape` 等） |
| `examples/**` | **0** |
| `lib/core/Str.h.ct`（实现本身） | 1 |
| 活跃文档（README/spec/tutorial/guide/glossary 等） | **12** |
| 历史文档（history/reviews/proposals/decisions） | 25 |

编译器不是“无感”的：`SymbolsTypeText.h.ct:231` 把 `U16String` 映射到 kind 2，
`Module.h.ct:302,340`、`Stmt.h.ct`、`Expr.h.ct` 都有 `U16String` / `U16Str` 的保留名、
borrow/drop/goto/return 判定与路径特判。把公开名改成 `core::utf16::U16String` 至少要同步这些点；
只改文件路径、不改编译器识别，会出现“文件在 `utf16`、代码仍按根名解析”的错位。

**结论**：仓库内没有 examples/外部包使用，用户侧影响可能低；但**不是零影响**，编译器 12 个文件、
测试 8 个文件、活跃文档 12 份必须跟着改。是否给旧名 `core::U16String` / `core::U16Str` 一个
兼容别名，应按“是否已对外发布 U16 API”决定，不能按“没人用”默认省略。

## 目标布局（四个文件）

| 文件 | 主类型 | 命名空间 | 约行数 |
| --- | --- | --- | --- |
| `lib/core/String.h.ct` | `String`（+ 辅助 `ct_str_hdr`） | `core` | 187 |
| `lib/core/Str.h.ct` | `Str` | `core` | 94 |
| `lib/core/utf16/U16String.h.ct` | `U16String` | `core::utf16` | 约 791 |
| `lib/core/utf16/U16Str.h.ct` | `U16Str` | `core::utf16` | 47 |

- `String` / `Str` **不换目录**：仍在 `lib/core/`，公开名保持 `core::String` / `core::Str`；
- 只有 U16 对进 `lib/core/utf16/`，目录名 `utf16` 与 `namespace core::utf16` 对齐；
- `ct_str_hdr` 是辅助记录，跟随 `String` 放 `String.h.ct`，不自成文件；
- U16 四个类型全部独立：`U16String` 791 行是大文件；`U16Str` 只有 47 行但本轮明确也独立。

## 命名空间与 API 影响（破坏性）

`namespace core::utf16;` 让 U16 的公开源名从：

- `core::U16String` → `core::utf16::U16String`
- `core::U16Str` → `core::utf16::U16Str`

`String` / `Str` 保持 `core::String` / `core::Str`。这不是纯文件移动：

- 文档、tutorial、`lib/core/README`、`docs/language-spec` 中的 U16 名称要全量更新；
- 用户的 `import`/限定名要改；若现有源码写 `core::U16String`，需要兼容别名或迁移窗口；
- C 符号可能从根拼写变成 `core_utf16_U16String` 一类，`--emit-model`/golden/ABI 要复核；
- 保留名/词法识别里的 `U16String` / `U16Str` 要按命名空间更新，不能只改文件位置；
- `String.to_utf16()` / `String.from_utf16(U16Str)` 位于 `core::utf16` 单元、扩展 `core::String`，
  需确认 `impl core::String` 的跨命名空间写法；若语言不允许，改成 `string_to_utf16` /
  `string_from_utf16` 自由函数，并在实施前记录 API 变化。

**建议**：在 `lib/core/README` 与 `docs/language-spec` 写清 U16 的新规范名，并给一个 MINOR 的
旧名兼容别名（若类型别名可行）；没有迁移说明就不要直接改公开名。

## 依赖方向（必须无环）

```
Str.h.ct        （无 import）
String.h.ct     → Str.h.ct
U16Str.h.ct     （无 import）
U16String.h.ct  → core::String / core::Str / core::utf16::U16Str
```

具体：

- `String.h.ct` 的方法返回 `Str`（`as_str` / `slice` / `find`），所以 import `core::Str`；
- `Str.h.ct` 不返回 `String`：把 `Str.to_string`、`str_dup`、`str_concat` 等移到
  `String.h.ct`（`impl Str` 扩展或自由函数，实施前裁定并记录 API 影响）；
- `U16Str.h.ct` 不返回 `U16String`：把 `U16Str.to_string` 移到 `U16String.h.ct`；
- `U16String.h.ct` 使用 `core::String`（`impl core::String` 扩展里的 `from_utf16` 返回 `String`）与
  `core::Str` / `core::utf16::U16Str`（`U16String.to_utf8()` 返回 `Str`），所以 import 三个文件；
- `String.h.ct` 不引用 `U16String`：把 `String.to_utf16()` / `String.from_utf16(U16Str)` 放在
  `U16String.h.ct` 的 `impl core::String` 扩展块；若不可行，改为自由函数。

这样四个单元是**单向 DAG**，C 头文件也不会互相包含成环。

## 内置层改动（5 → 8）

- `Module.h.ct:161-165`：`builtin_units[5]` / `builtin_live[5]` → 8；
- `Module.h.ct:2223-2243`：build 加载顺序改为 `Vec` / `Option` / `Result` / `Str` / `String` /
  `U16Str` / `U16String` / `Box`（U16String 依赖 String/Str/U16Str，必须最后）；
- `Driver.h.ct:368-377`：compile 模式同样 8 个单元；
- `find_builtin`：U16 两个单元要按 `lib/core/utf16/<base>` 查找，String/Str 仍按 `lib/core/<base>`；
- `Expr.h.ct:6428`、`Stmt.h.ct:4853`：`ptr` 写保护从 `lib/core/Str.h.ct` 扩到
  `lib/core/String.h.ct`、`lib/core/Str.h.ct`、`lib/core/utf16/U16String.h.ct`、
  `lib/core/utf16/U16Str.h.ct`；
- `Module.h.ct:2777-2779`：`builtin_live_for` 按 base `"Str"` 的查找要覆盖 String/Str/U16；
- `test/ast/p65_regression.sh:19`、`test/ast/232_str_own_pointer/prog.ct`、`test/ast/p80_migrate.sh`
  等旧路径引用要更新。

任一遗漏都会重演 SH-116（内置单元未并入 build 产物）。

## 本期范围

- 四个文件按上表落地；`String`/`Str` 不换目录；只有 U16 进入 `lib/core/utf16/` 且
  `namespace core::utf16`。
- `ct_str_hdr` 跟 `String` 同文件（辅助记录）。
- **不写 phase，不改代码**；本条目只登记问题、布局与验收，供后续 REQ/DEV 开卡。
- U16 公开名变更是破坏性变更；没有迁移/别名方案前不得实施。

## 期望 / 验收（后续实施时）

1. `lib/core/String.h.ct`（`String` + `ct_str_hdr`，namespace core）与
   `lib/core/Str.h.ct`（`Str`，namespace core）各自只有一个主类型；
2. `lib/core/utf16/U16String.h.ct`（`U16String`，namespace core::utf16）与
   `lib/core/utf16/U16Str.h.ct`（`U16Str`，namespace core::utf16）各自只有一个主类型；
3. 依赖为 `Str` / `U16Str` 无 import；`String → Str`；`U16String → core::String / core::Str /
   core::utf16::U16Str`；不存在环；
4. `ct compile` 与 `ct build` 都能编译使用四个类型的最小程序；`ct build` 产物包含
   `String.c`、`Str.c`、`U16String.c`、`U16Str.c`（或等价单元），不出现未定义/重复符号；
5. 内置层加载顺序为 `Str` → `String` → `U16Str` → `U16String`（Vec/Option/Result 在前），
   `builtin_units` / `builtin_live` 容量同步；`find_builtin` 支持 `lib/core/utf16/` 子目录；
   `ptr` 写保护覆盖四个文件；
6. `ct build examples/53_match_adt/prog.ct`、`examples/52_box_new/prog.ct`、`test/ast` 相关
   `String` / `Str` / U16 探针、goldens、bootstrap 不动点通过；
7. `selfhost/check-ast.sh` 的 unit-name lint 扩到 `lib/core` 与 `lib/core/utf16`；每个文件一个主类型
   （`ct_str_hdr` 作为辅助记录放行），负例“两个主类型”必须红；
8. 更新 `lib/core/README.md`（五个单元 → 八个；`lib/core/utf16` 与 `namespace core::utf16`；
   U16 新公开名）、`docs/language-spec.md`、tutorial 与所有旧路径/旧名引用；
9. U16 旧名 `core::U16String` / `core::U16Str` 的迁移/别名方案有记录；没有则不得直接改公开名；
10. **重生成 `bootstrap/ct-ast`**，`selfhost/check-seed.sh` 两轮重建逐字节一致、手改负例红；
    `install.sh` 用新 seed 装出的 `ct -v` 为当前版本——内置层变了而 seed 不换，等于发布旧编译器。

## 关联

- [SH-116](sh116-build-mode-box-unit.md)：内置单元未并入 build 产物的先例；拆分时必须同时验
  compile/build 两条路径。
- [DOC-54](../docs/doc54-unit-kinds-naming-import.md)：单元类型与命名/导入规则。
- [package-guide「一单元一主类型」](../../docs/package-guide.md)、
  [glossary「单元命名」](../../docs/glossary.md)。
- [lib/core/README](../../lib/core/README.md)：当前五单元布局的自我描述。
