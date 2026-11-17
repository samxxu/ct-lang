# Phase 65 — 严格 C 边界（外部库/用户默认 strict）

> **状态：实施中**（2026-11-17 立项；卡已冻结；S0 已完成，R1 待做）。
> **基线**：当前 `HEAD 0e541f32`（`v0.63.2`）；S0 记录实际 sha 与门禁数字。
> **文档形态**：`phase65-draft.md`；design window 7/12。
> **依据**：[battle cinclude-2 判决](../../battle/cinclude-2/verdict.md)、[cinclude-1 判决](../../battle/cinclude-1/verdict.md)、[硬件需求](../planning/hardware-readiness-requirements.md) 的 C 边界部分。
> **规模**：编译器/工具 180–320；夹具 120–220；文档 50–90；合计 **350–630**（±40%）。
> **纪律**：不收口不 bump；tag/push 按 6.7 V-7 / 6.5；不改 CT 仓内 1.0 前代码的既有 include。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-65 |
| 目标 | 外部库/用户代码默认 strict：`.ct/.h.ct` 禁直接 include，`.m.ct` 作为映射边界允许 include；C 边界可由包/CLI 显式放开；CT 仓内 1.0 前代码豁免 |
| 范围 | O1/O2/O3；不做 parser 无条件默认、不做 shim 内容审计、不要求外部包一次性全迁 |
| 交付物 | `Parser.h.ct` / `Module.h.ct` / `tool/pkg/Pkg.h.ct` / `tool/driver/Driver.h.ct` / `Emitter.h.ct`；`test/ast/**`；文档 |
| 任务清单 | §4.1（R1–R7，共 7 项） |
| 退出判据 | E65-1…E65-8（§5） |
| 依赖 | battle cinclude-2；PH-64 收口；规范 1.15.0 |
| version-minor | 64（PH-65，`d=1`，见 AGENTS §0.3） |
| 已知风险 | R65-1…R65-7（§7） |

## 1 需求与边界

### 1.0 AN-65（四段）

| 段 | 内容 |
| --- | --- |
| 问题 | `.ct` 直接 include C 头会让作者绕开 CT 库封装；但语言默认禁止会破坏 C 超集、自举、公开 `.h` 与 688 个仓内文件 |
| 范围 | 外部库/用户代码默认 strict；`.ct/.h.ct` 禁直接 include；`.m.ct` 作为映射边界允许 include；`.shim` 与 `.h.ct` shim；包/CLI 显式 allow；CT 仓内 1.0 前代码豁免 |
| 验收 | E65-1…E65-8 可在 `check-ast.sh` / `check-docs.py` / `check-all.sh` 上机械核对 |
| 依赖与风险 | strict 是 guardrail，不是 sound 沙箱；`.m.ct` 仍可 map C；shim 内容/链接仍可绕过；外部包需迁移窗口 |

### 1.1 一句话

默认 strict 只针对**外部库/用户代码**；`.ct/.h.ct` 的直接 `#include` 默认报错，`.m.ct` 和 `.shim.c/h` 是显式边界；CT 仓内 1.0 前代码不限制；要放开必须显式声明。

### 1.2 三项

| 编号 | 内容 | 今天 |
| --- | --- | --- |
| O1 | 作用域与默认：CT 仓内 `selfhost/**` / `lib/std/**` / `test/**` / `examples/**` 豁免；外部默认 strict；包/CLI `c-boundary=allow` 显式放开 | 无策略层，全部允许 |
| O2 | 边界：`.ct/.h.ct` 禁直接 include；`.m.ct` 允许 include（只对象式/常量宏）；`.shim` 允许；`#ct-raw`/extern/函数式 `#define` 在 strict 下禁 | `.m.ct` prologue 允许 include，`.h.ct` 可直通，raw/extern 无检查 |
| O3 | `.h.ct` shim：探测/部署 `<base>.shim.h`，公开头带 shim、`ct build` 自动 `-I` | 姊妹 `.shim.h` 被忽略，公开 C 类型只能直通 include |

### 1.3 非目标

- 不做 parser 无条件默认禁止（会命中 688 个仓内文件并破坏 C 超集）。
- 不要求 CT 仓内 `selfhost/**`、`lib/std/**`、`test/**`、`examples/**` 迁移。
- 不声称 strict 能封死 `#ct-raw`、shim 内容、`--ldflags` 外链 `.c`；这些是受控/审计出口。
- 不做 shim 内容审计、符号级白名单、所有外部包一次性迁移。
- 不改 `.m.ct` 零产物/静态 trait 语义；不把 `.m.ct` 变成实现单元。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D65-1 | 默认 strict 只对外部库/用户代码；CT 仓内四类路径豁免 | 688 个 include 全在四类内；避免重蹈语言默认禁止 |
| D65-2 | strict 由包/CLI 决定，不做 parser 全局默认 | 可回退、可 grandfather、可让 CT 核心用内部 flag |
| D65-3 | `.ct/.h.ct` 禁直接 include；`.m.ct` 允许 include | `.m.ct` 是映射单元/显式边界；`.ct/.h.ct` 是实现/公开面 |
| D65-4 | `.m.ct` 只允许 `#include` + 对象式/常量宏；函数式宏走 shim | prologue 宏可把任意 C 带进消费者，必须收窄 |
| D65-5 | strict 同时禁 `#ct-raw`、`extern` 原型/裸 C 调用、函数式 `#define` | 只禁 include 会被 7 类通道绕过 |
| D65-6 | `.h.ct` 必须有自有 shim；探测/部署/`-I` 与 `.m.ct` 同源 | 公开 C 类型不能靠直通系统头 |
| D65-7 | `ct.pkg` 增 `c-boundary = strict|allow`；`ct build`/`ct pkg check` 读取；未知键不得再静默 | 包级默认与可审计 |
| D65-8 | strict 是 guardrail；shim 内容/链接外部 C 仍可绕过，文档写明 | 不把文件边界冒充安全沙箱 |

