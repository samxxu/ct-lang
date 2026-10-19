# Phase 6 设计（已冻结）：生态与扩展

> 中文 · [English](#english)
>
> **状态：设计已冻结（2026-10-17）。** D15–D20 均按推荐项拍板。Phase 6 是**扩展类**，
> 无归档 oracle：出口 = **设计冻结 + 新用例 + `./test/run.sh` 与 `bash selfhost/check-all.sh` 全绿**。
> **收口（2026-10-17）**：6.1–6.4 与 6.6 已落地，6.5 `map` 仅设计冻结；版本 bump 至 **v0.6.0**，
> 全量 golden 已按新版本重生成。
>
> 现有约束：`MAX_FUNCS` 余量 **1**；`Pipe` 字段 **31/32**；`PipeOps` **31/32**。
> Phase 6 的新逻辑必须走 `impl` 方法；新状态优先放进 `SymTab` 或新的轻量对象，**不要**继续加 `Pipe` 字段。

---

## 中文

### 1. 范围与推进顺序（D15）

| 切片 | 内容 | 依赖 |
| --- | --- | --- |
| 6.1 | **反向映射表**：`--emit-map <file|->` 输出符号表 JSON（trait / struct / function / impl 方法 → 生成的 C 符号） | 无 |
| 6.2 | **调用图 + 跨函数泄漏分析**：在 6.1 的映射上记录调用边，并沿调用边传播「返回值是否转移所有权」 | 6.1 |
| 6.3 | **增量编译缓存**：按单元缓存 `.c/.h`，命中即跳过重新生成 | 无（driver 层） |
| 6.4 | **多目标编译**：先限定为 C 标准 / cc 兼容性（`--std=c99|gnu99` 一类的产物差异），跨平台与多架构推迟 | 6.3 可并行 |
| 6.5 | **`map` + 官方 bindings**：本阶段只冻结设计；bindings 清单出现后再实现（D8：最后） | 6.1 |
| 6.6 | **方言系统**：展开器保持在仓库外；实现时修订 AGENTS §2 的三条边界 | 6.1（sourcemap） |

理由：反向映射表是插件跳转、方言 sourcemap、`map` 三处的共同底座；跨函数分析是 Phase 5 的自然延伸；
增量与多目标属构建层，可独立推进；`map` 与方言依赖外部消费者与规约修订，放最后。

### 2. 6.1 反向映射表（D16）

CLI：`--emit-map <file>`；`-` 表示写 stdout（compile 模式推荐；build 模式下 stdout 已被 cc 命令占用，
请写文件）。只在编译**成功**后写出；失败不产出。

JSON 形状（v1）：

```json
{
  "compiler": "ct v0.6.0",
  "file": "prog.ct",
  "traits":  [{"name":"Greeter","cname":"Greeter","file":"prog.ct","line":3,
               "methods":[{"name":"greet","ret":"void","params":0}]}],
  "structs": [{"name":"Person","cname":"Person","file":"prog.ct","line":5,
               "uses":["Greeter"]}],
  "functions":[{"name":"add","file":"prog.ct","line":11,"ret":"int","params":2}],
  "impls":   [{"struct":"Person","trait":"Greeter","method":"greet",
               "symbol":"Person_Greeter_greet","ret":"void","params":0,
               "file":"prog.ct","line":7}]
}
```

> 6.2 起在 `impls` 之后追加 `"calls"` 段（见 §3），其余形状不变。

数据来源与改动点：

- `Trait` 增 `def_line` / `file`；`parse_trait` 记录。
- `Struct` 已有 `def_line`，增 `file`。
- `FuncSig` 增 `line` / `file` / `ret`（返回类型拼写）；`parse_func_sig` 记录，并按名字**就地更新**
  重复签名（与 `find_func` 的「最后一个生效」一致）。
- `SymTab` 增一个 plain-C `ImplEntry` 表（`struct/trait/method/symbol/ret/params/line/file`）；
  `parse_impl` 在收集完方法后登记。`impl Drop` 也登记为 `trait: "Drop"`。
- `SymTabOps::write_map(FILE *)`（impl 方法）负责写文件；导出面走 `ct_compile_file` 新增的
  `map_path` 参数（现场记录见下方「落地记录」）。
- 已知 v1 限制：不列**标量字段**（符号表只记录 struct/接口字段）；不列 `namespace` 的独立节点，
  但 `cname` 已含前缀；`line` 是定义行。

**落地记录（2026-10-17，切片 6.1）**：

- 写入口改为 `ct_compile_file(..., const char *map_path, const char *root)`，**不新增** `pub ct_write_map`——`MAX_FUNCS`
  只剩 1 个签名余量，本阶段约束要求新逻辑不消耗它。map 只在编译成功后写出；`build` 只把路径交给
  **最后一个单元**（此时整张符号表已填满），且 `-` 在 `build` 下被挡下（stdout 留给 cc 命令）。
- `structs[].uses` 在源码写了 `Drop` 时一并列出（符号表把 `Drop` 存成标记而非 use 条目，map 按源码还原）。
- 顶层 `"file"` 取本次运行**命令行上的第一个输入**（`build` 依赖先行编译，首个单元不是根，故由 driver 显式传入）；每个条目的 `file` 指向定义它的单元。
- fixture：`test/modules/map/`（compile，`--emit-map -`），`expected.stdout` 钉 JSON、`expected.out` 钉程序输出。

### 3. 6.2 调用图与跨函数泄漏分析

- 调用图：`"calls": [{"caller":"main","callee":"add","file":"prog.ct","line":15}]`。
  `caller` = 当前所在函数 / 方法名（顶层代码记 `<file>`）。
- **落地实现**：`SymTab` 增 `CallEdge` 表（`MAX_CALLS`）与 `cur_func`；**未新增 `Pipe` 字段**——
  函数体边界用既有的 `nscope`（普通函数）与 `in_body`（impl 方法）判定，`Pipe` 余量保持 31/32。
  边只记**直接调用** `name(...)` 且 `name` 已有签名（C 要求先声明后使用，这也自动滤掉关键字与
  libc 调用）；`.m()` / `->m()` 是动态派发，没有单一被调者，不记。impl 方法作为调用方时用生成符号
  （与 `impls[].symbol` 一致）；同一行同一对 caller/callee 去重。
- 跨函数泄漏：函数 `f` 在**自身层级**无条件 `return p;` 且 `p` 是它拥有的堆对象时，记一条事实
  `ret_owned[f] = 1`；调用方在**声明初始化** `T *q = f();` 且 `f` 返回同一 struct 指针时，把 `q`
  视为 owned，未释放则在作用域出口报泄漏。条件 return 不产生事实；`q = f();`（赋值而非声明）、
  别名、参数与容器都不跟踪。
- 保守口径：事实按函数本地记录（不做全程序数据流 / 别名分析）；`f` 若把从 `g()` 得到的对象继续
  `return` 出去，`f` 也会被记为可能转移——传递的是事实，不是跨函数求解。

### 4. 6.3 增量编译缓存（D17）

- 键：`(输入路径, mtime, size, 编译器版本, 关键选项)`；v1 不做内容哈希（成本/收益不划算）。
- 命中：`.c/.h` 已存在且键一致 → 跳过生成，保留旧产物（`#line` 与告警不重放；文档写明）。
- 缓存位置：`<outdir>/.ctcache/<unit>.key`；`build` 专用，单文件 `compile` 不缓存。
- 失效：源文件、`-I` 依赖、`--line/--no-line`、`--diagnostics` 任一变化即未命中。

**落地记录（2026-10-17，切片 6.3）**：

- 键 ≈ `ctc <版本> L<line> D<diag> N<ns_root> P<路径> S<mtime.size> I<导入名 digest> K<依赖 fold>`。
  `-I` 根**不直接入键**——它只能改变某条 `import` 解析到哪个文件，而解析结果已体现在该依赖自身的键里。
- 新增 `trait CacheOps` + `impl CacheOps for Build`（5 个方法，`struct Build` 加 `use CacheOps`）：
  `MAX_FUNCS` 只剩 1 个顶层签名余量，故缓存逻辑**不落**普通函数，落 impl 方法（precedent：`PipeOps` /
  `RewriteOps`）。`digest` 等不引用接收者的方法保留 `(void)self;`（否则 L2 会有 `-Wunused-variable`）。
- **命中不重放**：键一致即视为产物仍有效，`#line` 与告警不重放；`--emit-map` 时**一律不命中**（map
  覆盖整轮运行，跳过的单元会缺席），但键仍计算并落盘，保证依赖 digest 不为陈旧值。
- **安全规则（对 §4 的强制细化）**：`build` 的符号表**跨单元累积**，被跳过的单元其符号不进表，故
  重编译集 = `order` 的**前缀**（自首个未命中单元起向前全部重编，供其后单元查符号）**∪** 变更传播
  闭包（依赖键折叠进下游键，依赖变则下游全变）。因此全树未变才整轮跳过，否则至少前缀重编。
- 依赖键只折叠定宽 **digest**（FNV-1a），键长不随 `import` 链深指数膨胀；`stat` 失败或键溢出一律
  返回「无键」→ 必须重编译，绝不静默截断。写键失败静默（只损失一次重建，绝不破坏构建）。
- 新增 `#include <sys/stat.h>`（POSIX `stat` / `mkdir`，非第三方依赖）；L1 只需透传，不动点不受影响。
- 断言位置：`ct-tour.sh` 第 8 步（`cachesrc` 副本树两次 `build`，回写旧 `mtime` 后验「未被重写」，
  再 `touch -t` 触源验失效）——`test/modules/` 的 designed 用例只跑一次 `build`，表达不了「二次命中」。

### 5. 6.4 多目标编译（D18）

v1 只定义**C 方言目标**：`--std=c99`（默认）与 `--std=gnu99`，差异限定在少数需要 GNU 扩展的发射点
（目前代码里没有；若无可差异点，本切片只落 CLI 与 `cc` 建议命令里的 `-std=`）。
跨平台（Windows / MSVC）、多架构、交叉编译**推迟**到后续阶段。

**落地记录（2026-10-17，切片 6.4）**：

- 接受 `--std=c99`（默认）与 `--std=gnu99`；其他值一律硬报错 `unknown C standard '<v>'`（退出 1）。
- **产物零差异**：暂无可差异发射点，故 `compile` 只校验并接受该开关（不打印 cc 命令，无可见影响）；
  `build` 把 `-std=<std>` 放在建议命令的最前面（`cc -std=gnu99 core.c driver.c -o a.out`）。
  默认也显式写出 `-std=c99`，让建议命令自带完整信息、可被断言。
- fixture：`std_default` / `std_gnu`（build，`expected.stdout.contains` 钉字面量——建议命令含绝对
  输出目录，无法逐字节比对）、`std_bad`（compile 负例）。为此 `check-archive.sh` 第 7 组新增可选的
  `expected.stdout.contains`（每行一个字面量，全部须出现）。

### 6. 6.5 `map`（D19）

本阶段只做设计冻结（`map trait T for instance x { m() → CALL; }` → vtable 条目 + 反向映射条目）。
**不实现**，直到官方 bindings 清单出现；避免用想象用例把实例语义定死。

> **更新（2026-10-19，D19 解除）**：`map` 已从「设计冻结」解冻，立为 **Phase 11** 并在 **ct-ast** 主线落地
> 切片 **11.1**——解析 `map trait T for instance x { … }`、发射实例级包装函数 `<inst>_<Trait>_<method>` 与
> `<inst>_<Trait>_vtable`、`--emit-map` JSON 新增 `maps` 字段；切片 **11.2** 已把映射实例**接入派发**
> （装箱用实例级 vtable，未 `use` 该 trait 的 struct 亦可作为其实例运行）。
> 实际语义与产物命名以 [language-spec](../language-spec.md) §4.10 与 [roadmap](../roadmap.md) 的 Phase 11 为准；
> 本节保留当时的设计冻结记录。

### 7. 6.6 方言系统（D20）

- 展开器是**仓库外**的独立脚本（bash / Python / awk，作者自选语言），编译器零感知；因此 AGENTS §2 的
  「不引入代码生成脚本」指的是**仓库内**的编译器构建管线，方言展开器不在此列——**豁免已在 AGENTS §2
  落地**（中英双语，2026-10-17，切片 6.6）。
- 插件仍**不调用编译器**；`--watch` / 自动 expand 推迟，插件只消费 6.1 的映射 JSON。
- 包管理分发方言不在本阶段。

**落地记录（2026-10-17，切片 6.6）**：

- **AGENTS §2 豁免**：方言展开器在**仓库外**、`ctc` **零感知**（永不调用展开器、永不内置方言）；
  仓库内**只允许**在 `examples/**`（演示）与 `test/**`（测试）下携带方言源与插件，约定目录
  `ct-dialects/`、文件名 `<名字>.sh`（`/` 换 `-`），且**不得**成为编译器构建步骤。AGENTS §6 的
  「七层覆盖」随之改为「八层」（新增 `dialect` 层）。
- **可运行演示**：`examples/07_dialect/`——`registry.ct` 把寄存器表写成 `//@` 注释，插件
  `ct-dialects/register-map.sh`（POSIX sh + awk，零依赖）展开出 trait / struct / impl 与偏移宏；
  `test/run.sh` 新增 `dialect` 层：展开 → `ctc` → `cc` → 运行 → 与 `.expected.out` 比对，并额外
  **断言未展开的源无法直接编译**——这正是「编译器零感知」的证明。examples 层按 `ct-dialects/`
  目录存在与否跳过该目录。
- **布局**：插件不放在仓库根（那会暗示编译器自身用方言），而是放在演示项目自己的 `ct-dialects/`
  下，与 [dialect.md](dialect.md) §4.3 的项目级布局一致；包管理分发方言仍不在本阶段，未预留任何
  下载目录名。
- **验证**：`./test/run.sh` 118/118、`bash selfhost/check-all.sh` 全绿、手工三件套通过；**编译器与
  CT 线零改动**（本切片不动 L0 / L1 / L2）。
- **收口（2026-10-17）**：版本按阶段规范 bump 到 **v0.6.0**（`ctc.c` / `selfhost/ctc.ct` /
  `selfhost/src/{core,driver}.ct` 四处一致），`test/cases/**` 50 个与 `test/modules/**` 51 个
  golden（含 `map/expected.stdout`）按新版本重生成；归档 oracle 由 `same_modulo_version` 归一化。

### 8. 测试与验收

- 6.1：新 designed fixture `map/`（compile，`--emit-map -`，`expected.stdout` 钉 JSON，
  `expected.out` 钉程序输出）。
- 6.2：`calls` 形状 + 跨函数泄漏的正/负例（`test/modules/leak_call/`）。
- 6.3：`build` 两次运行，第二次命中缓存（产物时间戳不变 / 缓存计数日志）。
- 6.4：CLI 与建议命令的断言（无产物差异时只钉参数）。
- 每片后跑：`./test/run.sh`、`bash selfhost/check-all.sh`、手工三件套。

### 9. 决策点（2026-10-17 已拍板）

| 编号 | 问题 | 决定 |
| --- | --- | --- |
| **D15** | 推进顺序 | ✅ 反向映射表 → 调用图/跨函数分析 → 增量缓存 → 多目标 → `map` → 方言 |
| **D16** | 映射表形态 | ✅ `--emit-map <file|->` 输出独立 JSON，不塞进 `--diagnostics` |
| **D17** | 增量缓存键 | ✅ `路径 + mtime + size + 版本 + 关键选项`，v1 不做内容哈希 |
| **D18** | 多目标含义 | ✅ 先只做 C 标准 / cc 兼容性；跨平台推迟 |
| **D19** | `map` 何时实现 | ✅ 本阶段只冻结设计，等官方 bindings 清单（**2026-10-19 解除：Phase 11 落地 11.1**） |
| **D20** | 方言规约冲突 | ✅ 展开器留在仓库外；实现时修订 AGENTS §2（明确豁免 + 插件不调编译器） |

---

## English

### Scope and order (D15)

1. **Reverse mapping table** — `--emit-map <file|->` emits a symbol-table JSON (traits, structs,
   functions, and impl methods → their generated C symbols). It is the common base for editor
   navigation, the dialect sourcemap and `map`.
2. **Call graph + cross-function leak analysis** — record call edges on top of 6.1 and use them to
   propagate "does the callee return its allocation?" conservatively (one level only).
3. **Incremental compilation cache** — key `(path, mtime, size, version, relevant options)`; a hit
   reuses the existing `.c/.h` (no content hashing in v1; `build` mode only).
4. **Multi-target** — v1 defines only the C dialect target (`--std=c99` / `--std=gnu99`); cross-platform
   and cross-architecture are deferred.
5. **`map`** — design frozen only; implement after an official bindings list exists (D8 says last)
   — **lifted on 2026-10-19: Phase 11, whose 11.1 slice has landed on the ct-ast mainline**.
6. **Dialect system** — the expander stays **outside** the repository; implementing it requires an
   explicit AGENTS §2 exemption and keeps the editor from calling the compiler.

### 6.1 JSON shape (D16)

```json
{
  "compiler": "ct v0.6.0",
  "file": "prog.ct",
  "traits":  [{"name":"Greeter","cname":"Greeter","file":"prog.ct","line":3,
               "methods":[{"name":"greet","ret":"void","params":0}]}],
  "structs": [{"name":"Person","cname":"Person","file":"prog.ct","line":5,"uses":["Greeter"]}],
  "functions":[{"name":"add","file":"prog.ct","line":11,"ret":"int","params":2}],
  "impls":   [{"struct":"Person","trait":"Greeter","method":"greet",
               "symbol":"Person_Greeter_greet","ret":"void","params":0,
               "file":"prog.ct","line":7}]
}
```

Data-model changes: `Trait` gains `def_line` / `file`; `Struct` gains `file`; `FuncSig` gains
`line` / `file` / `ret`; `SymTab` gains a plain-C `ImplEntry` table filled by `parse_impl`;
`SymTabOps::write_map` writes the file, reached through `ct_compile_file`'s `map_path` argument (see
the landing notes). Scalar fields are not listed in v1.

