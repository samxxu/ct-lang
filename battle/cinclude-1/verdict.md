# battle/cinclude-1 判决

> **状态：`closed`**（2026-11-17；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **结论：不采纳“语言默认禁止 `#include`”；采纳 B′：默认保留 C 超集，新增包级/opt-in 的完整 C 边界严格策略，新包默认 strict。**

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 自举/基础库 | **B 胜** | L2 不认识 `.m.ct`，但普通 shim 头 + `-I` 可让 L2 编 ct-ast；真正断的是 `lib/std` 的 `ct build` 不部署 shim 头、不加 `-I`。A 要“不改 L1/L2”可以，但要改构建/门禁；不是零成本。 |
| J-2 C 互操作 | **B 胜** | `.m.ct`+shim 可用，但不能表达实例/状态；`.h.ct` 的 `#include` 会复制进公开 `.h`，姊妹 `.shim.h` 被忽略。A 要补 `.h.ct` header-shim 机制，否则公开 API 里的 `FILE*` 等类型无声明。 |
| J-3 可执行性 | **A=fail；B=pass（guardrail）/fail（零绕过）** | 7 类绕过实测 rc=0：`#ct-raw` 内 include、`extern int puts`、函数式 `#define`、raw 原型+外部 C、shim 内任意 C、任意 `*.shim.h` 名、缩进/mid-file/`# include`。**只禁 include 不可执行**；A 即使扩到 raw/extern，shim 内容与链接面仍可绕过。 |
| J-4 迁移成本 | **B 胜** | 688 文件/845 行；真迁只有 23/59，665/786 要 grandfather；60/62 expected.c、11 条 include 正向门禁、16 处脚本 fixture 都要改。A 不是“两 MINOR 小改”。 |
| J-5 兼容性 | **B 胜** | C 超集是既有契约；53.4% 文件含 include；传递 include 是公开头的一部分。默认禁止是 breaking change，不是修 bug。 |
| J-6 策略形态 | **B 胜** | `c-include = forbid` 在 HEAD 完全无效（未知键被忽略、build 不读）；但可新增 CLI/清单键、诊断和回退，blast radius 小于语言默认。 |

## 2 采纳：B′

1. **语言默认保留 `#include`**；C 超集不改。
2. **新增严格 C 边界策略**（opt-in，名称由实现定）：
   - 作用域：`.ct` / `.h.ct` / `.m.ct` 的直接 `#include`、`#ct-raw`、`extern` 原型/裸 C 调用；
   - 唯一允许：本包自有 `<base>.shim.h`（以及 shim 自身）；
   - 诊断：文件:行:列 + 违规类别 + 允许的 shim 路径；
   - 关闭时零影响；开启后失败关闭。
3. **包级默认**：新 `ct-pkg` 包默认 strict；已有包 grandfather/显式 opt-in。`ct.pkg` 增加 `c-boundary = strict|allow`（或等价键），`ct build`/`ct pkg check`/索引生成器读取；**未知键不能再静默忽略**。
4. **shim 扩展**：把 `<base>.shim.h` 探测从仅 `.m.ct` 扩展到 `.h.ct`/需要封装的 `.ct`；生成头部署 shim 头并自动加 `-I`，否则 `.h.ct` 的公开类型无法封装。
5. **CT 核心**：`selfhost/ct-ast`、`lib/std`、examples/test 不因语言默认被破坏；它们可在后续单独迁移/opt-in，不作为本策略的前置。
6. **明确 guardrail 边界**：strict 是包级/项目级 guardrail，不是“绝对无法调 C”；shim 内 C、链接外部 `.c` 仍是受控出口。若要求“零绕过”，需另做 shim 内容审计/链接白名单，不在本判决内。

## 3 不采纳

- **语言默认禁止 `#include`**：J-1/J-3/J-5 不过；会破坏 C 超集、688 文件、公开头与自举。
- **只禁 include**：J-3 不过；`extern`/`#ct-raw`/`#define`/shim/链接都可绕过，是假安全。
- **两 MINOR 全量迁移 + 665 文件 grandfather**：成本与收益不匹配；且 `lib/std` 的 shim 部署/`-I` 还没解决。
- **A 的“编译器/std 永久例外”**：会使规则对最有影响力的代码失效；不作为默认规则。

## 4 证据限制

- 未实现 strict 策略；以上是需求/判决，不是已交付功能。
- `ct.pkg` 当前忽略未知键、`ct build` 不读 `c-boundary`；实现时需先补读取与负例。
- `#ct-raw`/`extern` 的完整清单需在实现前按 HEAD 重新枚举；`#define` 的函数式 C 调用是否纳入 strict，需单独定。
- 外部 `ct-pkg std` 不在本仓，未验证；其迁移按包策略单独评估。

## 5 下一步

- 若 CT 组采纳：写一份 `strict C boundary` 提案/卡，先做 **诊断 + 包级开关 + shim 头部署**，不动语言默认；
- 若 ct-pkg 组采纳：新包默认 strict，索引/`ct pkg check` 读取策略；
- 不建议现在改 parser 默认或迁移 688 文件。
