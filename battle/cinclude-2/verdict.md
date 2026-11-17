# battle/cinclude-2 判决

> **状态：`closed`**（2026-11-17；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **结论：A 的 `.m.ct` 可 include 成立；但只作为“显式映射边界”，不是安全沙箱。范围按外部库/用户默认 strict，CT 仓内 1.0 前代码豁免；B 的 `.h.ct` shim 机制与 strict 覆盖面必须吸收。**

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 范围/豁免 | **A 胜，但需落点** | 688 个含 include 的文件全部在 `selfhost/**`、`lib/std/**`、`test/**`、`examples/**` 四类内；仓内迁移面 0。外部包/用户默认 strict；CT 仓内用路径/内部 flag 豁免。 |
| J-2 `.m.ct` | **A 胜（带条件）** | `.m.ct` 直连 `<stdio.h>/<stdlib.h>/<sys/socket.h>/<unistd.h>` 并 map `printf/getenv/socketpair` 实测 rc=0；它本来就是零产物映射单元，允许 include 可行且零仓内迁移。 |
| J-3 `.h.ct`/公开 C 类型 | **B 胜** | `.h.ct` 的 include 会复制进公开 `.h`，姊妹 `.shim.h` 被忽略；`ct build` 不部署/不加 `-I`。默认 strict 下公开 `FILE*`/`struct stat` 会断，必须补 `.h.ct` shim 头机制。 |
| J-4 绕过面 | **双方都只是 guardrail** | `#ct-raw`、`.ct` 内 `extern`、函数式 `#define`、shim 任意 C、`--ldflags` 外链 `.c` 全部 rc=0；`.m.ct` prologue 宏/宏 recipe 还能把 `system()` 带进消费者。strict 不能声称 sound。 |
| J-5 迁移 | **A 胜** | 仓内 0 迁移；外部包（5 包、97 `.ct`/68 含 include、10 `.m.ct`/5 系统头、6 `.h.ct`/5）才是真实迁移面；B 的仓内迁移表不成立。 |
| J-6 策略形态 | **双方一致：包/CLI 层** | `c-boundary` 当前 0 命中、`ct build` 静默忽略；需补读取、诊断、allow 清单和 kill switch。parser 无条件默认会命中 688 文件，不做。 |

## 2 采纳：A′

1. **范围**
   - CT 仓内 1.0 前代码（`selfhost/**`、`lib/std/**`、`test/**`、`examples/**`）豁免；
   - 外部库与用户代码默认 strict；外部项目可显式 `allow`。
2. **`.ct` / `.h.ct`**：默认不得直接 `#include`；C 声明经 `.m.ct` 或 `<base>.shim.h`。
3. **`.m.ct`**：允许 `#include`，作为显式映射边界；保留零产物/静态 trait 语义。
4. **strict 还要覆盖**：`#ct-raw`、`extern` 原型/裸 C 调用、函数式 `#define`。`.m.ct` 只允许 `#include` 与对象式/常量宏；函数式宏调用走 shim。
5. **`.h.ct` shim**：必须吸收 B 的机制——探测/deploy `<base>.shim.h`、自动 `-I`；否则公开 C 类型无解。
6. **默认层级**：包/构建策略，不是 parser 无条件默认。`ct.pkg` 增 `c-boundary = strict|allow`；`ct build`/`ct pkg check`/索引生成器读取；CT 核心用内部 flag 豁免；旧外部包给 allow 窗口。
7. **定位**：strict 是显式边界/guardrail，不是安全沙箱；shim 内容、链接外部 `.c` 仍可调用 C，需人工/包审查。

## 3 不采纳

- **B 的“`.m.ct` 只能 include 自有 shim 头”**：`.m.ct` 已是映射边界；强制每库再加 shim 只会增加 17 个 `.m.ct` 的迁移和基名歧义（实测 `lib` 同名 shim 冲突），并不能阻止 recipe 直接映射 C。
- **A 的“`.m.ct` 可任意 `#define`”**：函数式宏可把 `system()` 带进消费者，必须收窄为对象式宏，函数式走 shim。
- **语言 parser 默认禁止**：会命中 688 文件、破坏 C 超集；只做包/CLI 策略。
- **声称“只有 shim 可 include 就能封死 C”**：7 类绕过与 shim 内容都不支持；不能把 guardrail 写成安全承诺。

## 4 证据限制

- 无外部包全量迁移执行；外部包数量/迁移面是读 `~/.ct/pkg` 的静态统计。
- `.h.ct` shim 机制尚未实现；本判决只给需求，不宣称已交付。
- `ct.pkg` 未知键当前被忽略；`c-boundary` 需实现读取与负例。
- 真实 C 库的映射 API 是否“足够封装”需包评审；编译器只能做边界诊断，不能判断语义抽象质量。

## 5 下一步

- 先写 `strict C boundary` 提案/卡：`.m.ct` include 例外、`.h.ct` shim、raw/extern/define 诊断、`c-boundary` 读取；
- 外部包默认 strict 从新包开始，旧包 allow 清单逐步迁移；
- 不建议现在改语言默认或迁移 CT 仓内 688 文件。