**Landing notes (2026-10-17, slice 6.1)**:

- The writer is `ct_compile_file(..., const char *map_path, const char *root)`; no `pub ct_write_map`
  was added, since `MAX_FUNCS` has one signature slot left and this phase must not spend it. The map
  is written only after a successful compile, and `build` hands the path to the **last** unit (the
  table is complete by then); `-` is rejected under `build` (stdout carries the cc command).
- `structs[].uses` lists `Drop` when the source wrote it (the symbol table keeps it as a marker, not a
  use entry; the map restores what the source said).
- The top-level `"file"` is the **first input on the command line** (`build` compiles dependencies
  first, so its first unit is not the root — the driver passes it explicitly); each entry's `file`
  names the unit that defined it.
- Fixture: `test/modules/map/` (compile, `--emit-map -`), `expected.stdout` pinning the JSON and
  `expected.out` pinning the program output.

### 6.2 call graph and cross-function leaks

- `"calls": [{"caller":"main","callee":"add","file":"prog.ct","line":15}]` follows `impls`; `caller`
  is the enclosing function, the generated method symbol inside an impl body, or `<file>` at top level.
- Implementation: `SymTab` gains a `CallEdge` table (`MAX_CALLS`) and `cur_func`; **no `Pipe` field was
  added** — the body boundary is derived from the existing `nscope` (plain functions) and `in_body`
  (impl bodies), so `Pipe` stays at 31/32. Only direct `name(...)` calls whose name already has a
  signature are edges (C requires a declaration before use, which also filters keywords and libc);
  `.m()` / `->m()` is dynamic dispatch with no single callee. Edges are deduplicated per line and pair.
