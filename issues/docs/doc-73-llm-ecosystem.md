# DOC-73 · LLM 生态入口：std / ct-pkg / index

| 项 | 值 |
| --- | --- |
| 模块 | docs（llm-guide / std-catalog / ct-pkg / ct-pkg-index / tutorial / package-guide / glossary） |
| 定性 | 文档补充与口径统一；**不占新 phase** |
| 严重度 | High（LLM 只读本仓会把 std/包全部重造） |
| 优先级 | P0 |
| 状态 | **verified**（2026-11-20，REV） |
| 落点 | 挂 `v0-PH-67` R5「文档漂移审查」，与 DOC-72 同批；可提前做，不阻塞 ID 迁移 |
| 来源 | 用户 2026-11-18 指示：LLM 必须知道 CT 有生态，先复用，不要重写 std 和包 |

## 核心原则

> **LLM 不仅要懂 CT 语法，还要知道 CT 有生态：先查 std / hal / index，再决定是否实现；不要重写标准库，不要复制包源码。**

## 交付物

### P0-1 `docs/llm-guide.md`

固定决策顺序：

1. 语言/语法 → `language-spec`；
2. 容器/字符串/文件/UTF-8/arena/test → 先查 `std`；
3. 硬件 → 先查 `hal` / `hal-posix`；
4. 通用能力 → 先查 `ct-pkg/index`；
5. 都没有 → 才实现；可复用就发布成包，不 vendored。

硬规则：

- `Vec<T>` / `Map<K,V>` 是编译器内置，不要重写；
- `std::str` / `std::fs` / `std::utf8` / `std::vec` / `std::map` / `std::arena` / `std::test` 用 `ct get ct/std`，不要手写替代；
- 别人的包用 `ct get <pub>/<name>`，不要复制；
- 包格式用 `ct.pkg` + `ns-root` + publisher，不要自造。

### P0-2 `docs/std-catalog.md`

薄目录，不复制完整 API：

| 模块 | 用途 | 导入 |
| --- | --- | --- |
| 内置 | 泛型容器 | 免 import：`Vec<T>` / `Map<K,V>` |
| `std::str` | 字符串 | `import std::str::String` |
| `std::fs` | 文件 | `import std::fs` |
| `std::utf8` | UTF-8 | `import std::utf8` |
| `std::vec` | C 映射向量操作 | `import std::vec` |
| `std::map` | C 映射映射操作 | `import std::map` |
| `std::arena` | 区域分配 | `import std::arena` |
| `std::test` | 测试 | `import std::test` |

附：`ct get ct/std@...`、store 路径、完整 API 读安装包内 README。

### P0-3 `docs/ct-pkg.md`

四角色：

| 角色 | 归属 |
| --- | --- |
| 编译器 | ct-lang |
| 标准库 | `ct-pkg/std` |
| 平台包 | `ct-pkg/hal` / `hal-posix` |
| 索引/发布 | `ct-pkg/index` |

写清：CT 仓不内置 std；`ct get` 是消费入口；`package.sh` 是发布入口，不是 `ct` 内置；`ct pkg check` 是过渡，不是长期 API。

### P1 `docs/ct-pkg-index.md`

区分 current / target：

- 当前官方 index 五字段、无 publisher/签名；
- 六字段是目标/兼容形态；
- `CT_INDEX` / `--index` 显式，不自动联网；
- 发布走 `package.sh` / CI，带 token，不进 `ct`；
- pin/签名未落地前，不声称可信。

### P1 统一现有口径

- `tutorial.md` 的 std 段指向 `std-catalog`，不重复全文；
- `package-guide.md` 补 consumer / publisher / index 三分；
- `glossary.md` 五字段改“当前五字段；六字段目标/兼容”；
- `docs/README.md` 加 Ecosystem 入口，明确 `proposals/` 不是现状。

## 验收

| # | 判据 |
| --- | --- |
| A1 | 问“实现字符串 split” → 回答用 `std::str`，不是手写 |
| A2 | 问“实现 Vec/Map” → 回答用内置泛型，不是重写 |
| A3 | 问“加一个包” → 回答 `ct.pkg` + `ns-root` + publisher，不是复制源码 |
| A4 | 问“索引格式” → 区分当前五字段 / 目标六字段 |
| A5 | 文档中五/六字段不再互相矛盾；`proposals/` 标注非现状 |
| A6 | LLM 能从 `llm-guide` 走到 std/index，不先自己实现 |

## 不做什么

- 不新开 phase；不 bump 版本；
- 不复制 std 全量 API；
- 不改 ct-pkg/index 仓；
- 不把发布脚本写进 `ct`；
- 不把 `proposals/` 当 current。

## 落点

