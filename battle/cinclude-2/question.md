# battle/cinclude-2 — 外部库/用户默认 strict，`.m.ct` 能否作为 include 边界

| 字段 | 值 |
| --- | --- |
| 争点 | 在“CT 核心/1.0 前代码豁免、外部库与用户代码默认严格、手动申明放开”的前提下，`.m.ct` 是否允许 `#include`，以及 strict 的边界与默认层级 |
| 当前 HEAD | `729369fa`（v0.63.2；cinclude-1 已关闭） |
| 触发理由 | 用户收紧范围：只限制库与用户代码，CT 自身 1.0 前不限制；要求继续 battle `.m.ct` 的可行性 |
| proposer | REQ（主张 A：`.m.ct` 可 include，作为映射边界） |
| opposition | REVIEW（主张 B：`.m.ct` 只允许自有 shim 头，系统头只能进 shim） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`lib/std/**`、`docs/language-spec.md`、`docs/design/**`、`docs/proposals/**`；只写 `battle/cinclude-2/` 与 `/tmp` |

## 位置 A（`.m.ct` 可 include）

1. **范围**：CT 核心（`selfhost/**`、仓内 `lib/std`、examples/test 等 1.0 前代码）豁免；**外部库与用户代码**默认 strict。
2. `.ct` / `.h.ct` 默认不得直接 `#include`；C 库必须经 `.m.ct` 映射或 `.shim.h/.c` 封装。
3. `.m.ct` 允许 `#include`/`#define`：它本来就是映射单元，是“封装边界”，不是实现代码；已有 prologue 机制可复用。
4. strict 还覆盖 `#ct-raw`、`extern`、函数式 `#define` 等直接 C 边界；唯一允许的是 `.m.ct` prologue 和 `<base>.shim.h`。
5. 默认 strict，按包/文件显式 `allow-c-boundary` 放开；CT 核心由内部 flag/清单豁免。
6. `.h.ct` 若需要公开 C 类型，通过 `.m.ct`/shim 暴露；不直接 include。

## 位置 B（`.m.ct` 只允许自有 shim 头）

1. 范围同 A：CT 核心豁免，外部库/用户默认 strict。
2. 但 `.m.ct` 只能 `#include "<base>.shim.h"`（以及编译器生成的 shim），**不得直接 include 系统/第三方 C 头**；系统头放进 `.shim.h`。
3. 理由：`.m.ct` 的 `map` 可以直接把任意 C 函数暴露成 CT 方法；若允许任意 include，strict 只是把绕过从 `.ct` 搬到 `.m.ct`，并未强制封装。
4. `.h.ct` 也需要自有 shim 头机制；当前 `.h.ct` 的姊妹 `.shim.h` 被忽略，需扩展。
5. strict 覆盖 raw/extern/define；包/文件 opt-in；CT 核心豁免。
6. 默认 strict 应是**包/构建策略**，不是 parser 对语言的无条件默认；`ct.pkg`/CLI 决定。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 范围与豁免：CT 核心/1.0 前代码不破坏；外部库/用户默认 strict 可机械启用 | 构建矩阵 + 包/CLI 配置 |
| J-2 | `.m.ct` include：任意 C 头 vs 仅自有 shim；是否仍能表达真实 C 库 | 映射夹具 + 真实绑定样例 |
| J-3 | `.h.ct`/公开 C 类型：默认 strict 下是否可用，shim 探测/部署是否足够 | 公开头夹具 + 生成头检查 |
| J-4 | 绕过面：raw/extern/define/shim 内容/链接；strict 能否 sound | 7 类绕过探针 |
| J-5 | 迁移：外部包/用户代码/旧代码；grandfather/opt-in 成本 | 文件统计 + 包清单 |
| J-6 | 默认层级与回退：parser 默认 vs 包/CLI；诊断与关闭开关 | 开关/负例/回滚演练 |

## 证据要求

按 §7.7 E1–E5：完整命令/原始输出、`file:line`、可证伪预测、代价量化、对对方最强论点的 steelman。重点：`.m.ct` 任意 include 后能否直接 map `printf`；`.m.ct` 是否能声明状态/类型；`.h.ct` shim 现状；CT 核心 include 依赖；strict 的 7 类绕过。