- Cross-function ownership: when `f` unconditionally `return p;` at its own level and `p` is a heap
  object it owns, `ret_owned[f]` is recorded; a caller whose **declaration initialiser** is
  `T *q = f();` and whose callee returns the same struct pointer treats `q` as owned, so a missing
  release is reported at the scope exit. Conditional returns produce no fact; `q = f();` (assignment,
  not a declaration), aliases, parameters and containers are not tracked.
- Conservative: facts are recorded per function (no whole-program data flow or alias analysis); an `f`
  that forwards an object obtained from `g()` also becomes `ret_owned` — the fact travels, but no
  cross-function solver runs.

### 6.3 incremental build cache (D17)

**Landing notes (2026-10-17, slice 6.3)**:

- Key ≈ `ctc <version> L<line> D<diag> N<ns_root> P<path> S<mtime.size> I<import names digest> K<dep
  fold>`. The `-I` roots are **not** in the key: they can only change which file an `import` resolves
  to, and that resolved path is already inside the dependency's own key.
- New `trait CacheOps` + `impl CacheOps for Build` (five methods; `struct Build` gains `use CacheOps`):
  `MAX_FUNCS` has one top-level signature slot left, so the cache logic lives in `impl` methods, not
  plain functions (precedent: `PipeOps` / `RewriteOps`). Methods that ignore the receiver keep
  `(void)self;` — otherwise L2 would warn `-Wunused-variable`.