- **不占 phase**；挂 `v0-PH-67` R5，与 DOC-72 同批。
- 可先做 P0 三份短文档，不等 ID 迁移。

## 处置（2026-11-20，DEV #2）

范围：只新增/修订文档与本文处置；**不新开 phase、不 bump 版本、不改 ct-pkg 仓、不把发布脚本写进 `ct`**。
计数与字段形态全部按 2026-11-20 实测回填，不照抄 issue 写作时的旧前提。

### 交付物

| # | 结论 | 落点 |
| --- | --- | --- |
| P0-1 `docs/llm-guide.md` | **fixed** | 新建 [llm-guide](../../docs/llm-guide.md)：固定决策顺序（language-spec → std → hal → index → 才实现）、H1–H7 硬规则、需求→先查哪张表、最小命令、四个判断示例（含「split → `std::str` 的 `split_into`」）、文档地图 |
| P0-2 `docs/std-catalog.md` | **fixed** | 新建 [std-catalog](../../docs/std-catalog.md)：内置层（`Vec`/`Map`/`MapEntry`/`Option`/`Result`/`Str`，免 import）+ `std` 16 个模块的用途与入口 `import`；完整 API 指向包内 `std/<mod>/README.md`；含 store 路径与「包内无 tutorial.md」的事实 |
| P0-3 `docs/ct-pkg.md` | **fixed** | 新建 [ct-pkg](../../docs/ct-pkg.md)：四角色表（编译器 / `ct/std` / `hal` + `hal-posix` / 索引）、本仓不内置 std、消费/发布/索引/preflight 四条边界、当前可解析范围 |
| P1 `docs/ct-pkg-index.md` | **fixed（并按实测修正前提）** | 新建 [ct-pkg-index](../../docs/ct-pkg-index.md)：六字段现行、五字段旧行只读兼容且不可安装；`--index`/`CT_INDEX` 显式；索引无签名、pin/签名未落地；发布走索引仓 `tools/package.sh` + CI；`proposals/` 标注为目标形态 |
| P1 tutorial std 段 | **fixed** | [tutorial §10](../../docs/tutorial.md#10-标准库std)：加 std-catalog 指针；删掉过期的 `std::vec` / `std::map` 与「每模块一对 README/tutorial」表（std 0.3.0 已删 vec/map；0.19.0 包内无 tutorial.md） |
| P1 package-guide | **fixed** | [package-guide §0](../../docs/package-guide.md)：新增「消费者 / 发布者 / 索引」三角色表；§4 索引段补五字段旧行「可解析、不可安装」边界 |
| P1 glossary | **fixed（并顺带修正相邻过期项）** | [glossary](../../docs/glossary.md)：索引仓库改六字段现行/五字段只读；`ct.pkg` 改 `publisher`/`ns-root`/`c-boundary` 等现行键；`ct.lock` 改 v2 七字段且 `ct build` 默认读取；包根/`ns-root` 去掉「目标形态、当前不存在」；C 映射包改为 16 模块口径；新增 `$` 条目 |
| P1 docs/README | **fixed** | [docs/README](../../docs/README.md)：新增「生态：先复用，别重写」入口表（llm-guide / std-catalog / ct-pkg / ct-pkg-index / package-guide），并明确 `proposals/` 是提案、不是现状 |

### 验收判据

| # | 结论 | 说明 |
| --- | --- | --- |
| A1 | **fixed** | llm-guide §5：问「字符串 split」→ 先看 `std::str` 的 `split_into`（实测存在于 `std/str/String.shim.h`），不要手写 |
| A2 | **fixed** | llm-guide H1 + std-catalog §1：`Vec`/`Map`（以及 `Option`/`Result`/`Str`）是内置层，免 import，不重写 |
| A3 | **fixed** | llm-guide H4 + ct-pkg §3：包格式 `ct.pkg` + `publisher` + `ns-root`；发布走索引仓脚本，不复制源码 |
| A4 | **fixed（前提已按实测更正）** | issue 写作时（2026-11-18，v0.65.1）的「当前五字段、六字段是目标」已被 PH-77 的 S5/E77-8（v0.77.0）取代：实测官方索引 `std` 行是**六字段**，索引里五字段旧行仍可解析但没有 `publisher`、不能落 store。文档按「六字段现行 / 五字段旧行只读兼容」表述，不再写反 |
| A5 | **fixed** | 五/六字段口径已在 ct-pkg-index / package-guide / glossary 三处统一；`docs/README` 与 ct-pkg-index 都明确 `proposals/` 不是现状 |
| A6 | **fixed** | llm-guide §6 文档地图从 language-spec → std-catalog → ct-pkg / ct-pkg-index / package-guide / tutorial 可直接走通 |

### 实测命令与原始输出

```console
$ curl -fsSL --max-time 10 https://raw.githubusercontent.com/ct-pkg/index/master/index -o /tmp/ct-index.txt
$ awk 'NF{print NF}' /tmp/ct-index.txt | sort | uniq -c
  10 5
  10 6
$ grep '^std ' /tmp/ct-index.txt
std 0.19.0 ct https://github.com/ct-pkg/std v0.19.0 sha256:432086f0ec6c9ef3cdce5e24d465924d207e81d04f97595518d6e7d584ddaa79

$ git clone -q --depth 1 --branch v0.19.0 https://github.com/ct-pkg/std /tmp/std019
$ grep -c '^| `std::' /tmp/std019/std/README.md
16
$ find /tmp/std019/std -mindepth 1 -maxdepth 1 -type d | wc -l
20          # 16 个有 README 的公开模块 + mmap/poll/posix/thread 四个无 README 的内部单元

$ grep -n 'publisher' /tmp/ctindex/tools/gen-index.sh
60:publisher=$(manifest_value publisher)
65:[ -n "$publisher" ] || die "'$dir/ct.pkg' is missing 'publisher' (required since ct v0.54)"
107:    "$name" "$version" "$publisher" "$url" "$tag" "$digest" >>"$tmp"

$ .temp/p77/ct-ast -v
ct-ast v0.77.1
$ cd .temp/ioprobe && ../../.temp/p77/ct-ast build m.ct -I /tmp/std019 -o out   # m.ct: import std::io::Stdout;
$ echo $?
0
# 同法实测 std-catalog 的 16 个入口（io::Stdout / io::File / fs::Fs / utf8::Utf8Ops / num::Num /
# math::Real / search::Search / arena::Arena / test::Test / env::Env / process::Process /
# errno::Errno / locale::LocaleHandle / wchar::Wchar / time::Time / net::Socket）逐个 import + build，
# 全部 rc=0（证明 .m.ct 可被 import，且入口名可解析）

$ HOME=/tmp/halprobe CT_HOME=/tmp/halprobe .temp/p77/ct-ast get ct/hal
ctc: no index resolver for 'ct/hal'
  'ct/hal' is a publisher-qualified package name; the built-in
  pins cover the official packages only (ct/std).
$ echo $?
1
# pin 表只有 std：grep -n 'pnames\[\]' selfhost/ct-ast/tool/pkg/Pkg.h.ct
# 2015:    static const char *const pnames[] = { "std" };
```

验证：`python3 test/docs/check-docs.py` → OK；`bash tools/check.sh g0` → OK（原始输出见 [DOC-72 处置](doc-72-spec-audit-followup.md#处置2026-11-20dev-2)）。

## 复核（2026-11-20，REV）

**结论：verified**（无 deferred 子项）。

```console
$ for f in docs/llm-guide.md docs/std-catalog.md docs/ct-pkg.md docs/ct-pkg-index.md; do
    printf '%s %s lines\n' "$f" "$(wc -l <"$f")"; done
docs/llm-guide.md 83 lines
docs/std-catalog.md 85 lines
docs/ct-pkg.md 55 lines
docs/ct-pkg-index.md 74 lines
$ grep -n 'llm-guide\|std-catalog\|ct-pkg-index' docs/README.md | head
33:### 生态：先复用，别重写
37:| [llm-guide.md](llm-guide.md) | ...
38:| [std-catalog.md](std-catalog.md) | ...
$ grep -n 'std-catalog' docs/tutorial.md
719:模块清单、入口 `import` 与完整 API 入口见 [std-catalog](std-catalog.md)；...
$ grep -n '三个角色' docs/package-guide.md
14:### 0. 三个角色：消费者 / 发布者 / 索引
```

A4 的前提「六字段现行 / 五字段旧行只读」独立复核（2026-11-20 拉取官方索引）：

```console
$ curl -fsSL --max-time 12 https://raw.githubusercontent.com/ct-pkg/index/master/index -o /tmp/rev-index.txt
$ awk 'NF{print NF}' /tmp/rev-index.txt | sort | uniq -c
  10 5
  10 6
$ grep '^std ' /tmp/rev-index.txt
std 0.19.0 ct https://github.com/ct-pkg/std v0.19.0 sha256:432086f0ec6c…
```

内置 pin 表与 std 目录也一致：`Pkg.h.ct` 的 `pnames/pvers/ptags` 为 `std / 0.19.0 / v0.19.0`；
`/tmp/std019/std` 下 20 个目录、README 16 个公开模块，与 std-catalog 的「16 模块」口径一致。
四份新文档与 tutorial/package-guide/glossary/docs-README 的链接均通过 `check-docs`（1990 条
相对链接、329 文件）；`docs/README.md` 明确 `proposals/` 不是现状。A1–A6 的入口可走通。
