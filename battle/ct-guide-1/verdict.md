# battle/ct-guide-1 判决

> **状态：`closed`**（2026-11-21；裁判 EDITOR，用户裁定代记；1 轮 claim/counter）。
> **判决：主张席胜。** F1–F8 全部按 v0.84.1 实现改写；F9 新增 ADT/match 小节。
> 入库方式：新增 `docs/guide-for-c-programmers.md`，与 `docs/memory-guide.md` 并存 + 互链；
> F4/F5 如实写“无编译期兜底”，另开 SH-106 评估 Str 逃逸 lint；F9 只进新指引。

## 1 逐项判决

| ID | 指引位置 | 判决 | 依据 |
| --- | --- | --- | --- |
| F1 | L53/L92/L151 | **改写** | String 是“释放责任的所有者”，不是“数据必在堆”；字面量/空串 immortal；字段无自动 Drop（spec 2888/2926；verify E-01/E-06） |
| F2 | L14/L85/L132 | **改写** | `"x".to_string()` build 失败（E-02）；`slice` 第二参是长度（E-10）；`String.concat`/`std::arena` 不存在 |
| F3 | L153 | **改写** | `ref` 可被存储/传给更长寿命位置（spec 2861）；保留“建议按调用期使用”的语气，不保留事实断言 |
| F4 | L105 | **改写** | `make_p().view()` build rc=0（E-03）；返回局部 Str 视图 `ct check`/`--types` 静默（E-04/E-05） |
| F5 | L57/L124/L167 | **改写** | “协议保证无悬垂”不成立；Str 逃逸无 lint；refcount 非原子；TSan 仅 nightly/Linux（verify anchors） |
| F6 | L13/L165/L180 | **改写** | box 只省 malloc/free 配对与 sizeof；`--debug-leaks` 当前 `unknown option`（E-09）；直接环 lint 存在 |
| F7 | L39/L179 | **改写** | CT 不禁止指针，但禁止若干所有权形态（Str 字段 E-07、Map<Str> 键 E-08 等） |
| F8 | L56 | **改写** | 字段/Map 键硬错；`Vec<Str>` 元素、`Option<Str>`、ADT 负载允许（E-06/E-08）；补“存的是借用视图”的风险 |
| F9 | 全篇缺失 | **新增** | 加 ADT/match 一节：值类型/无 vtable/绑定副本/无 drop glue；补充实测“构造不 retain、绑定浅拷贝、释放绑定后原句柄悬垂”（E-11，spec 3061/3074） |

## 2 判据矩阵

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 可追溯 | **通过** | claim E1 + verify E-01…E-11；每条断言有 spec/lib/test 行或实测 |
| J-2 保全教学主线 | **通过** | 只改事实与限定词；口诀、三层图、残余风险诚实清单保留 |
| J-3 不引入未实现能力 | **通过** | 删除 `String.concat` / `std::arena` / 字面量方法；改用 `str_concat` / `String s = "x"` |
| J-4 风险边界 | **通过** | 与 spec §4.70/§4.71/§4.73、p79_places、check-tsan 对照；新增 Str 逃逸与 ADT drop glue |
| J-5 版本 | **通过** | 页首 v0.84.1 + PH-84 范围 |
| J-6 可回滚 | **通过** | 只动 `docs/**` 与 `battle/**`，不动实现 |
| J-7 ADT 覆盖 | **通过** | 新指引新增一节，逐条对齐 spec §4.73 |

## 3 用户裁定（2026-11-21）

1. **入 docs 方式**：并存 + 互链。新增 `docs/guide-for-c-programmers.md`；
   `docs/memory-guide.md` 页首标注“旧指针/own 模型，新代码看新指引”，索引两条都列。
2. **F4/F5 口径**：如实写“Str 视图逃逸无编译期兜底，靠契约 + ASan”；另开
   [SH-106](../../issues/selfhost/sh106-str-view-escape-no-lint.md) 评估补 lint，不阻塞文档入库。
3. **F9 范围**：只进新指引；tutorial / patterns 的同步归
   [battle/doc-consistency-1](../doc-consistency-1/verdict.md) 的后续 issue，避免两处重复施工。

## 4 不采纳

- **保留“编译错/协议保证”原措辞**：实测与 spec 均不支持；教学上可保留“建议避免”，
  但不能写成编译器兜底。
- **把“容器硬错”反向扩成“所有容器都允许”**：`Map` 键仍是硬错，且 `Vec<Str>` 存的是
  借用视图；必须分位置写。
- **F9 同步改 tutorial/patterns**：超出本 battle 的 forbidden 范围，归 doc-consistency 后续。

## 5 后续动作

- 修正稿落 `docs/guide-for-c-programmers.md`；`docs/README.md` 增索引；`memory-guide.md` 页首互链。
- 开 SH-106（Str 视图逃逸 lint 评估），挂 `docs/design/phase84.md` 或后续 lint 卡。
- `check-docs` 通过后入库；文档改动可单文件回滚。

## 6 Kimi 修订清单核对（2026-11-21，v0.84.1 实测）

| 项 | Kimi 说法 | 实测 | 处理 |
| --- | --- | --- | --- |
| R1 | 字面量 `.to_string()` 不存在 | **成立**：`no method 'to_string' for type 'char *'`；`String.to_string()` / `Str.to_string()` 合法；std 包的 `CStrOps` 也没有 `to_string` | 去掉字面量式；保留两种合法副本写法并注明区别 |
| R2 | 惯用法是 `"42".to_int()`，`parse_int("42", v)` 应删 | **成立，但前提是 `import std::str::String;`**：std 包 `map trait CStrOps for type char *` 提供 `to_int`；不带 import 时才是 `no method 'to_int' for type 'char *'`。`parse_int(Str, out int)` build rc=0，可作为“自己写 API”的建议保留 | 采纳；主示例改为 `"42".to_int()` + import，自由函数作为 API 设计建议保留 |
| R3 | 调用方未初始化传给 `out` 一律硬错 | **按 spec §4.68 收窄**：`int v; set(v);` 可编译；`String s; take(s);` 硬错 `out owning argument must be initialized`。30Q Q13 的“未初始化一律硬错”未按字面落地 | 按实现写：trivial 可未初始化，owning 必须先初始化 |
| R4 | box 16+8 / 自动解引用 / `at()`；ADT 现在时；memory-guide 关系 | **成立**（`test/ast/p81_box/layout.ct`、spec §4.71/§4.73） | 已补 box 布局注记、§1 ADT 行、memory-guide 互链 |
| R5 | `name_view()` 需核实 | **不存在**（仓库无该符号）；`p.name.as_str()` 与 `make_p().name.as_str()` 均可编译 | 已改为 `as_str()` |

结论：R1/R2/R4/R5 采纳（R2 必须带 `import std::str::String;`）；R3 收窄为“owning 实参”后采纳。

教训：探针必须先加载对应 std 单元；**内置层（自动预解析）与 std 包（`import` + 寄生映射）是两套加载方式**，不能用一个不带 import 的探针否定 std 包能力（本轮 R2 的第一次判定就是反例）。

