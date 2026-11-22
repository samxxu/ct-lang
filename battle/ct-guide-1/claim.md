# battle/ct-guide-1 主张席（REVIEW）

- 主张：指引的**教学骨架保留**；F1–F8 按 **v0.84.1** 实现改写，F9 补 ADT/match 章节；
  F4/F8 已有实测，不再挂“待验证”。
- 依据：v0.84.1 的 spec/lib/test 实物 + 最小探针（/tmp，不入库）。
- 目标：让 C 程序员拿到的每条“省了什么/还有什么风险”都能在仓库或实测里找到出处。

## E1 — 关键实物与实测证据

```console
$ ct --version
ct v0.84.1

$ ct build --debug-leaks /tmp/ct-guide-probe/vstr.ct
ctc: unknown option '--debug-leaks'

$ grep -n "refs = -1\|非原子" docs/language-spec.md
2888:  `refs = -1` 为 immortal（字面量 / 空串），`release` 首行直接返回。refcount 是普通 `int`，
2889:  非原子、非线程安全，作者负责同步。

$ grep -n "pub String slice\|pub Str slice\|pub String str_concat" lib/std/Str.h.ct
224:    pub String slice(int start, int n) {
355:    pub Str slice(int start, int n) {
390:pub String str_concat(Str a, Str b)

$ grep -n "concat" lib/std/Str.h.ct
821:    pub U16String concat(U16Str other) {      # 只有 U16String，没有 String.concat

$ ls lib/std
Box.h.ct  Option.h.ct  Result.h.ct  Str.h.ct  Vec.h.ct   # 无 std::arena
```

最小探针（源码在 `/tmp/ct-guide-probe/`，从仓库根目录 `ct build /tmp/...` 执行，
以便自动加载 `lib/std`；在 `/tmp` 下执行会因找不到 std 报 `use of an undeclared variable`）：

| 探针 | 代码要点 | 结果 |
| --- | --- | --- |
| `t1_literal_method.ct` | `String s = "x".to_string();` | **失败**：`no method 'to_string' for type 'char *'` |
| `t2c.ct` | `Str f(void){ return make_p().view(); }` | **通过**（rc=0）：临时接收者取视图可编译 |
| `retlocal2.ct` | `Str f(void){ String s = str_dup("x"); return s.as_str(); }` | **通过**且 `ct check` 无告警：局部视图逃逸无 lint |
| `fieldstr.ct` | `struct C { Str name; }` | **失败**：`a borrowed 'Str' view cannot be a struct field` |
| `vstr.ct` | `Vec<Str> v;` | **通过** |
| `vpush.ct` | `Vec<Str> v; v.push(s.as_str());` | **通过**：Str 可作 Vec 元素 |
| `tv.ct` | `Option<Str> o;` | **通过** |
| `mapstr.ct` | `Map<Str, int> m;` | **失败**：`Map key type 'Str' is a borrowed view; use 'String' (owning)` |
| `adt_str2.ct` | `enum E { A(Str s), B() }` + `E.A(v)` | **通过**：Str 可作 ADT 负载 |
| `adt_string.ct` | `enum E { A(String s), B() }` | **通过**：owning payload 可编译，但无 drop glue |
| `adt_refs.ct` | `String x = str_dup(...); E e = E.A(x); match ... s.release();` | **通过**：构造后 `x.refs()` 仍为 1（**不 retain**）；绑定 `s.refs()` 为 1（浅拷贝）；释放绑定后 `x.refs()` 变成垃圾值（悬垂） |

## E2 — 逐条锚点与建议改写

- **不利于己方的一条**：`docs/language-spec.md:2861` 明确 `ref` 可被存储/传给更长寿命位置，
  支持 F3 的改写；但指引作者可主张“教学上仍建议按调用期理解”，这只能作为表述边界，
  不能推翻事实。若最终判定“教学简化优先”，F3 可降为“建议”而非“必须”。
- 关键锚点：`docs/language-spec.md:2888`（immortal）、`docs/language-spec.md:3061`
  （绑定副本 / owning payload 按 move、ADT 无 drop glue）、`lib/std/Str.h.ct:355`
  （`slice` 第二参是长度）、`test/ast/p79_places.sh:184`（E79-6 只覆盖 `T[]` 切片）。

### F1 — String 不是“永远在堆上”

