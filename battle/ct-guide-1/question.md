---
id: ct-guide-1
head: 32e3e482
trigger: B-5（用户 2026-11-21 提交《给 C 程序员的 CT 内存指引》，与 Kimi 合写）
proposer: REVIEW
opposition: REQ
judge: EDITOR
forbidden: selfhost/**, test/**, docs/**
---

# battle/ct-guide-1 — 《给 C 程序员的 CT 内存指引》哪些断言必须按 v0.84.1 实现改写，并补齐 ADT/match

## 争点

指引的教学骨架（心智地图、String/Str 判据、逃生层、残余风险清单）成立；争点分两层：

- **事实层（F1–F8）**：指引按“目标形态/教学简化”写的地方，是否已经越过 v0.84.1 的实际实现；
  绝对化措辞（“永远”“无”“不禁止任何东西”“只出现在”）是否应改为带条件的表述；
  示例 API 是否真实存在、参数语义是否正确。
- **覆盖层（F9）**：指引页首基线停在 v0.83.x，PH-84 的 ADT/match 完全未进入“内存指引”。
  对 C 程序员而言，ADT 就是 tagged union；其所有权规则（值类型、无 vtable、
  match 绑定是副本、owning payload 不自动释放）必须有一节，否则“指引”名不副实。

基线：**v0.84.1**（`ct v0.84.1`；PH-78 ref/out、PH-79 切片、PH-80 String/Str、
PH-81 box/new、PH-84 ADT/match 均已落地）。

不讨论文风、章节顺序、篇幅；只裁定“必须改 / 可保留 / 待实测”。

## 待裁定条目（F1–F9）

| ID | 指引位置 | 断言 | 争议 |
| --- | --- | --- | --- |
| F1 | L53/L92/L151 | String 数据“永远在它拥有的堆上”；String 字段 ✅ | 与 immortal 字面量、字段无自动 Drop 冲突 |
| F2 | L14/L85/L132 | `"x".to_string()`；`Str.slice(1, len-1)`；`String.concat`；`std::arena` | 四个 API/包是否真实存在、参数是长度而非 end |
| F3 | L153 | `ref`/`out` “生命周期 = 本次调用” | spec 明确 ref 可被存储/传给更长寿命位置，语言不做借用检查 |
| F4 | L105 | `make_person().name_view()` 是“编译错” | 已实测：临时接收者取视图可编译；返回局部 Str 视图也无 lint |
| F5 | L57/L124/L167 | 悬垂风险“无（协议保证）”；不可变共享“无副作用” | 返回局部视图已实测可编译无 lint；refcount 非原子；同文 §6 已承认跨线程风险 |
| F6 | L13/L165/L180 | box “省掉泄漏” | 环与未配对 handle 仍泄漏；同文 §6 已承认 |
| F7 | L39/L179 | “CT 不禁止任何东西”；“指针只出现在 shim 和寄存器” | 语言有多处硬错；同文 L35/L144 已说指针合法 |
| F8 | L56 | Str 存字段/容器“❌ 类型硬错（四位置白名单）” | 已实测：struct 字段与 `Map` 键硬错；`Vec<Str>` 元素、ADT 负载均编译通过 |
| F9 | 全篇缺失 | 未覆盖 v0.84 ADT/match 的内存所有权 | 需补：值类型/无 vtable/绑定副本/owning payload 无 drop glue/上限 |

## 判据（J-1…J-7）

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 每条断言可追溯到 spec/lib/test/实测的具体位置 | 证据行号 + 命令输出；无出处即不通过 |
| J-2 | 纠错不破坏教学主线（判据/口诀/诚实清单保留） | 对照原文章节，只改事实与限定词 |
| J-3 | 不引入未实现 API/包（`String.concat`、`std::arena`、字面量方法） | 替换为已存在写法或删除 |
| J-4 | 风险表述与线程/环/字段 Drop/悬垂的真实边界一致 | 与 §6、spec §4.70/§4.73 对照 |
| J-5 | 页首适用版本写 **v0.84.1**，并列出 PH-84 新增范围 | 页首 + 脚注 |
| J-6 | 修正可单文档回滚，不牵动实现 | 只改指引文本 |
| J-7 | ADT/match 有独立小节，且把“无 drop glue、payload 作者释放”写成显式风险 | 小节存在 + 与 spec §4.73 逐条对照 |

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | REVIEW（按实现核对，提出必改项与新特性补齐） |
| opposition | REQ（指引作者侧，可主张“目标形态/教学简化”保留） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/**`（指引为附件，verdict 前不直接改） |

- 证据按 §7.7 E1–E5 提交；每轮至少新增 1 条 E1/E2。
- 最多 3 轮；F8 已实测，不再以“待验证”结案。
- verdict 通过后，修正稿落入 `docs/`（路径由 EDITOR 裁定）。