- **A hit replays nothing**: a matching key just means the artefacts are still valid, so `#line` and
  warnings are not replayed. Under `--emit-map` nothing is ever reused (the map spans the whole run and
  a skipped unit would be missing), but the key is still computed and stored so a dependency's digest
  never goes stale.
- **Safety rule (a hard refinement of §4)**: `build`'s symbol table **accumulates across units**, and a
  skipped unit's symbols never enter it — so the recompile set is a **prefix** of `order` (from the
  first miss backwards everything is recompiled, so later units can look up their symbols) **plus** the
  change-propagation closure (a dependency's key is folded into its dependants' keys, so a changed
  dependency invalidates everything downstream). Hence only a fully-unchanged tree skips the whole run.
- Dependency keys fold a fixed-width **digest** (FNV-1a), so a key does not grow exponentially with the
  import chain; a `stat` failure or an over-long key returns "no key" → must recompile, never silently
  truncated. A failed key write stays silent (it costs one rebuild, never breaks the build).
- Adds `#include <sys/stat.h>` (POSIX `stat` / `mkdir`, not a third-party dependency); L1 only has to
  pass it through, so the fixpoint is unaffected.
- Asserted in step 8 of `ct-tour.sh` (the `cachesrc` copy tree is built twice; after back-dating the
  artefacts the second build must not rewrite them, and a `touch -t` of a source must invalidate) — the
  designed fixtures under `test/modules/` run `build` only once and cannot express "the second build
  hits".

