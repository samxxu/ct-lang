# battle/p42-1 判决

> **状态：`closed`**（2026-11-13；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **结论：C 胜出**——删除保留名豁免，52 条全部显式 `pub`；生成代码跨单元/foreign 元素调用未 `pub` 的 `retain`/`release` 时报 L42-6，不自动公开、不留给 `cc`。

## 1 争点与判据

| ID | 判据 | 权重 |
| --- | --- | --- |
| J-1 | 未写 `pub` 的方法不得进 `.h`、不得 external；用户同名方法不被自动公开 | 否决项 |
| J-2 | 生成代码跨单元元素调用可链接 | 否决项 |
| J-3 | 迁移可机械核对，不依赖名字特判 | 高 |
| J-4 | 实现代价与单一真源 | 中 |
| J-5 | header/ABI 不变式 | 高 |

## 2 事实（evidence-p42-1 / verify.json）

- 总集合 **52 = std 43 + 其它 9**；按 impl 种类是 44 模板 + 8 非模板固有。
- 名字匹配 `retain|release` 的 10 条（4 retain + 6 release）；满足元素协议（`retain` 返回自身类型 + `release` 同时存在）的 **8 条**（Str/Vec/Map/Box 各一对）。
- `Option::release` / `Result::release` 不满足协议，生成代码的元素 helper 对它们是 `(void)e`，不按名调用。
- 生成代码按名跨单元调用的只有 `<Elem>_retain` / `<Elem>_release`（`Emitter.h.ct:2017/2023/2026`）；`drop`/`handback` 是 trait impl 或 static，`.h.ct` 中 0 条固有定义；唯一 `drop()` 在 `impl Drop for Str`（`Str.h.ct:24`），恒 `static`。
- 翻默认的模拟（定义改 static、删 `.h` 原型）在 plain 与模板实例上都得到 `cc -Wundefined-internal` + `ld: symbol(s) not found`；说明显式 `pub` 是链接正确性的开关。
- C 的 L42-6 对链接不是必要件（作者写 `pub` 就成功），但它是 C 自己承诺「不把错误留给 cc」的必要件；触发条件必须是**跨单元/foreign 元素**，单单元私有元素（`test/ast/227`、`errors/double_drop`）不得误杀。
- B 的谓词按**类型结构**，不接收「是否被当元素用」；因此 B 会把从未作元素使用的 `Probe` 的 `retain`/`release` 自动公开（与 J-1 字面冲突）。B 的 8 条比 A 的 10 条精确，但仍不是 opt-in。
- 52 条全补 `pub` 后既有 `.h` 原型集合不变；B 的 8 条自动公开也不改变 `.h`。`expected.internal` 在 HEAD 无 `--lib` 夹具可核对（未复现），E42-6 必须用含 `impl` 的 `--lib` 夹具。

## 3 逐条判决

| J | C | B | A | 说明 |
| --- | --- | --- | --- | --- |
| J-1 | **pass** | fail（字面） | fail | B 自动公开 8 条协议方法；A 按名字公开 10 条；C 无自动公开 |
| J-2 | pass | pass | pass | 显式 `pub` / 自动公开都能链接；真正跨单元只有 Str/Box，容器元素调用多在模板所属单元内 |
| J-3 | **pass** | pass | fail | C 52 条全列；B 44+8；A 纯名字不可机械核对 |
| J-4 | **pass** | unresolved | pass（简单但泄漏） | C 只需一个方法标记；B 的谓词按 owner 种类分叉（plain 用 `decl_is_pub`，模板实例用 `tps[tmpl].is_pub`），且 `Expr` 还有名字-only 判定 |
| J-5 | pass（前提迁移完整） | pass（同） | pass（同） | 迁移后 `.h` 原型集合不变；expected.internal 需新夹具，双方都未完全复现 |

## 4 判决

**C 胜出。** 理由按判据顺序：

1. **J-1 是否决项**：方法级 `pub` 的唯一含义是「写 `pub` 才公开」；B 的 8 条自动公开是对该原则的例外，且按类型结构而非使用点，无法限制在「真的被当元素用」的实例上。A 的 10 条更宽，且 `drop`/`handback` 无证据。
2. **J-4 的单一真源**：C 只增加 `N_METHOD.d` 一个标记；B 需要在 plain struct 与模板实例之间分叉，且在发射期重新求值 `elem_has_life`，仍有 `Expr` 的名字-only 判定。C 的实现面更小、更可解释。
3. **J-3 可核对**：C 的迁移清单就是 52 条方法；B 的 44+8 也机械，但 8 条自动公开需要额外的「为什么这 8 条不需要 `pub`」说明，增加评审面。
4. **J-2/J-5 不构成 B 的优势**：两者都能链接、都能保持 `.h`；B 省掉的 8 条 `pub` 不足以抵消 J-1/J-4。

## 5 被否方案

- **A（现稿 D42-6，10 条按名字无条件公开）**：`drop`/`handback` 无固有定义；按名字公开会命中任意用户同名方法；与 J-1/J-3 冲突。否决。
- **B（8 条协议自动公开）**：比 A 精确，但仍不是 opt-in；谓词按类型结构，无法限定使用点；迁移 44+8 与 C 的 52 是同一集合的两种记账，不构成独立优势。否决。

## 6 落卡要求（C）

- 删除 D42-6 的保留名豁免与 L42-6 旧文案；改为 **52 条全部显式 `pub`**（std 43 + 其它 9）。
- 新增 **L42-6**：`element protocol method 'retain' must be pub`，仅当生成代码在**跨单元/foreign** 元素调用点发现目标方法未 `pub` 时触发；单单元私有元素不报。
- `drop`/`handback` 按 D42-8 排除（trait impl / static），不进入迁移清单，不做名字特判。
- 迁移清单必须剥注释、跳过 `impl … for …`；std 43 = Option 8 / Result 11 / Str 2 / Vec 22；其它 9 条按 S0 冻结清单。
- E42-5 的计数从「42 手工 + 10 保留名」改为 **52/52 手工**；§6.1 脚本必须输出 `std 43 / other 9 / all 52`。
- `Option::release` / `Result::release` 即使不被生成代码调用，也随 52 条补 `pub`，以保持既有 `.h` 原型集合不变；不得以「没被调用」为由跳过。
- E42-6 的 ABI 证据必须用含固有 `impl` 的 `--lib` 夹具，不能只用 `p39_lib`（无 impl）与 `ABI_HASH`（只遍历自由函数）。
- 任务顺序：R1 解析 `pub` 并写 `N_METHOD.d` → R2/R3 迁移 52 条 → R4 切换判定/翻默认；不得在迁移前切换，也不得保留 `|| decl_is_pub(N_STRUCT)` 双模式。