- 指引 L53：“数据住哪：永远在它拥有的堆上”；L151：“数据必在堆”。
- 实物：[spec §4.70](../../docs/language-spec.md#L2888-L2893)：`refs = -1` 为 immortal（字面量/空串），
  绑定只读静态块；[spec §4.70 边界](../../docs/language-spec.md#L2926-L2927)：字段/全局位置的
  `String` **无自动 Drop**。
- 建议改写：**String 是“释放责任的所有者”，不是“数据必在堆”**；字面量/空串是只读区 immortal；
  字段 `String` 合法但无自动 Drop，需显式 `release`/协议处理。

### F2 — 四个 API 不存在或参数语义错

- 指引 L14：`String s = "x".to_string()`。实测失败（E1 t1）；字面量裸值类型是 `char *`
  ([spec §4.70](../../docs/language-spec.md#L2892-L2895)）。建议改 `String s = "x";`。
- 指引 L85：`Str trim(Str s) { return s.slice(1, s.len - 1); }`。
  [Str.h.ct:355](../../lib/core/Str.h.ct#L355)：第二参是**长度 n**，不是 end；`len-1` 会取错区间。
  建议按字节写 `s.slice(1, s.len - 2)`（ASCII），并注明 `len` 是字节数。
- 指引 L132：`a.concat(b)`。仓库只有 `str_concat(Str, Str) -> String`
  ([Str.h.ct:390](../../lib/core/Str.h.ct#L390)) 和 `U16String.concat`
  ([Str.h.ct:821](../../lib/core/Str.h.ct#L821))；**没有 `String.concat`**。
  建议：`str_concat(a.as_str(), b.as_str())`。
- 指引 L132：`std::arena`。`lib/std` 只有 Box/Option/Result/Str/Vec；arena 是编译器内部
  `selfhost/ct-ast/runtime/arena`，不是公开 std 包。建议删掉或标“未内置”。

### F3 — ref/out 不是“生命周期 = 本次调用”

- 指引 L153 写“生命周期 = 本次调用”。
- [spec §4.68](../../docs/language-spec.md#L2861-L2862)：“`ref` 可以被存储或传给更长寿命的位置，
  语言不做借用检查（契约 + 直接 lint，J-4b）”。
- 建议：改为“调用点自动取地址；语言不阻止你把 ref 存到更长寿命位置，靠契约/lint”。

### F4 — 临时视图不是“编译错”（已实测）

- 指引 L105：“`make_person().name_view()` 这种从临时量取视图是编译错（lint 抓直接形态）”。
- 实测：`t2c.ct`（`return make_p().view()`）**build rc=0**；`retlocal2.ct`
  （返回局部 `String` 的 `as_str()`）也 **rc=0 且 `ct check` 静默**。
- [test/ast/p79_places.sh:48-59](../../test/ast/p79_places.sh#L48-L59)：temporary 是允许的放置；
  `:184` 的 `slice escape` 是 `expect_warn`，且只覆盖 `T[]` 切片，不覆盖 `Str`。
- 建议：改为“临时视图可编译；返回局部 **切片** 是 lint（warning）；**Str 视图逃逸当前无 lint**，
  越界/悬垂靠契约 + ASan”。

### F5 — “悬垂风险无 / 不可变共享无副作用”与同文 §6 冲突

- 指引 L57：“悬垂风险 无（协议保证）”；L124：“不可变共享无副作用”；
  L167 又写“句柄跨线程共享 → 数据竞争（refcount 非原子）”。
- 实测：局部 Str 视图返回可编译且无 lint（E1 `retlocal2`）。
- [spec §4.70](../../docs/language-spec.md#L2888-L2889)：refcount 非原子、非线程安全；
  [selfhost/check-tsan.sh:3-6](../../selfhost/check-tsan.sh#L3-L6)：TSan 是 nightly/Linux 独立门禁。
- 建议：改为“**单线程内** owning 不悬垂；**Str 视图逃逸不在编译期兜底**；
  跨线程共享 refcount 非原子，需自行同步；TSan 只在 nightly/Linux”。

### F6 — box 不“省掉泄漏”，`--debug-leaks` 也未实现

- 指引 L13 表格写 box 省掉“泄漏”；L165/L180 又承认引用环泄漏。
- 指引 L165 把 `--debug-leaks` 列为防线。实测 `ct build --debug-leaks` →
  `ctc: unknown option '--debug-leaks'`；[spec §4.71 边界](../../docs/language-spec.md#L2952-L2955)
  写“（若将来实现）只报未配对计数”，[spec §4.72 非目标](../../docs/language-spec.md#L2985-L2986)
  再次声明；[phase81 评审](../../docs/reviews/2026-11-21-phase81-rev-verdict.md#L116)与
  [phase82 评审](../../docs/reviews/2026-11-21-phase82-rev-verdict.md#L118)均记录该选项未实现。
- 直接环 lint 存在：`test/ast/p82_cycle.sh` 的文案是
  `may leak unless the cycle is broken by hand`（不说 `will leak`）。
- 建议：改为“省掉 **malloc/free 配对与 sizeof**；环与未配对 handle 仍泄漏，环=作者责任；
  直接环有 lint；`--debug-leaks` **当前未实现**，将来也只报未配对计数”。

### F7 — 绝对化措辞与同文自相矛盾

- 指引 L39：“CT 不禁止任何东西”；L179：“指针只出现在 shim 和寄存器”。
- 实物：`String` 不可变写入、`Str` 字段、`Map<Str,V>` 键、`new Str` 等都是硬错
  （spec §4.70/§4.71；E1 探针）。
- 同文 L35 已写“指针在任何 .ct 里都合法”，L144 又写“应用代码里冒出指针，先问自己”。
- 建议：改为“**CT 不禁止指针**；但确实禁止若干所有权形态”，以及“指针主要在 shim/硬件/逃生层，
  不是只在”。

### F8 — Str 容器禁令：已实测，原表述过宽

- 指引 L56：“存进字段/容器 ❌ 类型硬错（四位置白名单）”。
- 实测边界：
  - struct 字段：**硬错**（`fieldstr.ct`，错误文案明确）；
  - `Map` 键：**硬错**（`mapstr.ct`）；
  - `Vec` 元素：**允许**（`vstr.ct` / `vpush.ct`）；
  - `Option<Str>` 与 ADT 负载：**允许**（`tv.ct` / `adt_str2.ct`）。
- [spec §4.70 边界](../../docs/language-spec.md#L2926-L2927)只明写 `Map<Str,V>` 键。
- 建议改写为两行：
  - `Str` 不能作 **struct 字段 / Map 键**（硬错，必须换 owning `String`）；
  - `Vec<Str>`、`Option<Str>`、ADT 负载**可以**，但存的是借用视图，
    owner 必须先于容器/值死亡，语言不拦——这是 §6 的新增风险条目。

### F9 — 缺 ADT/match 章节（v0.84 新特性）

- 指引页首停在 v0.83.x，全篇无 `enum` 负载 / `match`。对 C 程序员应有一节，至少包含：
  - **两形态**：任一成员带负载 = ADT（tagged union）；全无负载 = C enum；不能混用
    ([spec §4.73](../../docs/language-spec.md#L3013-L3015))。
  - **值类型、无 vtable、无分配**：ADT 不是 trait 接口；构造是复合字面量
    ([spec §4.73 布局](../../docs/language-spec.md#L3053-L3056))。
  - **match 是语句**、必须穷尽或末位 `_`、绑定是**副本**、owning payload 按 **move** 进绑定
    ([spec §4.73](../../docs/language-spec.md#L3021-L3026))。
  - **最关键的诚实登记**：编译器**不生成 ADT drop glue**，owning payload（如 `String`）
    的释放由作者显式处理；`match` 绑定拿走的 owning 值同理
    ([spec §4.73](../../docs/language-spec.md#L3061-L3064)、
    [简化条](../../docs/language-spec.md#L3074-L3076))。
  - **实测补充（比 spec 文字更危险）**：`E.A(x)` 构造**不 retain**（`x.refs()` 仍为 1），
    `match` 绑定是浅拷贝（`s.refs()` 也为 1）；`s.release()` 后 `x.refs()` 变成垃圾值，
    原句柄悬垂。因此要把 ADT 当“move 语义”写：**payload 只释放一次，释放后原句柄不再使用**。
  - 上限：64 ADT / 16 变体 / 8 负载；无泛型 ADT、无 or/守卫/嵌套/结构体模式、无表达式 match。
- 建议：在 §3 之后新增“§4 tagged union（ADT）与 match：C 的 enum + union，但所有权要自己收尾”，
  并把“owning payload 不自动释放”加入“残余风险诚实清单”。

## E3 — 可证伪预测

改写后应满足：

1. F1–F9 每条都能在 spec/lib/test 或本 claim 的实测里找到对应行；
2. 指引不再出现 `String.concat`、`std::arena`、`"x".to_string()` 作为当前可用写法；
3. `ref/out`、临时视图、Str 容器/字段的风险描述与实测、spec §4.68/§4.69/§4.70 一致；
4. 页首写 v0.84.1，并有 ADT/match 小节与“payload 不自动释放”风险条目。

## E4 — 代价

- 只改指引文本：约 40–60 行（新增 F9 小节 + 修订 F1–F8）；不新增实现、不改教学骨架；
- 探针均在 `/tmp`，不进入仓库门禁。

## E5 — 对“目标形态/教学简化”的 steelman

指引作者可以说：这是“给 C 程序员的心智模型”，不是 API 手册，过早塞边界会劝退读者。

回应：**心智模型可以简化，但不能与实现相反**。F1/F2/F3/F4/F8 属于“照做会编译失败或语义错”；
F5/F6/F7 属于“简化后让读者低估风险”；F9 是 v0.84 新增能力，缺了就不是“当前版本的指引”。
建议保留口诀与三层图，只把这几处改成“带条件的真话”，并新增一节 ADT/match。

## 待讨论

- F4/F5 的定稿口径：写成“Str 视图逃逸无 lint、靠契约 + ASan”，还是要求 DEV 补一条
  Str 逃逸 lint（后者超出本 battle 的 forbidden 范围，只能开 issue）。
- 入库目标存在冲突：[docs/memory-guide.md](../../docs/memory-guide.md) 仍是 `own` / `delete` /
  `Drop` / `borrow` 时代的“内存实践指南”，且 §8 仍写“Arena（提案，未落地）”；新指引若独立入库，
  两份“内存”文档会给出不同心智模型。需要在“替换 / 并存 + 互链 / 合并重写”中三选一。
- 是否把 F9 的“ADT payload 不自动释放”同时补进 language-spec 之外的 tutorial/patterns
  （属于 `battle/doc-consistency-1` 的范围，避免两处重复施工）。