### 6.4 multi-target (D18)

**Landing notes (2026-10-17, slice 6.4)**:

- `--std=c99` (default) and `--std=gnu99` are accepted; any other value is a hard
  `unknown C standard '<v>'` (exit 1).
- **Output is unchanged**: no emission point needs a GNU extension yet, so `compile` only validates and
  accepts the switch (it prints no cc command, hence no visible effect), while `build` puts
  `-std=<std>` at the front of the suggested command (`cc -std=gnu99 core.c driver.c -o a.out`). The
  default is spelled out too, so the suggestion is complete and assertable.
- Fixtures: `std_default` / `std_gnu` (build, pinning the literal with `expected.stdout.contains` — a
  build's suggested command embeds an absolute output directory, so it cannot be byte-diffed) and
  `std_bad` (a compile-mode negative). Group 7 of `check-archive.sh` gained that optional
  `expected.stdout.contains` file (one literal per line, all must occur).

### 6.5 `map` (D19)

Design frozen only (see the scope-and-order bullet); **not implemented** until an official bindings
list appears.

> **Update (2026-10-19, D19 lifted)**: `map` is no longer design-frozen — it became **Phase 11** and
> slice **11.1** landed on the **ct-ast** mainline: parse `map trait T for instance x { … }`, emit the
> instance-level wrapper `<inst>_<Trait>_<method>` and `<inst>_<Trait>_vtable`, and add the `maps`
> field to the `--emit-map` JSON; slice **11.2** has now **wired the mapped instance into dispatch**
> (boxing uses the instance-level vtable, so a struct that never `use`d the trait still runs as its
> instance). The actual semantics and artifact naming live in [language-spec](../language-spec.md) §4.10
> and Phase 11 of the [roadmap](../roadmap.md); this section keeps the original design-freeze record.

### 6.6 dialect system (D20)

The expander is a standalone script **outside the repository** (bash / Python / awk — the author picks
the language) and `ctc` stays unaware; the §2 ban on code-generation scripts covers the **in-repo**
compiler build pipeline, so the dialect expander is exempt — **the exemption has landed in AGENTS §2**
(both languages, 2026-10-17, slice 6.6). The plugin still **never invokes the compiler**; `--watch` /
auto-expand is deferred and a plugin only consumes 6.1's map JSON. Package-manager distribution stays
out of this phase.

**Landing notes (2026-10-17, slice 6.6)**:

- **The AGENTS §2 exemption**: the expander lives **outside the repository** and `ctc` is **unaware**
  (it never runs an expander and never ships a dialect). Inside the repo, dialect sources and plugins
  are allowed **only** under `examples/**` (demos) and `test/**` (tests), in the conventional
  `ct-dialects/` directory, the file being `<name>.sh` (`/` → `-`), and must **not** become a compiler
  build step. AGENTS §6's "seven layers" therefore becomes "eight" (a new `dialect` layer).
- **A runnable demo**: `examples/07_dialect/` — `registry.ct` writes a register table into `//@`
  comments and the plugin `ct-dialects/register-map.sh` (POSIX sh + awk, no dependencies) expands it
  into the trait / structs / impls and offset macros. `test/run.sh` gained a `dialect` layer: expand →
  `ctc` → `cc` → run → compare with `.expected.out`, plus an assertion that the **unexpanded** source
  does not compile — which is exactly the "compiler stays unaware" proof. The examples layer skips that
  directory by the presence of `ct-dialects/`.
- **Layout**: the plugin sits neither at the repo root (that would suggest the compiler itself uses
  dialects) nor loose beside the source, but in the demo project's own `ct-dialects/`, matching the
  project-level layout of [dialect.md](dialect.md) §4.3. Package-manager distribution is still out of
  this phase and no download directory name is reserved.
- **Verification**: `./test/run.sh` 118/118, `bash selfhost/check-all.sh` green, and the manual
  three-step check; **the compiler and the CT line are untouched** (this slice changes no L0/L1/L2).
- **Close-out (2026-10-17)**: the version is bumped to **v0.6.0** per the phase-boundary rule (all
  four sites agree: `ctc.c`, `selfhost/ctc.ct`, `selfhost/src/{core,driver}.ct`), and the 50 goldens
  under `test/cases/**` plus the 51 under `test/modules/**` (including `map/expected.stdout`) are
  regenerated for the new version; the archived oracle is normalised by `same_modulo_version`.

### Constraints and gates

The new logic must live in `impl` methods (`MAX_FUNCS` has one slot left), and `Pipe` is at 31/32
fields (`PipeOps` at 31/32 methods). Each slice runs `./test/run.sh`, `bash selfhost/check-all.sh`
and the manual three-step check; new behaviour gets a designed fixture under `test/modules/`.