## 2 现状与基线

### 2.1 门禁基线

S0 在 `0e541f32` 上冷构建 `ct`（`ct -v` = `v0.63.2`），记录 `check-ast` / `check-warnings` / `test/run` / `check-docs` 基线；不沿用旧卡数字。

**S0 实测（2026-11-17）**：`selfhost/check-ast.sh` → `1463 passed, 0 failed, 0 skipped`（exit 0）；`tools/check.sh g0` → OK（1.15.0）；`check-docs.py` → 1795 links / 286 files。

### 2.2 设计探针

| 探针 | 结果 |
| --- | --- |
| 688 个 `.ct` 文件含 `#include` | 全部落在 `selfhost/**`、`lib/std/**`、`test/**`、`examples/**`；仓内迁移面 0 |
| `.m.ct` 直连系统头并 map C | rc=0，生成 `.c` 带 include；可行，但可绕过封装 |
| `.h.ct` 的 `#include` | 复制进公开 `.h`；姊妹 `.shim.h` 被忽略 |
| strict 开关 | `c-boundary` / `--allow-c-boundary` 当前不存在；`ct.pkg` 未知键被忽略 |
| 绕过面 | `#ct-raw`、extern、函数式 `#define`、shim 内容、`--ldflags` 外链 `.c` 均 rc=0 |

### 2.3 代码锚点

`Parser.h.ct` 的 `.m.ct` prologue 白名单、`Module.h.ct` 的 `is_map`/shim 探测、`Emitter.h.ct` 的 shim 头发射、`Pkg.h.ct` 的 `ct.pkg` 读取、`Driver.h.ct` 的 build 参数。

## 3 语义与落码

### 3.1 作用域

- 豁免：`selfhost/**`、仓内 `lib/std/**`、`test/**`、`examples/**`；由路径/内部 flag 判定。
- 外部库/用户代码：默认 strict；`c-boundary = allow` 或 CLI `--c-boundary=allow` 放开。
- CT 核心构建：内部传 `--c-boundary=allow`（或等价），不要求用户看见。

### 3.2 strict 规则

- `.ct` / `.h.ct`：直接 `#include` 硬错；唯一允许 `#include "<base>.shim.h"`（自有 shim）。
- `.m.ct`：允许 `#include`；`#define` 只允许对象式/常量宏；函数式宏/宏 recipe 调用 C 走 shim。
- `.shim.c/.h`：允许 C 头与 C 实现；是受控出口。
- `#ct-raw`、`extern` 原型/裸 C 调用、函数式 `#define`：strict 下禁（`#ct-raw` 仅允许非 C 的 asm？v1 先禁）。
- 诊断：文件:行:列 + 类别 + 允许的 shim 路径；rc=1，不落 C。

### 3.3 `.h.ct` shim

- 探测 `<base>.shim.h`（与 `.h.ct` 同目录同名）；存在则公开 `.h` 自动 `#include "<base>.shim.h>"`，`ct build` 加 `-I`；
- shim 基名歧义硬错；
- 公开 C 类型由 shim 提供；不把系统头复制进公开 `.h`。

### 3.4 包/CLI

- `ct.pkg`：`c-boundary = strict|allow`；缺省按外部默认 strict；`local`/CT 核心包允许；
- `ct build --c-boundary=strict|allow`；`--allow-c-boundary` 作为内部/兼容别名；
- `ct pkg check` 读取；未知键仍 warning/ignore 规则保持，但 `c-boundary` 必须识别；
- 旧外部包：缺省 allow 窗口 + 迁移清单；新包默认 strict。

### 3.5 诊断（L65-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L65-1 | strict 下 `.ct/.h.ct` 直接 include | `a strict C boundary forbids '#include'; use .m.ct or <base>.shim.h` |
| L65-2 | `.m.ct` 函数式宏/非 shim C 调用 | `a strict .m.ct allows #include and object-like macros only` |
| L65-3 | strict 下 `#ct-raw` | `a strict C boundary forbids #ct-raw` |
| L65-4 | strict 下 `extern` 原型/裸 C 调用 | `a strict C boundary forbids direct C declarations` |
| L65-5 | `.h.ct` 无 shim 的公开 C 类型 | `public C type needs a .shim.h` |
| L65-6 | shim 基名歧义 | `shim base name ... is ambiguous` |

