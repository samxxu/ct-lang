# PKG-22 · std 包：`std::str::String` 单元改名 `std::str::CharStr`

| 项 | 值 |
| --- | --- |
| 模块 | packages / ct-pkg `std` |
| 定性 | 命名修正（避免与内置 `String` 混淆） |
| 严重度 | Medium |
| 锚点 | `std 0.19.0`（2026-11-21；同日所有者更新目标名） |
| 依据 | [language-spec §5.1](../../docs/language-spec.md#L1978-L1989)；[DOC-85](../../issues/docs/doc-85-idiom-priority-card.md) |
| 状态 | open |
| 处置证据 | **open（REV 复核，2026-11-22：std 0.20.0 已发布 CharStr；本仓消费侧仍用旧名，包侧未留兼容别名）** |

## 现象

`std` 包的 `char *` 方法层：映射 trait 早已叫 `CStrOps`，但单元文件叫 `String.m.ct`，
所以导入写成 `import std::str::String;`。这与内置的 `String` 句柄同名，用户和模型容易
把它当成“内置 String 的包版本”，产生混淆。

本卡最初拟定的目标是 `std::str::CStrOps`。**2026-11-21 所有者更新**：`CStrOps`
将改名为 `std::str::CharStr`，因此跳过 `CStrOps` 这个中间导入名，单元与导入直接
由 `String` → `CharStr`；本仓不再按 `CStrOps` 口径写文档。若 std 包侧已经发布过
`CStrOps`，则按包自身的发布记录为它保留一个 MINOR 回退，不新增中间名。

## 决策

| 项 | 决定 |
| --- | --- |
| 单元文件 | `std/str/String.m.ct` → **`std/str/CharStr.m.ct`** |
| 导入写法 | `import std::str::CharStr;` |
| trait | 以 std 包发布为准：若 trait 随单元同步改名 `CharStr`，`map trait` 方法表与文档同步；本仓只保证导入名与说明一致 |
| 兼容 | 旧 `String.m.ct` 保留一个 MINOR：作为 `CharStr` 的薄兼容单元（若 import 可传递则直接转出；否则保留重复映射并在文件头标 deprecated） |
| 版本 | `std` 包 MINOR bump（0.x 语义允许），索引行随发布更新 |
| 本仓 | 只改文档/示例的导入口径；不改内置 `String`、不改 `std::*` 其他单元 |

> 不设 `CStrOps.m.ct` 过渡：本仓未消费过该单元（截至 std 0.19.0 仍是 `String.m.ct`），
> 多一个名字只会延长迁移面。

## 验收

1. `import std::str::CharStr;` 后 `"42".to_int()`、`s.length()` 等可用；
2. 旧 `import std::str::String;` 在兼容窗内仍可用，文件头有 deprecation 说明；
3. std 包内不再出现 `CStrOps.m.ct` 单元或 `import std::str::CStrOps;` 推荐写法；
4. `std` 包 `ct.pkg` 版本/索引行更新；`ct index verify` 通过；
5. `std` 包测试、`examples/wave1-demo` 等消费者迁移；
6. 内置 `String`/`Str`/`Vec` 等不受影响；
7. 一个 MINOR 后移除 `String.m.ct`，另立清理 issue。

## 非目标

- 不改方法语义（`to_int` 仍是 `atoi` 语义）；
- 不改内置 `String`（内置类型改名归 DOC-87 Stage 2）；
- 不改 `std::io` / `std::num` 等其他单元；
- 不在本仓复制 std 包源码。

## 风险

| 风险 | 缓解 |
| --- | --- |
| 旧导入路径失效 | 保留 `String.m.ct` 一个 MINOR；错误文案提示新路径 |
| 文档/示例漂移 | 本仓文档写“0.19.0 旧名 / 下一 MINOR 新名 `CharStr`”，不提前改可运行示例 |
| trait 名与单元名不同步 | 以 std 包发布为准；本仓文档只承诺导入名，trait 解释处标注“随包发布” |
| 包版本与索引不同步 | 发布时一次更新 `ct.pkg`、索引行、README |

## 关联

- [DOC-85](../../issues/docs/doc-85-idiom-priority-card.md)
- [language-spec §5.1](../../docs/language-spec.md#L1978-L1989)
- [DOC-87](../../issues/docs/doc-87-lib-core-rename.md)（内置层 `namespace core`，另一条线）

## §复核（REV，2026-11-22，HEAD `38cd4ae4`）

包侧（`ct-pkg/std`，只读核对，不代改）：

```console
$ grep -E '^std ' .temp/rev-pkg-head/index | head -1
std 0.20.0 ct https://github.com/ct-pkg/std v0.20.0 sha256:60d2e7dd157facc775e80d45e6769c4f2bfe7273feed6af7ccba9676d8ae42a7
$ .temp/rev-pkg-head/ct-ast index verify .temp/rev-pkg-head/index
index verify: OK (5 rows)                              # exit 0
$ git clone --depth 1 --branch v0.20.0 https://github.com/ct-pkg/std std20
$ git -C std20 log -1 --format='%H %s'
9949543b0260de6d19223473186b7b873cd90571 release: std 0.20.0
$ ls std20/std/str/
CharStr.m.ct   CharStr.shim.h   README.md
```

- `String.m.ct` 与 `CStrOps.m.ct` 都不在 0.20.0 的 `std/str/`；`CharStr` 已是唯一单元名。
- 用 HEAD 构建的 `ct-ast` 编译 std 自带消费者：
  `ct-ast build -I std20 std20/tests/utf8/guide.ct` → `build exit=0`，运行
  `35 checks, 0 failures`，`exit 0`。
- 旧导入 `import std::str::String;` 对 0.20.0 直接失败：
  `ctc: cannot resolve import 'std/str/String'`（exit 1）。std 的 `CHANGELOG.md` 0.20.0
  明写“不留兼容别名（项目未正式发布）”——与本卡“旧 `String.m.ct` 保留一个 MINOR”的决策
  **不一致**，需 REQ 书面确认以包侧决定为准，还是要求补兼容单元。

本仓侧（未完成）：

- `examples/wave1-demo/src/main.ct:7` 仍写 `import std::str::String;`；内置 pin 仍是
  `std 0.19.0`（`selfhost/ct-ast/tool/pkg/Pkg.h.ct:2306`），因此示例现在仍能编译；
- 生效文档仍有“下一 MINOR 改名”的旧口径：`docs/std-catalog.md:39`、`docs/tutorial.md:739`、
  `docs/language-spec.md:146`（另 `docs/idioms.md` / `docs/guide-for-c-programmers.md` 已按
  CharStr 写，口径不齐）；
- 因为 pin 未升级，把示例改成 `CharStr` 会与 0.19.0 的包内容不一致；0.20.0 又没有旧名别名，
  所以必须和 pin 升级同一次做。

处置：保持 `open`，不标 `verified`——验收 2（旧导入在兼容窗内可用）被包侧决定推翻且未获
REQ 确认，验收 5（`examples/wave1-demo` 等消费者迁移）未做。最小下一步：

1. REQ 书面确认：接受 std 0.20.0 “无兼容别名”，并据此改写本卡验收 2/7；或要求 std 包补
   `String.m.ct` 薄兼容单元（一个 MINOR）；
2. DEV 在“内置 pin 升到 0.20.0”的同一提交里迁移 `examples/wave1-demo` 与上述三处文档，
   跑 `ct build` + `ct index verify` + conformance；
3. 迁移后旧名不再出现在可运行示例与推荐写法中，再转 `verified`。

owner：REQ（兼容裁决）+ DEV（pin/示例/文档）；P2。
