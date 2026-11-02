# DOC-54 · 单元种类、命名与 import 解析规则未在 spec / tutorial 收口

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium**（教程与 spec 表面矛盾，影响用户对 `.m.ct` 的判断；命名规则归属不清） |
| 锚点 | `v0.16.2`，commit `dab1b71`（2026-11-02） |
| 文件 | [tutorial.md:281](../../docs/tutorial.md#L281)、[:760](../../docs/tutorial.md#L760)、[language-spec.md:489-493](../../docs/language-spec.md#L489-L493)、[:2103-2108](../../docs/language-spec.md#L2103-L2108)、[glossary.md:88](../../docs/glossary.md#L88) |
| 状态 | 已修（2026-11-02，`v0.16.3`）：教程 §7 中英补 `.m.ct`；spec §4.10 中英加单元种类表、import 搜索顺序与命名约定归属 |
| 来源 | `ct-mac-gui-example/docs/ct-naming-and-import-issues.md`，经本仓库逐条复核后收窄 |

## 现象

1. **教程把 import 说得比实际窄。** [tutorial.md:281-282](../../docs/tutorial.md#L281-L282) 写
   「`import x;` 只接受 `x.h.ct`，普通 `.ct` 不发布接口」，英文 [:760-762](../../docs/tutorial.md#L760-L762)
   同；但 `resolve_import` 在每个 root 里先探 `x.h.ct`、再探 `x.m.ct`，两者都没有才查 `x.ct` 并报错
   （[Module.h.ct:248-310](../../selfhost/ct-ast/frontend/module/Module.h.ct#L248-L310)）。
   即 `.m.ct` 可被 import，教程把它隐藏了。
2. **spec 有规则、没有一张收口表。** §4.10 的中文 [:489-493](../../docs/language-spec.md#L489-L493)
   与英文 [:2103-2108](../../docs/language-spec.md#L2103-L2108) 已写全「`.m.ct` 无产物、只能被 import、
   `ct compile` 拒绝、同 root 并存歧义、映射单元只能 import 映射单元」，但没有「后缀 / 发布 `.h` /
   可 import / 可单独 build」的对照表；读者需要拼接散落的三段。
3. **命名规则未进 spec / tutorial。** 规则在 [glossary.md:88](../../docs/glossary.md#L88)（
   `Parser.h.ct` ↔ `struct Parser`，一个单元一个主类型，`main.ct` 例外）并在
   [:90](../../docs/glossary.md#L90) 标为「已发布命名规则」；`check-ast.sh:215-227` 只扫描
   `selfhost/ct-ast/**`；编译器不检查、不告警。spec 与 tutorial 均未提，读者无法判断
   「这是约定还是规则」。

## 复核订正（相对于来源文件）

- 来源写「spec §9.1」——**引用有误**，规则在 **§4.10**（中英同号），§9.1 不是该节。
- 来源建议「补三条门禁」——**已存在**，无需新增：
  - 普通 `.ct` 不可导入：`check-ast.sh:1262` 断言
    `only a .h.ct unit can be imported: rename 'helper.ct' to 'helper.h.ct'`；
  - `.h.ct` + `.m.ct` 同 root 歧义：`check-ast.sh:1497` 断言 `import 'foo/foo' is ambiguous: both`；
  - `.m.ct` 导入另一个 `.m.ct`：`check-ast.sh:631` 的 `map_unit_chain` 正例（含缓存重生）。
- 来源写「命名规则只存在于 glossary / lint，用户不可见」——**不准确**：glossary 是用户文档，且
  [:90](../../docs/glossary.md#L90) 已称其为「已发布命名规则」；真正的缺口是 **spec / tutorial 未写**，
  以及「已发布」是否等于「编译器强制」没有一句话说清。
- 来源表格本身成立：`.ct` 不产接口 / 可单独 build；`.h.ct` 发布 `.h` / 可 import / 可单独 build
  （`ct build <unit>.h.ct` 实测返回 0，见 [DOC-51](doc51-tutorial-impl-unit-import.md) 的订正段）；
  `.m.ct` 无产物 / 只能 import / `ct compile` 拒绝 / 只能 import 另一个 `.m.ct`。

## 采纳与不采纳

**采纳（文档）**

1. 修正 [tutorial.md:281](../../docs/tutorial.md#L281) 与 [:760](../../docs/tutorial.md#L760)：
   「接受 `x.h.ct` 或 `x.m.ct`；普通 `.ct` 不可导入；同 root 下两者并存报歧义」。
2. 在 spec §4.10 中英各加一张「单元种类」表，并写一句 import 搜索顺序
   （importer 目录 → `-I` 顺序；先 `.h.ct` / `.m.ct`，再 `.ct` 报错）。
3. 在 spec §4.10（或 §6.2 交叉引用处）写一句命名规则归属：
   **`.h.ct` 文件名 = 主类型名是仓库约定，不是编译器规则；`check-ast.sh` 的 lint 只覆盖
   `selfhost/ct-ast/**`，用户工程不受检查**（建议取来源的 A 方案）。

**不采纳**

- **不新增 `ct lint`，也不在 `ct build` 做 basename ↔ 主类型检查**：那是编译器行为变更
  （AGENTS §2 需用户授权），且会把既存用户工程判为不合规；命名是项目约定，用文档 + 仓库内 lint 足够。
- **不补三条 import 门禁**：已有断言（见上），再加只会重复覆盖。

## 修复建议

只动三份文档：`docs/tutorial.md`（中英两处）、`docs/language-spec.md`（§4.10 中英各一表 + 两句话）。
无需改 `selfhost/**`、无需改测试、无需 bump 版本。

## 验收

- [ ] tutorial 中英两处不再写「只接受 `x.h.ct`」，明确列出 `.h.ct` / `.m.ct` 与歧义；
- [ ] spec §4.10 中英各有一张单元种类表，含「发布 `.h` / 可 import / 可单独 build / 用途」四列；
- [ ] spec 写明 import 搜索顺序与普通 `.ct` 的报错；
- [ ] spec 写明命名规则是**约定**、lint 范围仅 `selfhost/ct-ast/**`；
- [ ] `bash selfhost/check-all.sh` 不受影响（仅文档改动）。

## 关联

- [DOC-51](doc51-tutorial-impl-unit-import.md)：同一页 §7 的 `.ct` / `.h.ct` 修正；本条是它的补充
  （修正后仍漏 `.m.ct`）。
- 规则出处：[language-spec.md §4.10](../../docs/language-spec.md#L399)、
  [glossary.md:44](../../docs/glossary.md#L44)（映射单元定义）。
