# PKG-22 · std 包：`std::str::String` 单元改名 `std::str::CharStr`

| 项 | 值 |
| --- | --- |
| 模块 | packages / ct-pkg `std` |
| 定性 | 命名修正（避免与内置 `String` 混淆） |
| 严重度 | Medium |
| 锚点 | `std 0.19.0`（2026-11-21；同日所有者更新目标名） |
| 依据 | [language-spec §5.1](../../docs/language-spec.md#L1978-L1989)；[DOC-85](../../issues/docs/doc-85-idiom-priority-card.md) |
| 状态 | deferred |
| 处置证据 | **deferred（REQ 裁定，2026-11-22，HEAD `7061aa22`）：std 0.20.0 已发布 `CharStr` 且无旧名别名；本仓仍 pin 0.19.0，必须与 pin 升级同一次原子迁移。触发条件与最小迁移清单见 §裁定** |

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

## §裁定（REQ，2026-11-22，HEAD `7061aa22`）：deferred

**裁定：`deferred`**（不是 `rejected`，也不是 `verified`）。延后的是**执行时点**，不是方向：
std 0.20.0 已把单元改名为 `CharStr` 且不留旧名别名，本仓仍 pin `0.19.0`；迁移必须与 pin
升级同一次原子完成，当前没有承载它的窗口。

### 依据

1. **包侧既成事实**（只读核对，不代改）：std 0.20.0 的 `std/str/` 只有
   `CharStr.m.ct` / `CharStr.shim.h`；`String.m.ct` / `CStrOps.m.ct` 都不在；旧导入对 0.20.0
   直接失败（`cannot resolve import 'std/str/String'`），`CHANGELOG` 明示不留兼容别名。
   → 本卡原「兼容」行与验收 2/7（旧 `String.m.ct` 保留一个 MINOR、一个 MINOR 后另立清理 issue）
   被包侧决定推翻。按 9.8 DB-5 / 9.10 CF-1，本仓**不要求也不代改** std 包补别名；是否补由包侧决定。
2. **本仓仍 pin `0.19.0`**（`selfhost/ct-ast/tool/pkg/Pkg.h.ct:2306-2312`），
   `examples/wave1-demo/src/main.ct:7` 与 `docs/tutorial.md:739` 仍写旧名。pin 未升时把示例/文档
   改成 `CharStr` 会与 0.19.0 的包内容不一致（0.19.0 没有该单元）；只升 pin 不迁移，示例立刻编译失败。
   → 必须一次原子迁移，不能按普通文档修订拆开。
3. **为何不 `rejected`**：`rejected` 表示「旧名继续支持 / 本卡不采纳」。但 0.20.0 已删除旧名，
   一旦 pin 升到 0.20.0 旧名必然失效，本卡的目标（新名 `CharStr`）成立；只是不能在
   当前 fix 窗口里夹带一次依赖升级 + 消费者迁移。故 `deferred`，并把触发条件写死。

### 验收改写（取代原验收 2、7）

- 验收 2：**不再是**「旧导入在兼容窗内仍可用」。改为：std 0.20.0 无旧名别名；迁移后
  `import std::str::String;` 必须失败（`cannot resolve import 'std/str/String'`），
  文档不再承诺兼容窗。
- 验收 7：**不再需要**「一个 MINOR 后移除 `String.m.ct`，另立清理 issue」；改为一次原子迁移完成，
  旧名在可运行示例、推荐写法、测试 pin 中同时清零。
- 验收 1、3、4、5、6 不变（新名可用；无 `CStrOps` 残留；包版本/索引/verify；消费者迁移；内置类型不动）。
- 决策表「兼容」行按包侧 0.20.0 决定废止；本仓不以任何形式要求 `String.m.ct` 兼容别名。

### 触发条件（先到者，写死）

| # | 触发 | 必须动作 |
| --- | --- | --- |
| T1 | **`v1-PH-0` 开卡提交之前**（主触发；硬兜底：v1.0 发布检查表之前） | 同一提交完成下面「最小迁移清单」全部条目；REQ 在开卡前核对，未完成不开卡（G1 拦） |
| T2 | 任何把 `pkg_pin_lookup` 的 std 行改为 `>= 0.20.0` 的提交 | 该提交必须已含全部迁移条目（原子），否则不合并 |
| T3 | std 侧若自行发布 `std::str::String` 兼容单元/别名（本仓不请求） | 本仓在下一 MINOR 内删除旧名引用，不延长兼容承诺；T1 仍然有效 |

> 当前 T1/T2/T3 均未触发，故 `deferred`。到达任一触发即转 `open` 交 DEV 执行；完成后由 REV
> 按改写后的验收复核，再转 `verified`。日期兜底：不晚于 v1.0 发布检查表。

### 最小迁移清单（执行时逐条验收）

| # | 落点 | 动作 |
| --- | --- | --- |
| 1 | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:2306-2312` | `pvers` 0.19.0→0.20.0、`ptags` v0.19.0→v0.20.0、`pshas` 换成发布索引的 0.20.0 digest（复核记录为 `sha256:60d2e7dd157facc775e80d45e6769c4f2bfe7273feed6af7ccba9676d8ae42a7`，执行时以 `ct index verify` 通过的索引行为准）；同步 `:458`、`:1174` 的 `ct/std@0.19.0` 注释 |
| 2 | `examples/wave1-demo/src/main.ct:7` | `import std::str::String;` → `import std::str::CharStr;` |
| 3 | `docs/tutorial.md:723/739`、`docs/std-catalog.md:8/32/39/69/72-74`、`docs/language-spec.md:146/2012/2640`、`docs/stable-subset.md:46` | pin 示例 0.19.0→0.20.0；旧导入名→`CharStr`；删除「下一 MINOR / 待发版 / 旧名一个 MINOR」等已失效承诺；§5.1 保留名行同步为 `std::str::CharStr.len` |
| 4 | `docs/idioms.md:43/112`、`docs/guide-for-c-programmers.md:60/114/122/161` | 已写 `CharStr`，删除「0.19.0 及以前叫 `String`、旧名一个 MINOR 回退」的兼容暗示（保留历史说明可以，但不得暗示旧名仍可用） |
| 5 | `docs/ct-pkg.md:42`、`docs/ct-pkg-index.md:39`、`docs/llm-guide.md:48`、`docs/package-guide.md:168/253`、`README.md:13` | pin 值/索引样例/安装示例 0.19.0→0.20.0；README 的弃用窗口列表把 `CharStr`（新名）改为旧名 `std::str::String` |
| 6 | `docs/planning/j6-evidence/ledger.md:58/89/90/92`、`issues/selfhost/sh104-j6-evidence-ledger.md:74` | 「std 新版本未发 / 包侧阻塞」改为 0.20.0 已发布、迁移随本卡；P-6 状态按实际重评 |
| 7 | `test/ast/p77_external.sh:85`、`p77_docs.sh:35`、`p77_install.sh:25-27`、`p77_bare.sh:60/67/178`、`p77_migrate.sh:52/98/110`、`test/ast/pkg23_git_diag.sh:46/97`、`test/ast/p83_verify.sh:38` | pin/索引/文档断言从 0.19.0 改 0.20.0；`p77_external.sh` 的发布索引比对改用 0.20.0 行 |
| 8 | 版本与提交 | 一次提交（T2）或 `v1-PH-0` 的一个 stage（T1）；版本位按 6.7 V-2/V-4：引用本卡的 fix 才 +PATCH，纯文档迁移不得单独 +PATCH；不夹带内置 `String`/`Str`、DOC-87 |

执行后验收命令（写死）：

```console
$ ct get ct/std@0.20.0                             # 落到 0.20.0 store
$ ct index verify <官方索引>                        # OK
$ ct build -I … examples/wave1-demo/src/main.ct    # exit 0，运行通过
$ import std::str::String; 负例                     # 必须 cannot resolve import 'std/str/String'
$ bash selfhost/check-all.sh                        # 11 门绿
$ python3 test/docs/check-docs.py                   # 绿
```

owner：REQ（本裁定）/ DEV（pin + 示例 + 文档 + 测试）；P2。执行时若发现清单外的新落点，
补进本表后再做，不得留旧名到迁移提交之后。
