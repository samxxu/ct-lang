# SwiftCT 方言接口 battle：主张席 / 反证席

> 中文
>
> **对象**：外部提案《CT 方言语义导出与 SwiftUI 三方资产组方案》（自称基于 v0.12.0），及负责人补充的交付形态。
> **核对基线**：本仓 `v0.53.0`（`ct-ast v0.53.0`，HEAD `267cb5eb`）。负责人所说「现行 v0.52.0」已过时一版。
> **实测**：按 `selfhost/check-ast.sh` 链路在 `/tmp/ctprobe` 重建探针编译器（L0→L1→L2→ct-ast），未改仓库实现。
> **主交付物**：§6 细节问题清单。§5 裁定与 §7 未决项从该清单派生。
> **配套**：[swiftct-dialect-interface-review.md](swiftct-dialect-interface-review.md) 承载前提逐条核对、四组对应关系（类型映射 / 事件 / 生命周期 / 状态绑定）、两类契约边界、依赖顺序、缺口回退与两侧验证点；本文只做对冲与裁定，不重复展开。

---

## 0. 既定前提（不再讨论）

1. SwiftCT 是 ct-pkg 下的第三方包，CT 主仓不带它。
2. CT 只负责「足够的方言编写能力」，且必须是跨进程、语言无关的固定接口。
3. 生成器可能是 PHP，只读声明层语义视图，不读 `.ct` 文本、不读内部 AST、不依赖 mangling 与降级方式。
4. 一份声明派生三份产物（CT 模型与事件 / 胶水 / SwiftUI 代码），靠协议钉住。
5. 目标是开发者只写 `.ct`，不写胶水样板。

---

## 1. 两席共享事实（双方均不反对）

| # | 事实 | 证据 |
|---|---|---|
| S1 | 现行方言是**注释块路由 + argv 输入 + stdout 输出**的文本变换器，编译器零感知、永不调用展开器 | `AGENTS.md:402-410`；`test/run.sh:298-313`、`315-385`；`docs/history/design/dialect.md:62-66` |
| S2 | `CT_FILE` / `CT_LINE` / `CT_NS`（env 通道）**从未实现**，只存在于归档草案 | `docs/history/design/dialect.md:246-252`；全仓代码零引用 |
| S3 | 唯一语义出口是 `--emit-map`，输出 `compiler/file/traits/structs/impls/functions/calls/maps`；struct 只有 `name/cname/file/line/uses`，方法只有 `ret` 与形参**个数**，函数同理 | 实测输出见 §附录 P1 |
| S4 | 前端符号表**已持有** `Field{name,type,dims}`、`StructDef.fields[]`，多个记录已有 `line`/`col`；缺的是「序列化」而不是「数据」 | `selfhost/ct-ast/frontend/sym/Symbols.h.ct:232-238`、`246-247`、`351-352` |
| S5 | `Field` 自身**没有** `line`/`col`（只有 name/type/dims） | 同上 `232-238` |
| S6 | `ct build --lib` 产出 `.abi.h`：不透明前置声明 + 导出自由函数 + `ABI_VERSION` + `ABI_HASH`；导出面**只含根单元 `pub` 自由函数**，固有方法与 trait impl 不进 | 实测 P2；`docs/history/design/phase39.md:37-48`、`60` |
| S7 | 回调函数指针**可以**出现在导出签名里，但不会生成 `typedef` | 实测 P2：`void UI_login_set_on_login(struct UI_Login *, void (*)(void *, int), void *);` |
| S8 | `ABI_HASH` 只哈希**导出名**：把回调参数 `int` 改 `long`，头变了、哈希不变 | 实测 P3：`0x3b8d1c83` → `0x3b8d1c83` |
| S9 | 包分发走「整树复制」，非 `.ct` 文件会一起进 `vendor/`；但 `ct install` 打印编译单元时只收 `.ct` | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:533`、`1404` |
| S10 | 闭包档②（`=>`）是 non-escaping 绑定，不可存、不可跨调用存活；档① 是手写 `(fn, env)` | `docs/closure-conventions.md` 约定 #3；`docs/language-spec.md:2119-2159` |
| S11 | 命名冲突与空导出都在编译期报 `file:line:col`、rc=1 | 实测 P4：`duplicate struct 'S'` rc=1；`no exported functions` rc=1 |
| S12 | 三处语法已漂移：`namespace A { }` 块式、`void m(self)`、`pub impl` 块在 v0.53.0 全部报错 | 实测 P5 |

---

## 2. 主张席

### 2.1 成立路径

三段式，每段都有明确归属：

```
用户 .ct（只写模型 + 逻辑）
   │  ①  ct --emit-map - <unit> -o /tmp/x.c      ← CT 提供：声明层视图（JSON）
   ▼