## 4 任务清单

**S0（不占任务行）**：在 `0e541f32` 冷构建、复跑 §2.2、记录基线；不产提交。

| 任务 | 交付物（路径） | 验收命令 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| R1 | 策略层：CLI/包键/默认/豁免（`Driver.h.ct` / `Pkg.h.ct`） | `p65/policy`：外部 strict、核心 allow、CLI/包键生效 | M | revert |
| R2 | `.ct/.h.ct` include 诊断（`Parser.h.ct`） | `p65/include`：strict 3 负例、allow 2 正例 | M | revert |
| R3 | raw/extern/函数式宏诊断（`Parser.h.ct`） | `p65/raw-extern`：3 负例 + `.m.ct` 对象宏正例 | M | revert |
| R4 | `.m.ct` include 例外与宏收窄（`Parser.h.ct`） | `p65/map`：include 正例、函数式宏负例 | M | revert |
| R5 | `.h.ct` shim 探测/发射/`-I`（`Module.h.ct` / `Emitter.h.ct`） | `p65/hdr-shim`：公开头带 shim、`-I` 正确、歧义负例 | M | revert |
| R6 | 外部 strict/旧包 allow 回归（`test/ast/**`、`check-ast.sh`） | `p65/regression`：688 仓内零变化、外部夹具 | M | revert |
| R7 | 文档与包规则（`language-spec` / `package-guide` / README） | `check-docs.py` rc=0；`p65/docs` | S | revert |

映射：R1→E65-1；R2→E65-2；R3→E65-3；R4→E65-4；R5→E65-5；R6→E65-6；R7→E65-7。每项至多覆盖 1 条判据（6.6 T-5）。

## 5 退出判据

| ID | 断言 | 命令与阈值 | 夹具 |
| --- | --- | --- | --- |
| E65-1 | 外部默认 strict、CT 核心豁免、CLI/包键可切换 | `ok p65/policy`，1/1 | `test/ast/p65_policy` |
| E65-2 | `.ct/.h.ct` strict 下 include 硬错；allow 下通过 | `ok p65/include`，5/5 | `test/ast/errors/p65_*` |
| E65-3 | raw/extern/函数式宏 strict 下硬错 | `ok p65/raw-extern`，3/3 | `test/ast/errors/p65_*` |
| E65-4 | `.m.ct` include 允许；函数式宏/非 shim C 调用拒绝 | `ok p65/map`，2/2 | `test/ast/p65_map` |
| E65-5 | `.h.ct` 公开头带 shim、`ct build` 加 `-I`、歧义硬错 | `ok p65/hdr-shim`，1/1 + 1 负例 | `test/modules/p65_hdr_shim` |
| E65-6 | CT 仓内 688 文件零行为变化；外部 strict/allow 夹具 | `ok p65/regression`，1/1；`check-all` 11/11 | 全量 |
| E65-7 | 文档/包规则同步 | `check-docs.py` rc=0；`ok p65/docs` | `docs/**` |
| E65-8 | **任务清单每项可独立验收（6.6 T-6）** | 逐项跑 §4，7/7 exit 0；收口对照表逐行贴输出 | §4 |

## 6 负例台账

| 编号 | 触发 | 夹具 |
| --- | --- | --- |
| L65-1…4 | strict 下 include/raw/extern/函数式宏 | `test/ast/errors/p65_*` |
| L65-5 | public C type 无 shim | `p65_public_type` |
| L65-6 | shim 基名歧义 | `p65_shim_ambiguous` |

## 7 风险与开放项

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R65-1 | parser 默认误伤 CT 核心/688 文件 | 路径/内部 flag 豁免；E65-6 |
| R65-2 | `.m.ct` 仍可 map C，封装只是名义 | D65-8 文档；包审查；不声称 sound |
| R65-3 | `.h.ct` shim 与公开头自包含冲突 | E65-5 + `-I` 部署；歧义硬错 |
| R65-4 | 外部旧包无 `c-boundary` | 缺省 allow 窗口 + 迁移清单 |
| R65-5 | 函数式宏/raw 绕过 | strict 禁；shim 出口；审计 |
| R65-6 | 包键未知被忽略 | 读取 `c-boundary`；负例 |
| R65-7 | 范围膨胀到 shim 内容审计/全 C 封装 | 列为 T65-1，另案 |

开放项：T65-1 shim 内容/链接审计；T65-2 外部包全量迁移；T65-3 公开 C 类型完整白名单；T65-4 `#ct-raw` 的 asm 例外。

## 8 估算与收口

- 编译器/工具 180–320；夹具 120–220；文档 50–90；合计 350–630。
- 开工前 S0：`0e541f32` 冷构建、记录基线、复跑探针；不占任务行。
- 收口：E65-1…8 全绿、11 道门禁绿、`version-minor=64`、五处 `CTC_VERSION` 到 `v0.64.0`、phase-log/对照表；tag 按 6.7 V-7，分支推送按 6.5。
