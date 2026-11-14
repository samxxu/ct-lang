# 文档导航

> 中文
>
> **当前版本 v0.43.0。** 本目录的 `design/` 保留**最近 12 个已完成阶段**的设计文档（当前在研
> 阶段计入），更早的 `design/phase*.md` 必须退役到 [history/design/](history/design/)；评审报告
> 与其余历史记录在 [history/](history/README.md)。仓库入口见 [../README.md](../README.md)，改动
> 规约见 [../AGENTS.md](../AGENTS.md)。
>
> **语言约定：** 默认中文；英文仅根 [README.en.md](../README.en.md)，供人类阅读，AI 代理不读。

---

## 中文

### 从哪读起

| 文档 | 内容 | 何时读 |
| --- | --- | --- |
| [tutorial.md](tutorial.md) | 逐章入门：安装 → 派发 → 模块 → 内存 → `map`，附命令行速查与常见坑 | 第一次使用 |
| [language-spec.md](language-spec.md) | `.ct` 的语法与展开规则、命名契约、容量上限、明确不支持 | 想知道「这条写法展开成什么 C」 |
| [glossary.md](glossary.md) | 术语表：项目名、语言构造、内部符号 | 读文档遇到生词 |
| [vision.md](vision.md) | 定位、设计原则与生态策略 | 想知道「为什么这样设计」 |
| [architecture.md](architecture.md) | 编译器内部结构与关键算法 | 改编译器 |
| [polymorphism.md](polymorphism.md) | 接口多态与派发 | 设计对象协作 |
| [construction.md](construction.md) | 对象构造语义（vptr 由谁、何时写入） | 排查构造期问题 |
| [patterns.md](patterns.md) | 设计模式在现有特性下的写法 | 判断「要不要新增语言特性」 |
| [memory-guide.md](memory-guide.md) | 内存实践：`own` / `borrow` / 工厂 / 池 / arena | 写持有资源的代码 |
| [package-guide.md](package-guide.md) | 包作者指南：`ct.pkg` 键、命名 / 版本 / tag、索引收录、许可证、常见失败 | 发布或消费一个包 |
| [modern-oo-gap.md](modern-oo-gap.md) | 需求侧评估：以现代化 OO 为参照的差距清单、battle 记录与三档结论 | 判断「还缺哪些语言特性」 |

### 计划与台账

