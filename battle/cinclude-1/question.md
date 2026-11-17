# battle/cinclude-1 — 是否默认禁止 `.ct` 直接 include C 头

| 字段 | 值 |
| --- | --- |
| 争点 | 用户提案：`.ct` 默认禁止直接 `#include` C 库；C 库必须经过封装，只有 `.shim.c/h` 可以 include。是否采纳、边界与迁移方式 |
| 当前 HEAD | `85579c4d`（v0.63.2） |
| 触发理由 | 用户认为直接 include 会让作者绕开 CT 基础库封装；要求用 battle 决定是否改为默认禁止 |
| proposer | REQ（主张 A：默认禁止） |
| opposition | REVIEW（主张 B：默认允许 + 可选严格模式/包策略） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`lib/std/**`、`docs/language-spec.md`、`docs/design/**`；只写 `battle/cinclude-1/` 与 `/tmp` |

## 位置 A（默认禁止）

1. `.ct` / `.h.ct` / `.m.ct` 默认不得出现 `#include`；C 声明只能通过 `.shim.h` 暴露，实现通过 `.shim.c`。
2. 现有 688 个含 `#include` 的 `.ct` 文件必须迁移；迁移期用显式 `allow-c-include` 文件/包标记 grandfather，默认关闭。
3. 编译器自身（`selfhost/ct-ast`）与 `lib/std` 也必须按 shim 迁移，不能永久豁免；否则规则不成立。
4. `#ct-raw`、`extern` 声明、`.m.ct` prologue 等同属“直接 C 边界”，一并限制或至少纳入同一策略。
5. 目的：强制 C 库经过一次封装，避免绕开 CT 基础库；新代码默认干净。

## 位置 B（默认允许 + 严格模式/包策略）

1. 语言默认保留 `#include`（C 超集是既有契约）；新增 `--strict-c-include` 或包清单 `c-include = forbid`，由项目/包主动启用。
2. 编译器、`lib/std`、examples 不因全局默认被破坏；新包可默认 strict，旧包逐包迁移。
3. `.m.ct` + `.shim.h/.c` 继续作为官方封装路径；`.h.ct` 的 C 互操作保留。
4. 若要“默认禁止”，先做 lint/迁移工具与全部语料迁移，再改默认；不能直接翻默认。
5. 目的与 A 相同，但用包级策略而非语言级 breaking change 达成。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 自举/基础库：默认禁止后 `ct-ast` 与 `lib/std` 能否构建，是否必须永久豁免 | 构建矩阵 + 依赖清单 |
| J-2 | C 互操作：厂商 HAL/SDK、binding、`.m.ct`/shim 是否仍可表达，成本多少 | 现有 binding 夹具 + 迁移样例 |
| J-3 | 可执行性：只禁 `#include` 是否真能阻止绕过（`extern`、`#ct-raw`、`.m.ct`、`#define`、C 文件） | 绕过探针与门禁设计 |
| J-4 | 迁移成本：688 文件、examples/test、std、版本/兼容窗口 | 文件/行数统计 + 迁移切片 |
| J-5 | 兼容性：C 超集/既有规范/包消费者是否被破坏 | 规范条款 + 全量门禁 |
| J-6 | 策略形态：语言默认、包策略、严格模式三者哪个可机械验收且可回退 | 诊断/清单/回滚演练 |

## 证据要求

按 §7.7 E1–E5：完整命令/原始输出、`file:line`、可证伪预测、代价量化、对对方最强论点的 steelman。重点统计 `#include` 在 selfhost/lib/std/examples/test 的分布，`.m.ct`/shim 的现有契约，`#ct-raw`/`extern` 的绕过面，以及全量门禁对 include 的依赖。
