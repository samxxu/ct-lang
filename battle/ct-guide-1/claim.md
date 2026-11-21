# battle/ct-guide-1 主张席（REVIEW）

- 主张：指引的**教学骨架保留**，但 F1–F7 必须按 v0.83.x 实现改写；F8 标为“待实测”，不得写成定论。
- 依据：v0.83.3 的 spec/lib/test 实物；指引为附件，本席不直接改文档。
- 目标：让 C 程序员拿到的每条“能省掉什么/还有什么风险”都能在仓库里找到出处。

## E1 — 关键实物证据

```console
$ grep -n "refs = -1\|非原子" docs/language-spec.md
2888:  `refs = -1` 为 immortal（字面量 / 空串），`release` 首行直接返回。refcount 是普通 `int`，
2889:  非原子、非线程安全，作者负责同步。
$ grep -n "pub String slice\|pub Str slice" lib/std/Str.h.ct
224:    pub String slice(int start, int n) {
355:    pub Str slice(int start, int n) {
$ grep -n "str_concat\|pub U16String concat" lib/std/Str.h.ct
390:pub String str_concat(Str a, Str b)
821:    pub U16String concat(U16Str other) {
$ ls lib/std
Box.h.ct  Option.h.ct  Result.h.ct  Str.h.ct  Vec.h.ct
```

## E2 — 逐条锚点与建议改写

### F1 — String 不是“永远在堆上”

