# 核查记录 · 内置层 `lib/std` 与 ct-pkg `std` 同名

- 日期：2026-11-15
- 基线：`v0.53.1`（HEAD `271e9e2d` 后重建 `ctc`，`/tmp/cthead/ctc`）；外部包 `/Users/samxx/trae-ws/std`
- 范围：只查证与影响面，不改实现、不开 phase 卡

## 0 结论

**当前不冲突**：内置层占用**根命名空间**（无 `namespace` 声明），外部包占用 `std::*`；
`import std::Vec` 不可解析，`import std::str::String` 与内置 `Str` 可在同一程序共存。
共用的是**目录/包名「std」这个词**，不是符号表里的名字。

## 1 是否真冲突

| 子问题 | 结论 | 证据 |
| --- | --- | --- |
| 内置层占什么命名空间 | **根命名空间**（裸名 `Vec` / `Map` / `Option` / `Result` / `Str`） | `lib/std/*.ct` 全部无 `namespace`；[Vec.h.ct:19-20](../../lib/std/Vec.h.ct#L19-L20)「Root namespace on purpose: the layer is pre-parsed, not imported … (D29-3)」 |
| 外部包占什么命名空间 | `std::<模块>` | `String.m.ct:47`、`Fs.m.ct:29`、`Io.h.ct:19`、`Num.m.ct:28`、`Test.h.ct:27` 等（外部仓文件，本仓不复制） |
| 同名单元 | **没有** | 内置：`Vec`（含 `Map`/`MapEntry`）、`Option`、`Result`、`Str`；外部：`Arena`、`Fs`、`File`、`Io`、`Stdout`、`Math`、`Real`、`Num`、`String`、`Test`、`Utf8Ops`（`std/str` 无 `Str` 结构体，见 `String.m.ct:9-11`） |
| 命名空间首段 | **不撞**：内置是根，外部是 `std` | 同上；`std` 只作为外部包的命名空间首段出现 |
| `import std::...` 解析歧义 | **无歧义**：内置单元不可 import | 实测 `import std::Vec;` → `ctc: cannot resolve import 'std/Vec'`（`-I <外部 std 仓>`，`CT_STD_DIR` 指内置层） |

### 实测（`/tmp/ctname`）

```text
t1: import std::Vec;            -> cannot resolve import 'std/Vec'
t2: import std::str::String;
    "abc".len()                  -> 3
t3: import std::str::String; + Str s = str_from("abc"); + str_len(s)
                                  -> 3 3      （两者共存，无冲突）
```

### 唯一的撞法（边界）

`-I` 指向内置层父目录时，`import std::Vec` / `import std::Str` 能解析到同一个文件；
`load_unit` 按路径去重（[Module.h.ct:476-478](../../selfhost/ct-ast/frontend/module/Module.h.ct#L476-L478)），
实测 `-I /Users/samxx/trae-ws/ct-lang/lib` 下 `t4` / `t5` 正常编译。
**只有** `CT_STD_DIR` 与 `-I` 指向两份不同副本时才会重复加载；属配置错误，不是默认路径。

另一个潜在撞点：外部包若新增 `std/Vec.h.ct` / `std/Map.h.ct` / `std/MapEntry.h.ct`，
会被内置名守卫拒绝（[Parser.h.ct:2161-2168](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2161-L2168)）；
`Str` / `Option` / `Result` 不在该守卫里，会落到重复声明诊断。

## 2 内置层改名 `core` 的牵连面

### 2.1 编译器（硬编码）

| 位置 | 内容 | 性质 |
| --- | --- | --- |
| [Module.h.ct:436](../../selfhost/ct-ast/frontend/module/Module.h.ct#L436) | `getenv("CT_STD_DIR")` | 可做别名兼容 |
| [Module.h.ct:443](../../selfhost/ct-ast/frontend/module/Module.h.ct#L443) | 候选 `lib/std/%s` | 可做回退兼容 |
| [Module.h.ct:449](../../selfhost/ct-ast/frontend/module/Module.h.ct#L449) | 候选 `%s/../lib/std/%s` | 可做回退兼容 |
| [Driver.h.ct:103](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L103) | 同上 env | 同上 |
| [Driver.h.ct:121](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L121) / [:127](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L127) | 同上两条候选 | 同上 |
| [Module.h.ct:1525-1528](../../selfhost/ct-ast/frontend/module/Module.h.ct#L1525-L1528) / [Driver.h.ct:110-113](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L110-L113) | 四个单元基名 | **不变**（只是目录改） |
| [Parser.h.ct:2163](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2163) | `strstr(path, "lib/std/")` 豁免 | **硬改**（路径判断） |
| [Module.h.ct:1189-1193](../../selfhost/ct-ast/frontend/module/Module.h.ct#L1189-L1193) | 导出面排除 `Vec_`/`Map_`/`Option_`/`Result_`/`Str` | **不变**（按名字） |
| [Emitter.h.ct:2124](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2124) / [:2145](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2145) | 注释提到 `lib/std` | 只改注释 |

### 2.2 规范与文档（硬改，历史文档不改）

- [language-spec.md:47](../../docs/language-spec.md#L47)（自动加载清单）、[:1926](../../docs/language-spec.md#L1926)（适用范围）、
  [:1941](../../docs/language-spec.md#L1941)（保留名）、[:2390-2392](../../docs/language-spec.md#L2390-L2392)（内置层段落）、
  [:2411-2415](../../docs/language-spec.md#L2411-L2415)（`Map` 键）、[:2546](../../docs/language-spec.md#L2546) / [:2553](../../docs/language-spec.md#L2553)（§4.56）。
- [lib/std/README.md:5-17](../../lib/std/README.md#L5-L17)（范围）、[:28-29](../../lib/std/README.md#L28-L29)（类型表+保留名）、
  [:43](../../lib/std/README.md#L43)（保留名）、[:80-83](../../lib/std/README.md#L80-L83)（`Str`）。
- [README.md:468](../../README.md#L468)、[README.en.md:64](../../README.en.md#L64)。
- 外部包侧也有同类内置层路径写法；逐条引用属外部仓，本仓不复制，记录随包外移交清单分发。

### 2.3 测试与 golden

- 7 个脚本直接用路径：`test/ast/p47_map.sh:31/45/70/101/118/141/144`、`p52_subscript.sh:23/99/124`、
  `p51_dot.sh`、`p49_own.sh`、`p53_optional.sh`、`p48_drop.sh`、`p50_has.sh`；
  `test/probes/p34_check_baseline.sh:118-119`；`test/ast/232_str_own_pointer/prog.ct:3`；
  `selfhost/check-ast.sh:6754/6785`。
- golden：生成的 `.c` / `.h` 用基名（`Vec.h`、`Vec.c`），目录改名不影响；**会变**的是
  `--emit-map` 里的 `file` 路径（SH-79 已规定必须指向输入单元，内置单元路径仍会出现在条目里）。

**兼容做法**：`CT_CORE_DIR` 与 `lib/core` 优先，保留 `CT_STD_DIR` 与 `lib/std` 作回退（一个 MINOR 的弃用窗）；
规范/测试/文档是硬改。

## 3 方案取舍

| 方案 | 代价 | 兼容性 | 下游影响 |
| --- | --- | --- | --- |
| **(a) 内置层改 `core`** | 编译器 4 处搜索 + 1 处路径守卫 + 规范/README + 26 处测试引用 + 转场别名 | 可做到软着陆（旧 env/旧目录回退） | 不影响 `import std::...`；只影响依赖 `CT_STD_DIR`/同级 `lib/std` 的工程 |
| **(b) 外部包改名 `base`/`commons`** | 包名、`ct.pkg`、66 处 `import std::`（`std` 仓自身）+ 下游全部 import + 文档 | **最差**，全局破坏 | 所有已有 `import std::...` 的仓都要改；不建议 |
| **(c) 不改名，文档说清** | 规范一段 + 可选诊断 | **零破坏** | 零；歧义仍留在「std」这个词上 |

## 4 定性与版本落点

- **不是 bug**：现有行为与文档一致（`std` 0.3.0 已删 `std::vec` / `std::map` 避开内置名；
  内置层根命名空间是 D29-3 的明确决定），没有「承诺了却没实现」。
- 按 D-005 属 **B 新需求/命名重构 → phase**，不进 patch；建议排在 **PH-54 之后**（依赖包根与
  `ns-root` 定稿），不占 PH-62 的位（与可写下标无关）。

## 5 建议

1. **先做 (c)**：在规范里给两层定名——「内置层 = `lib/std`，根命名空间，自动加载」与
   「`std` 包 = ct-pkg 包，`std::*`，显式 import」；再给 `import std::Vec` 一条明确诊断
   （现在是 `cannot resolve import 'std/Vec'`，没有解释）。
2. 若确要改名，选 **(a)** 并带兼容别名；**(b) 不推荐**。
3. **如果只做一件事**：把两者的定名与边界写进 `language-spec`（并同步 `lib/std/README.md`），
   同时把 `import std::<内置名>` 的诊断补成可读提示——不动物理路径，零破坏。

## 6 留档声明

- 本记录只做查证，不含实现承诺；
- 未开 phase 卡、未改 `selfhost/**`、未改测试与规范；
- 未 push。