PHP 生成器（包内，入库）
   │  ②  读视图 + 包内映射表 + 模板
   ├──► generated/*.ct    （CT 侧状态/事件骨架，自由函数）
   ├──► generated/*.c/.h  （胶水：不透明句柄 + set_on_* + ctx）
   └──► generated/*.swift （holder + @State 镜像 + @convention(c) trampoline）
   ▼
③  ct build（CT 侧）+ Xcode/SPM（Swift 侧）→ 可运行
```

关键：①②③ **都不共享内存、不共享类型定义**。① 是 JSON，② 是文件，③ 是编译器命令行。

### 2.2 最小接口（M1–M6）

| # | 接口 | 归属 | 现状 |
|---|---|---|---|
| M1 | 声明层视图 v1：`schema` + models/fields/methods/events/use/loc{file,line,col} | CT | 部分有，缺字段/形参类型/col |
| M2 | C ABI 面 `.abi.h`（不透明句柄 + 导出自由函数 + `ABI_VERSION`） | CT | **已有** |
| M3 | 导出指纹：`ABI_HASH` 升到签名级，或由视图 `view_hash` 承担 | CT | 只有名字级 |
| M4 | 生成物可校验入口（`ct check` / `ct build` 给 `file:line:col` + rc=1） | CT | **已有** |
| M5 | 资产组布局、命名、模板、`--verify` | 包 | 无（须自建） |
| M6 | 类型映射表、状态绑定、组件映射、运行时 | 包 | 无（须自建） |

### 2.3 两半交付

| | 包（ct-pkg 侧） | CT 侧 |
|---|---|---|
| 交付物 | `ct.pkg`、`gen/gen.php`、`runtime/*.swift`、`templates/`、`generated/`、`examples/`、`tools/verify.php` | `--emit-map` 扩字段 + `schema`；`Field` 补 `loc`；`ABI_HASH` 升签名级；保持不变：`--lib`、`ct check` |
| 不交付 | 语义视图、ABI 头 | SwiftUI 映射表、运行时、绑定方案、bridging header、资产组布局 |
| 门禁 | golden 工程跑通 + `--verify` + 黑名单检查 | fixture 逐字段断言 + 负例 rc=1 |

### 2.4 细节怎么定（D1–D10）

**D1 类型映射。** 视图的 `type` 给「声明处原文拼写 + 空白规范化」，**不做 typedef 展开**；同时必须给 `kind`（`scalar` / `pointer` / `array` / `fnptr` / `struct` / `opaque`）。包内映射表：`char *` → `UnsafeMutablePointer<CChar>?`，`T *`（T 为具名 struct）→ `OpaquePointer?`，整型 → 定宽 Swift 整型。**只给字符串不够**——`typedef` 会把指针伪装成标量。

**D2 事件与 ctx。** CT 侧生成自由函数 `x_set_on_<e>(X *self, void (*cb)(void *ctx, …), void *ctx)`；CT 模型只存 `fn`/`ctx` 两个字段；Swift 侧 `Unmanaged.passUnretained(holder).toOpaque()`；注销传 `(NULL, NULL)`。**档② 不能用**（non-escaping，S10）。

**D3 生命周期。** holder 唯一持有句柄；`deinit` 顺序固定为「注销 → `x_free`」；`x_free` 在 CT 侧**清空回调槽**作为二道保险。CT 侧 `x_new`/`x_free` 成对进 ABI。

**D4 状态绑定。** 真源在 CT 侧（模型定义方），Swift `@State` 只是镜像；输入类控件（TextField 等）**本地缓冲、提交时再写回**，避免每击键一次跨 FFI。

**D5 资产组与命名。** 全部在包内：`generated/` + 后缀区分；符号用「包名 + 模型名 + 事件名」；前缀冲突由生成器检测（视图里的 `cname` 集合内查重）。

**D6 回指。** 每段生成物带 `// @ct <file>:<line>:<col>`；Xcode 只能跳到行，列用于人工定位与生成器报错定位。**前提是视图给 `col`，且 `Field` 要补 `loc`**（S5）。

**D7 schema 版本。** 视图带整数 `schema`；只追加字段、不改既有语义；生成器持 `expect.json`，不匹配即非 0 退出。

**D8 失败判定。** 四类：① 导出失败（编译器 rc=1，`file:line:col`）；② schema 不兼容（生成器 rc=1，打印期望/实际）；③ 产物缺项（`--verify` rc=1，列出缺哪份）；④ 哈希不符（`--verify` rc=1，指出改过哪一侧）。

**D9 PHP 实现要点。** 只吃 JSON；输出确定性（字段排序、固定换行、不写时间戳）；每份产物写 `schema` + `view_hash` + `ABI_HASH`；不读 `.ct`、不读 `.h`。

**D10 Xcode 集成。** 生成物入库；bridging header 由包**生成一次并固定在工程里**（Build Settings 里的一行，不是每模型一次）；`@main` / App 生命周期人写。

---

## 3. 反证席（逐条攻击）

**A1 · 提案基线与现行机制不符，路径不能沿用。**
11 条前提中 5 条从未存在（`trait View`、`use Range`/`Range` trait、asset group、`each` 关键字、`set_on_*`）、3 条形态已变（只吐 C、无公共出口、`Type_method`）、3 条成立（注记路由、`borrow`、闭包档①②）。提案 §2 九项里 #2/#3/#4/#9 在解决不存在的问题；§6 三处类比全部落空。**强度：高**（主张席已接受，路径重写）。

**A2 · 前端能不能导出这份视图——能，但有两个硬细节。**
(a) `Field` 没有 `line/col`（S5），字段级回指要动前端结构体；(b) `--emit-map` 在 `build` 模式下实测**不落盘**（传文件路径也不生成，P6），只有 `compile` 模式能出 JSON；而多单元工程必须逐单元调用再合并。**强度：中高**（主张席接受，代价进条件）。

**A3 · 非 C 产物在包体系里怎么落地。**
`copy_tree` 会把 `.swift` 一起 vendored（S9），但 CT 的编译入口只认 `.ct`（`Pkg.h.ct:1404`）；没有任何 CT 命令会消费 `.swift`。因此「一条命令跑起来」**不可能由 `ct build` 单独承担**，必须包提供包装命令。**强度：中**（主张席接受，口径改为「包提供 gen+build 包装」）。

**A4 · 事件回调与 `void *ctx` 的跨语言所有权。**
CT 侧无法证明 ctx 不被保存（`docs/language-spec.md:1829` 已把「env 以 `void *` 交给不透明接收方后被保存」列为未防护面）；`_free` 清槽只在 CT 侧生效，若回调正在飞行（重入/多线程）仍可能 UAF。**强度：高**（必须降级为「单线程 UI + 清槽」）。

**A5 · 漂移检测是否真做得到。**
`ABI_HASH` 不含签名（S8），改 `int`→`long` 检测不到。`view_hash` 能补字段类型，但**头部戳是自证式**：手改产物的人也可以顺手改戳。真正可靠的判据只有「重跑生成器 + 逐字节比对」，代价是每次全量重生成。**强度：中高**（接受，条件写「`--verify` 必须重跑生成，不得只读戳」）。

**A6 · PHP 生成器的可维护性与跟版。**
视图字段一旦变化，PHP 必改；但比「PHP 解析 `.ct` 文本」低一个数量级（后者要追 namespace 形态、`use` 子句、impl 可见性，v0.12→v0.53 已变三次）。真正风险是**输出确定性**（PHP 数组顺序、浮点格式化）与**映射表跟版**，两者都在包侧。**强度：中**（接受，条件写「确定性输出 + 映射表版本钉住」）。

**A7 · 「用户不写样板」是否被 Xcode/bridging 现实击穿。**
击穿一处：bridging header 必须在 Xcode Build Settings 里出现一次（工程级，可生成，但不能零配置）。holder、注销顺序、`@convention(c)` 都能生成。`@main` 与 App 生命周期仍必须人写。因此口径只能是「把 Swift 缩到最薄」，不能是「不需要 Swift」。**强度：中**（主张席本来就这么写，判为一致）。

**A8 · `use View` 作为标记会改布局。**
`use` 子句真实存在（`docs/language-spec.md:72-73`），但会**追加 vptr 字段**（`131-148`）。若把 `use View` 当纯标记，每个模型多一个指针 + vtable 初始化，且与「模型布局不动」的直觉冲突。**强度：中**（主张席不再依赖它，改为包内目录/生成区约定）。

**A9 · 「一份声明三份产物」的原子性没有语言侧保证。**
CT 只保证「生成的 `.ct` 能编译」，不保证三份同源。原子性只能由生成器 + `--verify` 提供，CT 无法约束。**强度：中**（接受，属包责任）。

---

## 4. 交叉质询

| 反证席追问 | 主张席回应 | 反证席再驳 / 结论 |
|---|---|---|
| A2：字段级 `loc` 到底要不要？ | 要，但可分两步：先出字段名/类型，`loc` 后补 | 后补期间字段级回指不成立，必须写进「暂不主张」 |
| A4：单线程假设是不是太弱？ | UI 主线程模型成立；跨线程由包文档排除 | 可接受，但必须在 ABI 文档明写 |
| A5：重跑生成的成本能接受吗？ | 生成是秒级；CI 每次重跑 | 可接受 |
| A7：bridging header 一次配置算不算「手写样板」？ | 不算：一次工程级配置，不是每模型 | 必须在验收口径里显式豁免，否则判据永远红 |
| A9：CT 要不要提供「三份同源」检查？ | 不要：会替包跟 Swift 工具链 | 接受 |

---

## 5. 裁定

**有条件成立。** 条件全部可判定：

| # | 条件 | 判定方式 |
|---|---|---|
| C1 | 视图含 `schema`、`models[].fields[{name,type,kind,loc}]`、`methods[].params[{name,type}]` | 对 fixture 逐字段断言，缺一即不成立 |
| C2 | 视图导出可逐单元调用、可合并（`compile` 模式，JSON 到 stdout 或文件） | 多单元工程导出后合并结果字段数与逐单元之和相等 |
| C3 | 字段级回指依赖 `Field` 补 `loc`；未补前，「字段级回指」标为暂不主张 | 视图里 `fields[].loc` 存在且非 0 |
| C4 | 指纹取签名级 `ABI_HASH` 或视图 `view_hash`，且 `--verify` 必须重跑生成后比对 | 改 `int`→`long` 不重生成，`--verify` 必须 rc≠0 |
| C5 | 事件仅支持单线程 UI；`x_free` 清回调槽；注销传 `(NULL,NULL)` | ABI 文档写明 + 模板含清槽；跨线程用例明确不支持 |
| C6 | 状态真源在 CT 侧，输入控件本地缓冲 | 生成物中 TextField 路径有缓冲层 |
| C7 | 资产组布局/命名由包定，CT 只保证多单元可分 | 包内 manifest 存在；CT 侧无资产概念 |
| C8 | 生成物入库 + 头部戳 + `--verify` 全量重生成比对 | 手改一份产物 → `--verify` rc≠0 |
| C9 | bridging header 一次性工程级配置，不算「用户样板」 | 验收黑名单只查「每模型手写」 |
| C10 | 联调 6 条（同声明三产物、改类型重生成、只生成一份、手改、黑名单、无编译器机器构建）必须一起验 | 六条全绿才算联调通过 |

---

## 6. 细节问题清单（主交付物）

| # | 争点 | 主张席证据 | 反证席证据 | 裁定 |
|---|---|---|---|---|
| 1 | 提案前提是否仍成立 | 分层目标合理 | 5 条从未存在、3 条形态已变（S1/S2/S12） | **不成立**：路径必须重写，提案只能当动机 |
| 2 | 语义出口载体 | `--emit-map` 可扩 | 只有 compile 模式落 JSON（P6） | **有条件成立**：固定在 compile 模式，逐单元导出 |
| 3 | 字段能否导出 | 前端已有 `Field{name,type,dims}`（S4） | `Field` 无 `loc`（S5） | **成立（字段名/类型）；字段 loc 未决** |
| 4 | 形参类型能否导出 | 前端有类型信息 | JSON 只发个数（S3） | **成立**，序列化工作 |
| 5 | `col` 能否导出 | 多个记录已有 `col`（S4） | 结构体字段没有 | **部分成立**：模型/方法级可，字段级不可 |
| 6 | 不透明句柄 | `--lib` 已产 `struct X;`（S6） | 普通 `.h` 是全定义；固有方法不导出 | **成立**，但胶水只能写自由函数 |
| 7 | 回调 typedef | 函数指针可导出（S7） | `.abi.h` 不发 typedef | **成立**：包内包一层 `typedef` |
| 8 | `set_on_*` 命名约定 | 可自由函数实现 | `set_on_*` 在 CT 无对应物 | **成立（包约定）**，不是语言能力 |
| 9 | 事件持久回调 | 档① 可用 | 档② non-escaping（S10） | **成立（仅档①）** |
| 10 | ctx 所有权安全 | `_free` 清槽 | CT 不检查保存；重入风险（A4） | **有条件成立**：单线程 + 清槽 + 文档 |
| 11 | 生命周期顺序 | 模板可写死 | 无编译期检查 | **有条件成立**：模板 + `_free` 清槽 |
| 12 | 状态真源 | CT 是模型定义方 | 输入控件每击键跨 FFI 代价 | **有条件成立**：本地缓冲 |
| 13 | 资产组是否由 CT 定义 | 需要契约 | 属包概念，CT 定义即替包跟版（S9） | **不成立（CT 侧）**：只固定三条红线 |
| 14 | 非 C 产物落地 | 整树复制会带（S9） | CT 无消费入口（`Pkg.h.ct:1404`） | **成立（文件层面）**，构建入口归包 |
| 15 | 回指到列 | 视图给 `col` | Xcode 只能跳行 | **有条件成立**：列只用于定位，不承诺跳转 |
| 16 | `ABI_HASH` 作为漂移判据 | 已有哈希 | 只哈希名字（S8） | **不成立**：需签名级或 `view_hash` |
| 17 | `--verify` 可否只读头部戳 | 低成本 | 自证式，可被手改绕过 | **不成立**：必须重跑生成比对 |
| 18 | 三份产物原子性 | 生成器保证 | CT 无约束 | **成立（包责任）** |
| 19 | PHP 只读视图 | 视图足够即成立 | 视图缺字段时只能回读源码 | **有条件成立**：视图字段集是前置 |
| 20 | 用户零胶水 | 生成器可覆盖 | bridging header 需一次性工程配置 | **有条件成立**：口径改为「最薄」 |
| 21 | 单命令跑通 | `ct build` 单入口 | 只管 CT 侧（A3） | **不成立**：必须包提供包装命令 |
| 22 | `use View` 作显式标记 | 已有语法 | 加 vptr，改布局（A8） | **未决，需负责人拍板** |
| 23 | 注记是否进语言 | 视图内可见 | 成本远超「几百行」 | **未决，需负责人拍板** |
| 24 | `ABI_HASH` 是否改判据口径 | 一处小改 | 动已收口的 Phase 39 判据 | **未决，需负责人拍板** |
| 25 | 成本「几百行」是否可信 | 序列化为主 | 注记/字段 loc 会放大 | **不成立**：须分项报，不能打包成一句 |

---

## 7. 未决，需负责人拍板

1. **#22 显式标记**：`use View`（零新语法、加 vptr）／目录约定（零副作用、不进符号表）／新增注记（成本最高）。
2. **#23 注记是否进语言**：若要求「PHP 只依赖视图且模型自带元数据」，注记是唯一干净解。
3. **#24 `ABI_HASH` 是否升签名级**：涉及已收口的 Phase 39 判据，不宜由评估自行改。
4. **#3/#5 字段级 `loc` 是否本期主张**：不主张就把「字段级回指」明确标为暂不支持，不得含糊。
5. **#20 验收口径措辞**：是否接受「bridging header 一次性工程配置」不计入用户样板。

---

## 附录：探针（全部在 `/tmp/ctprobe`，未改仓库）

| 编号 | 命令要点 | 结果 |
|---|---|---|
| P1 | `ctast --emit-map - m.ct -o m.c` | JSON 无字段、无形参类型、无 `col` |
| P2 | `ctast build --lib UI.h.ct --outdir out6 -o ui.a` | `.abi.h`：`struct UI_Login;` + 三个导出（含回调 fnptr，无 typedef） |
| P3 | 同源改 `int`→`long` 回调参数 | `.abi.h` 变，`ABI_HASH` 均为 `0x3b8d1c83`（**不变**） |
| P4 | 两单元重复 `struct S` / 空导出 | `duplicate struct 'S'` rc=1 / `no exported functions` rc=1 |
| P5 | `namespace A { }`、`void m(self)`、`pub impl` | 三者均报错（见 S12） |
| P6 | `build --lib --emit-map out.json` | JSON **未落盘**；仅 `compile` 模式可出 |
| P7 | `pub impl Widget` 与逐方法 `pub` | 块式报错；逐方法 `pub` 不进导出面（`no exported functions`） |