- 指引 L53：“数据住哪：永远在它拥有的堆上”；L151：“数据必在堆”。
- 实物：[spec §4.70](../../docs/language-spec.md#L2888-L2889)：`refs = -1` 为 immortal（字面量/空串），
  绑定只读静态块；[spec §4.70 边界](../../docs/language-spec.md#L2926-L2927)：字段/全局位置的
  `String` **无自动 Drop**。
- 建议改写：**String 是“释放责任的所有者”，不是“数据必在堆”**；字面量/空串是只读区 immortal；
  字段 `String` 合法但无自动 Drop，需显式 `release`/协议处理。

### F2 — 四个 API 不存在或参数语义错

- 指引 L14：`String s = "x".to_string()`。
  [spec §4.70](../../docs/language-spec.md#L2892-L2895)：裸字符串字面量值类型仍是 `char *`；
  已有夹具统一写 `String s = "x"`（如 `test/ast/p80_cstr/prog.ct:10`），无字面量方法调用例。
  建议：改为 `String s = "x";`，或 `Str v = "x"; String s = v.to_string();`。
- 指引 L85：`Str trim(Str s) { return s.slice(1, s.len - 1); }`。
  [lib/std/Str.h.ct:355](../../lib/std/Str.h.ct#L355)：`slice(int start, int n)` 的第二个参数是**长度**，
  不是 end。`len-1` 会取错区间。建议：按字节用 `s.slice(1, s.len - 2)`（ASCII），
  或改用码点级 trim；并注明 `len` 是字节数。
- 指引 L132：`a.concat(b)`。
  仓库只有 `str_concat(Str, Str) -> String`（[Str.h.ct:390](../../lib/std/Str.h.ct#L390)）和
  `U16String.concat`（[Str.h.ct:821](../../lib/std/Str.h.ct#L821)）；**没有 `String.concat`**。
  建议：`str_concat(a.as_str(), b.as_str())`。
- 指引 L132：`std::arena`。`lib/std` 只有 Box/Option/Result/Str/Vec；arena 是编译器内部的
  `selfhost/ct-ast/runtime/arena`，不是公开 std 包。建议：删掉“std::arena”，改为“自建 arena/项目内分配器”，
  或明确标为“未内置”。

### F3 — ref/out 不是“生命周期 = 本次调用”

- 指引 L153 写“生命周期 = 本次调用”。
- [spec §4.68](../../docs/language-spec.md#L2859-L2860)：“`ref` 可以被存储或传给更长寿命的位置，
  语言不做借用检查（契约 + 直接 lint，J-4b）”。
- 建议：改为“调用点自动取地址；语言不阻止你把 ref 存到更长寿命位置，靠契约/lint”，
  不要给出“生命周期 = 本次调用”的保证。

### F4 — 临时视图不是“编译错”

- 指引 L105：“`make_person().name_view()` 这种从临时量取视图是编译错（lint 抓直接形态）”。
- [test/ast/p79_places.sh:48-59](../../test/ast/p79_places.sh#L48-L59)：**temporary 是允许的放置**；
  `:184` 的“返回局部 slice”是 `expect_warn`（**warning**），不是硬错。
- 建议：改为“临时视图可编译；直接返回局部视图是 lint（warning）；越界/悬垂靠契约 + ASan”。
  若特指“方法接收者临时量”，请在 battle 内补一个实测；未实测前不写“编译错”。

### F5 — “悬垂风险无 / 不可变共享无副作用”与同文 §6 冲突

- 指引 L57：“悬垂风险 无（协议保证）”；L124：“不可变共享无副作用”；
  L167 又写“句柄跨线程共享 → 数据竞争（refcount 非原子）”。
- [spec §4.70](../../docs/language-spec.md#L2888-L2889)：refcount 非原子、非线程安全；
  [selfhost/check-tsan.sh:3-6](../../selfhost/check-tsan.sh#L3-L6)：TSan 是 nightly/Linux 独立门禁。
- 建议：改为“**单线程内** owning 不悬垂；跨线程共享 refcount 非原子，需自行同步；TSan 只在 nightly/Linux”。

### F6 — box 不“省掉泄漏”

- 指引 L13 表格写 box 省掉“泄漏”；L165/L180 又承认引用环泄漏。
- 建议：改为“省掉 **malloc/free 配对与 sizeof**；环与未配对 handle 仍泄漏，环=作者责任，
  `--debug-leaks` 只报未配对计数”。

### F7 — 绝对化措辞与同文自相矛盾

- 指引 L39：“CT 不禁止任何东西”；L179：“指针只出现在 shim 和寄存器”。
- 实物：`String` 不可变、借用字段、`new String`、`Vec<T[]>` 等都有硬错（spec §4.70/§4.71/§4.69）。
  同文 L35 已写“指针在任何 .ct 里都合法”，L144 又写“应用代码里冒出指针，先问自己”。
- 建议：改为“**CT 不禁止指针**；但确实禁止若干所有权形态（不可变 String 写入、借用字段等）”，
  以及“指针主要在 shim/硬件/逃生层，不是只在”。

### F8 — Str 容器禁令：待实测

- 指引 L56：“存进字段/容器 ❌ 类型硬错（四位置白名单）”。
- [spec §4.70 边界](../../docs/language-spec.md#L2926-L2927)只明写 `Map<Str,V>`（借用类型不能作键，
  用 `Map<String,V>`）；`Vec<Str>` 在 PH-79 卡 R79-3 写“同样禁止”，但当前 spec §4.70 未落定论。
- 建议：字段 `Str` 硬错、`Map<Str,V>` 硬错可保留；`Vec<Str>` 标“待实测/以编译器为准”，
  battle 内补一个最小探针后再定稿。

## E3 — 可证伪预测

改写后应满足：

1. F1–F7 每条都能在 spec/lib/test 找到对应行；
2. 指引中不再出现 `String.concat`、`std::arena`、`"x".to_string()` 作为当前可用写法；
3. `ref/out` 与“临时视图”的风险描述与 §6、spec §4.68/§4.69 一致；
4. F8 要么有实测输出，要么明确写“待验证”。

## E4 — 代价

- 只改指引文本：约 20–30 行；不新增章节、不改教学骨架；
- 不需要实现改动；F8 若实测，只需一个临时夹具（不入库）。

## E5 — 对“目标形态/教学简化”的 steelman

指引作者可以说：这是“给 C 程序员的心智模型”，不是 API 手册，过早塞边界会劝退读者。

回应：**心智模型可以简化，但不能与实现相反**。F1/F2/F3/F4 属于“照做会编译失败或语义错”的级别，
不是简化；F5/F6/F7 属于“简化后让读者低估风险”。建议保留口诀与三层图，只把这 7 处改成
“带条件的真话”；F8 未实测就不写死。

## 待讨论

- F4 的“临时接收者取视图”是否需要单独实测（若实测是硬错，指引可保留“编译错”，但需给出夹具）。
- F8 的 `Vec<Str>` 是否在 PH-80 后被允许；需要 DEV 侧一个最小探针。
- 指引是否作为正式文档入库（`docs/guide-for-c-programmers.md`）还是保持外稿；入库前需通过本 battle。