| 文档 | 内容 |
| --- | --- |
| [roadmap.md](roadmap.md) | 简要阶段表：阶段 / 主题 / 状态 / 收口版本 / 详情入口 |
| [history/phase-log.md](history/phase-log.md) | 逐相流水账：Phase 0–42 的详细记录、版本记录、已定决策与待定项 |
| [history/design/phase20.md](history/design/phase20.md) · [history/design/phase21.md](history/design/phase21.md) · [history/design/phase24.md](history/design/phase24.md) · [history/design/phase25.md](history/design/phase25.md) · [history/design/phase26.md](history/design/phase26.md) | 已完成的阶段计划（Phase 20–26）：包支持 / 非逃逸栈闭包 / `loop` 语法糖 / `loop(a..b)` 范围 / 数组 range 初值 / 静态映射调用的闭包实参 / 泛型函数；phase17、phase18、phase19、phase22、phase23 与 phase25–phase31 已按 DOC-66 归档到 [history/design/](history/design/) |
| [history/design/phase27.md](history/design/phase27.md) | 已完成的阶段记录（Phase 27）：`foreach` 语句形态（数组形态已实现，容器协议由 Phase 29 解冻；语法、展开规则与决策见正文） |
| [history/design/phase28.md](history/design/phase28.md) | 已完成的阶段记录（Phase 28，泛型两阶段第一相）：trait 约束的泛型函数与静态派发（语法、落码、E28-1–E28-9 收口核对与 D28-1–D28-11 见正文；未 bump） |
| [history/design/phase29.md](history/design/phase29.md) | 已完成的阶段计划（Phase 29，泛型两阶段第二相）：泛型 struct + 内置 `Vec`/`Map`，解冻 `foreach` 容器协议（`Map` 遍历为硬判据）、`Vec`/`Map` 从 `ct-pkg/std` 迁入 `lib/std/`（std 其余模块不动）（D29-1–D29-16 见正文） |
| [history/design/phase30.md](history/design/phase30.md) | 已完成的阶段计划（Phase 30）：接收者语境块 `<receiver> into { … }`——块内 `.name` 访问接收者成员/方法、`$` 指代自身；`into` 为后置上下文关键字，块结束后仍返回接收者、可继续接后缀链或连续多段 `into`；语句形态与值形态（初始化器 / 赋值 / `return`，结果为接收者本身）；接收者只求值一次并按 value category 提升；`.m.ct` 类型宿主（含 shim）可作接收者、`$ =` 可接链（D30-1–D30-19 见正文） |
| [history/design/phase31.md](history/design/phase31.md) | 已完成的阶段计划（Phase 31）：接口值进容器（`Vec<Show>` / `Map<char *, Show>`）与嵌套容器的元素寿命与所有权、`v[i]` / `m[k]` 仅展开为 `get`、`Vec` / `Map` 花括号初值（E31-1–E31-23、L31-1–L31-21、D31-1–D31-17 见正文） |
| [design/phase32-draft.md](design/phase32-draft.md) – [design/phase42-draft.md](design/phase42-draft.md) | 阶段草案（Phase 32–42，均已完成）：类型安全网 / 有界泛型 struct / 生态可用性 / 泛型 trait / 泛型 Drop 与 `Str` / trait 签名硬错与运行期契约 / `defer` / C ABI 与库制品 / `errdefer` 错误出口 / 原子并发（`atomic T`）/ `impl` 方法可见性；状态以 [roadmap.md](roadmap.md) 为准 |
| [design/phase43.md](design/phase43.md) · [design/phase44.md](design/phase44.md) · [design/phase45.md](design/phase45.md) | 已定稿待实施（Phase 43–45）：错误出口类型契约（`return err:` 载荷检查）/ `?` 错误传播运算符 / 类型契约一致性（闭包 `return` 与指针基类型判据）；状态以 [roadmap.md](roadmap.md) 为准；未立项评估结论与门禁欠账见 [planning/requirements-pool.md](planning/requirements-pool.md) |
| [proposals/ct-pkg-agent-runtime.md](proposals/ct-pkg-agent-runtime.md) | ct-pkg `std` 的 Agent 内核运行库提案：`arena` / `sync` / `result` / `string` / `callback` 契约与交付顺序 |
| [../issues/README.md](../issues/README.md) | 审查发现台账（每条一文件，含状态与处置） |
| [history/README.md](history/README.md) | 历史档案索引：已关闭阶段的设计记录与评审报告 |

目录级说明：[../selfhost/README.md](../selfhost/README.md)（四代编译器与门禁脚本）、
[../test/README.md](../test/README.md)（测试分层）、[../test/bindings/README.md](../test/bindings/README.md)（binding 规约）。

### 文档约定（由 `test/docs/check-docs.py` 校验）

1. **语言**：默认中文；英文仅根 [README.en.md](../README.en.md)（人类阅读，AI 不读）；其他文档不写英文段。
2. **相对链接必须可解析**。唯一豁免：`docs/history/reports/**` 里指向当时存在、现已删除的
   `selfhost/ast/**` 与 `selfhost/src/**` 的链接（历史快照，正文不改写）。
3. **版本标记**：`README.md` 与本文出现的 `vX.Y.Z` 必须是当前版本（取自 `selfhost/l0/ctc.c` 的 `CTC_VERSION`）。
   历史版本只出现在 [history/phase-log.md](history/phase-log.md) 的版本记录与 [history/](history/README.md)。
4. **门禁条数**：`README.md`、本文与 [glossary.md](glossary.md) 写出的硬门禁条数必须等于
   `selfhost/check-all.sh` 实际运行的条数（当前共 11 道硬门禁）。
5. **阶段状态**：`docs/design/phase*.md` 的状态行（完成 / 实施中 / 规划中）必须与 [roadmap.md](roadmap.md)
   的简要阶段表一致（✅ / 🟨 / ⬜）；详细证据见 [history/phase-log.md](history/phase-log.md)。
6. **路线图与流水账**：[roadmap.md](roadmap.md) 只做简要索引，不写逐相叙述；逐相细节、版本记录与决策全文在
   [history/phase-log.md](history/phase-log.md)。

校验脚本是 [../test/docs/check-docs.py](../test/docs/check-docs.py)，已接入 `check-all.sh`。
