# 路线图

> 中文 · [English](#english)

本文只记录**计划**，不描述现状。当前已实现的能力请见 [README](../README.md) 与
[language-spec](language-spec.md)。所有未标注「待用户确认」的条目都只是候选方案，不代表已承诺。

---

## 中文

### 阶段总览

| 阶段 | 主题 | 类别 | 状态 | 出口条件 |
| --- | --- | --- | --- | --- |
| Phase 0 | 用 trait 写「完整 OO」（封装 / 接口 / 派发 / 传递 / 组合 / 创建与释放 / 接口多态） | 建设 | ✅ 完成（出口 1–9 成立；堆对象的**创建**按 0.1.8 推迟到 Phase 0 之后，已落地） | 出口清单 1–9 全部成立 |
| Phase 0.1 | 缺陷修复 + 回归测试 | 建设 | ✅ 完成（0.1.1–0.1.9） | 组合 / 数组 / 作用域 / 接口多态全部补齐；golden 测试全绿 |
| Phase 0.2 | 接口多态：把 trait 当类型、运行时派发 | 建设 | ✅ 完成（设计先行 → 已实现） | 接口**数组**尚未实现；接口**字段**（值字段装箱 + 派发、指针字段派发）已补齐 |
| Phase 0.3 | **剥离越位特性**：把 namespace / 多文件 / import / Drop / 诊断等在 C 侧越位实现的能力移出 `ctc.c`，使其回到**纯 OO + 底层设施**；移出件**归档为 oracle**（不销毁） | 建设 | ✅ 完成（2026-10-14） | `ctc.c` 3836 → 2897 行、只余 Phase 0 能力；套件 146 → 110 项全绿；归档件在 `test/archive/` + tag `overreach-oracle` |
| Phase 1 | **自举（第一目标）**：以剥离后的**纯 OO `ctc.c`** 为 L0，用 CT（OO 子集、单文件）重写其**全部能力**，出口是与 L0 **逐字节一致** | 建设 | ✅ 完成（2026-10-15：M2 达成 25/25，且 L1′ 自举闭环通过） | 阶梯 M1→M2（L1）；每层以 **byte-identical golden** 为出口 |
| Phase 2 | **模块化**：namespace / 多文件 `ct build` / `pub` / `import` | 恢复 | ✅ 完成（2026-10-16；非版本 tag `phase2-multifile-split`） | 归档用例 **byte-identical**；编译器源码切成多文件 |
| Phase 3 | **内存**：Drop / `delete` 放宽 | 恢复 | ✅ 完成（2026-10-16；在 `selfhost/src/**` 实现，L1 冻结） | drop 用例 **byte-identical** |
| Phase 4 | **诊断与溯源**：`#line` / 泄漏警告 / `--diagnostics` + 多错误恢复 / 语义诊断 | 恢复 + 新增 | 🚧 进行中（2026-10-16 起；切片 1：`--line` / `--no-line` 已落地） | 诊断层全绿；`#line` 能把 gcc 报错映回 `.ct` 行 |
| Phase 5 | **新增特性**：AutoDrop / 路径敏感泄漏分析 / 目录 = namespace | 新增 | 🔭 展望 | 设计冻结 + 新用例全绿；阶梯 **M6** 在此收口 |
| Phase 6 | **生态与扩展**：`map` + 反向映射表（D8）、方言系统；增量编译、跨函数分析、多目标 | 扩展 | 🔭 展望 | — |
| Phase 7 | **工具链形态**：单入口 `ct` + `ctc` 兼容别名（设计已冻结，只差落地） | 落地 | 🔭 展望 | `ct compile` 可用且 `ctc …` 调用不失效 |

> **历史说明**：Phase 0 之后曾一度把 namespace / import / Drop / 诊断 / 多文件**直接实现在 C 侧**（`ctc.c`，即旧称的 Phase 1）。按本路线，这些属**越位实现**：语法决策保持冻结，但**实现要用 CT 重做**——先由 **Phase 0.3** 把它们从 `ctc.c` 移出并归档为 oracle，再由 **Phase 2–5** 用 CT 逐项恢复（回归清单见下方「自举之后的恢复与新增」节）。
>
> **编号约定**：下文出现的 `Phase 1.0`–`Phase 1.9`、`Phase 1.6/1.7/1.9c` 等，是**越位实现期的历史子阶段编号**，与新的 **Phase 1（自举）**无关。`Phase 0.1` / `0.2` / `0.3` 是 Phase 0 的**历史子阶段**，编号保留不动。
>
> **重编号记录（2026-10-16 用户确认）**：原「Phase 2（含 4 个子阶段）+ Phase 3」把**特性族**伪装成了子阶段（2.1–2.3 的 DoD 其实同属「恢复」类），而且与版本号无法一一对应。现把子阶段**升为一级阶段**，并把「类别」（恢复 / 新增）降为总览表的一列，另立 Phase 7：

| 旧编号 | 新编号 | 主题 |
| --- | --- | --- |
| Phase 2.1 | **Phase 2** | 模块化（namespace / 多文件 / `pub` / `import`） |
| Phase 2.2 | **Phase 3** | 内存（Drop / `delete` 放宽） |
| Phase 2.3 | **Phase 4** | 诊断与溯源（`#line` / 泄漏警告 / `--diagnostics`） |
| Phase 2.4 | **Phase 5** | 新增特性（AutoDrop / 路径敏感分析 / 目录 = namespace） |
| Phase 3 | **Phase 6** | 生态与扩展（`map` / 方言系统 / 增量编译…） |
| （无） | **Phase 7** | 工具链形态（单入口 `ct` + `ctc` 兼容别名） |

> 读到旧文档（或本仓库 `reports/` 里的旧报告）中的「Phase 2」「Phase 3」时，按上表换算。以上编号与版本号**一一对应**：Phase *n* ↔ `v0.n.x`（见「版本记录」）。

### 版本记录

| 版本 | 对应阶段 | 内容 |
| --- | --- | --- |
| v0.0.1 | Phase 0 | trait / struct / impl / use 的结构转换、方法调用重写、配套 `.h`、五层回归测试 |
| v0.1.0 | Phase 1 自举（**里程碑已达成，尚未 bump**） | L1（`selfhost/ctc.ct`）对 `test/cases/**` 全量 25/25 逐字节一致，且 L1 编译自身（L1′）重跑同一批语料仍逐字节一致 |
| v0.2.0 | Phase 2 模块化（**里程碑已达成，尚未 bump**） | namespace / 多文件 `ct build` / `pub` / `import` / `.h.ct` / `-I`；归档用例逐字节一致，编译器源码拆成 `selfhost/src/**`（L1 建出 L2，对 `test/cases/**` 25/25 一致） |
| v0.3.0 | Phase 3 内存（**里程碑已达成，尚未 bump**） | Drop / `delete` 放宽，已在 `selfhost/src/**` 恢复（L1 冻结）；`22_drop` 逐字节一致 |
| v0.4.0 | Phase 4 诊断与溯源 | 展望：`#line` / 泄漏警告 / `--diagnostics` |
| v0.5.0 | Phase 5 新增特性 | 展望：AutoDrop / 路径敏感分析 / 目录 = namespace |
| v0.6.0 | Phase 6 生态与扩展 | 展望：`map` / 方言系统 / 增量编译 |
| v0.7.0 | Phase 7 工具链形态 | 展望：单入口 `ct` + `ctc` 兼容别名 |

版本号定义在 `ctc.c` 的 `CTC_VERSION`，并写入生成物注释；改动它必须重新生成全部 golden（见 [AGENTS.md](../AGENTS.md) 第 5 节）。

**版本规则（2026-10-15 用户确认）**：

- 版本号形如 **`v0.<phase>.<patch>`**，**只在阶段边界 bump**；`patch` 位留给阶段内需要重生成 golden 的修复。与阶段**一一对应**：`0.<n>.x` = Phase *n* — `0.0.x` = Phase 0（已完成，当前 v0.0.1）、`0.1.x` = Phase 1 自举（已完成，尚未 bump）、`0.2.x` = Phase 2 模块化、`0.3.x` = Phase 3 内存、`0.4.x` = Phase 4 诊断与溯源、`0.5.x` = Phase 5 新增特性、`0.6.x` = Phase 6 生态与扩展、`0.7.x` = Phase 7 工具链形态；`1.0.0` = 语言定稿。
- **tag 名必须与 `CTC_VERSION` 一致**：因此「不 bump 就不打 `v` 号 tag」，未 bump 的里程碑用非版本 tag（`phase1-m2` 标记 v0.1.0、`phase2-multifile-split` 标记 v0.2.0）。
- **口径 A（2026-10-16 用户确认）**：Phase 1 / Phase 2 的版本号**都不在阶段边界 bump**，与「单入口 `ct`」一并落地；`v0.1.0` / `v0.2.0` 的 bump 会在那一刻一次性完成（含两处 `CTC_VERSION` 同步与全量 golden 重生成）。
- **bump 为什么必须谨慎**：`CTC_VERSION` 会进产物 banner，一次 bump 就要重新生成 `test/cases/**` 全部 golden 与 examples 的 `.expected.out`，并**同时**改 `ctc.c` 与 `selfhost/ctc.ct`（L1 自带一份版本号，第 84 行）——两处不一致会让 `selfhost/check-goldens.sh` 立刻全红。冻结期改 `CTC_VERSION` 属「不允许」项，需用户显式授权一次例外。

### 已定的设计决策

#### 工具链形态：单入口 `ct`（已定，尚未落地）

- **最终形态**：一个 `ct` 命令承载全部功能，靠子命令区分 —— `ct compile`（即现有的编译能力）、`ct build`、`ct get` / `ct install`（包管理，待做）。
- **`ctc` 保留为兼容别名**：现有文档、脚本与习惯里的 `ctc …` 调用不失效。
- **实现方式（待落地时确认）**：按 `argv[0]` 分派（同一二进制，同 busybox 的做法），`ctc` 作为 `ct` 的软链或副本。
- **当前状态**：**尚未落地** —— 今天的二进制仍叫 `ctc`，`ct` 命令与子命令都不存在。因此 README 等处的命令仍写作 `ctc`，等实现落地那一步统一替换，避免文档指向跑不通的命令。

落地清单（越位实现期起执行）：

1. `ctc.c`：`main` 增加子命令解析（`compile` 为默认），并支持按 `argv[0]` 以 `ctc` 身份直调。
2. 构建方式改为 `gcc ctc.c -o ct`，并生成 `ctc` 别名（软链）。
3. 生成物注释 `Generated by ctc …` 改为 `Generated by ct …` → **必须重新生成 `test/cases/**` 的全部 golden**（见 AGENTS 第 5 节第 6 条）。
4. 同步 `README.md`、`AGENTS.md`、`docs/*` 中所有 `ctc` 命令。
5. `test/run.sh` 的构建与调用路径同步。

#### 包管理的前置条件（比命名更重要）

- 真正的**前置是「多文件编译」**（Phase 1 已列）：类型定义下沉到 `.h`，生成的 `.c` 改为 `#include` 自己的头。这会打破 Phase 0 的「`.c` 自包含」约定，属破坏性变更。
- 包的**接口边界天然是 trait**：一个包 = 一组 `.ct` + 对外暴露的 `.h`（trait 声明）。这条决定了包管理器与 registry 能长成什么样。

#### 包管理器的命名（待定）

- 候选：`ct-pkg`（直白）、`ctpm`（类比 npm），或像 `cargo` / `dub` / `mix` 那样的独立品牌词（辨识度高，但新人不易联想到它是 ct 的包管理器）。
- **registry 与组织名要趁早占位**：`github.com/ct-lang`（2022 年注册）与 `github.com/ctlang`（2019 年注册）两个用户名均已被闲置账号占用（各 1 个仓库、0 关注），要做组织需另选名字。

#### 许可（已定并已落地）

- **编译器本体** GPL-3.0-or-later（`LICENSE`）；**`.ct` 源码与生成物不受 GPL 约束**（`LICENSE.EXCEPTION`，照 GNU Bison 先例，且随产物走）；**`examples/` 与 `test/` 为 MIT**。
- 例外不是可选项：ctc 会往产物里插入样板（vtable 结构体、vptr 字段、`_self` 强转行），"编译器输出是否构成衍生作品"存在歧义——不写例外，使用者（尤其公司法务）无法判断，等于挡住采用。

#### namespace 与路径访问规则（已定，越位实现落地）

CT 采用混合路径访问方式：**前面用 `::` 走命名空间路径，最后一步用 `.` 调用方法或访问字段**。最后一步一定是 `.`。

```c
// 正确
HAL::UART::huart1.send(data, len);
HAL::GPIO::pinA5.set(1);

// 静态函数用 ::
HAL::UART::get_default_config();

// 错误
HAL::UART::huart1::send(...);   // 最后一步不能用 ::
HAL.UART.huart1.send(...);      // 中间不能用 .
```

| 场景 | 符号 | 示例 |
| --- | --- | --- |
| 命名空间路径导航 | `::` | `HAL::UART` |
| 方法调用 / 字段访问 | `.` | `huart1.send(...)` |
| 静态函数调用 | `::` | `HAL::UART::init()` |
| trait 方法引用 | `.` | `obj.method()` |

此规则落地时写入 [language-spec](language-spec.md)，编译器强制检查。

#### import 与模块系统（已定，越位实现落地）

`import` 不是 `#include` 的语法糖，而是**编译单元声明**。编译器通过 `import` 建立模块依赖图，自动处理符号引用、编译顺序和链接：

```c
import HAL::UART;      // 告诉编译器：HAL::UART 的符号在 hal/uart/ 下
import Driver::Sensor; // 告诉编译器：Driver::Sensor 的符号在 driver/sensor/ 下
```

编译器内部行为：

1. 扫描所有 `.ct` 文件，建立 module 表（namespace → 源文件路径）
2. 解析 `import` 关系，构建依赖 DAG
3. 拓扑排序，按依赖顺序编译
4. 每个 `.ct` → `.c` + `.h`
5. 链接所有 `.o`

Phase 0 不做 import（单文件），Phase 1 实现。

#### 文件命名约定与 `pub` 可见性（已定，越位实现落地）

文件名决定编译器的生成行为，无需额外关键字或配置文件：

| 文件名 | 生成行为 |
| --- | --- |
| `foo.ct` | 只生成 `foo.c`（实现文件，不对外暴露接口），文件内符号默认只在当前编译单元可见 |
| `foo.h.ct` | 生成 `foo.h` + `foo.c`（接口 + 实现分离） |

> **落地说明（2026-10-16）**：**附加式落地**——`foo.h.ct` 这一半已实现：基名去掉 `.h.ct` 后产出 `foo.c` + `foo.h`，
> `import foo;` 也会回退命中 `foo.h.ct`（并因此产出 `foo.h`）。`foo.ct` 「只产出 `foo.c`、不对外暴露」的那一半
> **未落地**：冻结归档对 `foo.ct` 的 `.h` 也做逐字节比对（`check-archive.sh` 组 6），砍掉 `.h` 会立刻判 REGRESSION，
> 故推迟到 **Phase 5**。用户 2026-10-16 拍板：本轮只做附加式，不改 `*.ct` 既有产物。

编译器从 `pub` 关键字识别需要暴露的符号，自动生成 `.h`（含 `#ifndef` 守卫、struct 定义、函数声明、vtable 类型）和 `.c`（含实现）：

```c
// uart.h.ct
namespace HAL::UART {
    pub trait Controller {
        void send(uint8_t *data, int len);
        int recv(uint8_t *buf, int len);
    }

    pub struct UartDevice {
        int baud;
        int fd;
    }

    pub UartDevice init(int baud);
    pub void deinit(UartDevice *d);
}
```

可见性修饰符：

| 修饰符 | 作用 |
| --- | --- |
| `pub` | 对外暴露（进 `.h`） |
| `static` | 文件级私有（不进 `.h`，不进符号表） |
| `pub readonly` | 外部可读不可写（生成 `const` 或 getter） |

可见性规则作用于 namespace 内的声明、struct 字段、trait 方法，由编译器强制约束，违反直接报错。封装由编译器强制执行，不存在「忘了在 `.h` 里声明但 `.c` 里实现了」的不一致问题。

#### 内存管理：Drop 与 delete（已定，越位实现落地）

编译器内置 `Drop` trait。struct 声明 `use Drop` 后，编译器自动生成释放逻辑：

```c
struct MyDevice {
    uint8_t *buf;
    Filter *filter;
} use Drop;
```

自动生成规则：

- 对每个字段，如果其类型也 `use Drop` → 递归调用 `drop()`
- 基本类型（int / char / float / 裸指针）→ 不处理
- 如果 struct 本身是堆分配的 → `free(self)`
- 用户可以用 `impl Drop for MyDevice { void drop() { ... } }` 自定义释放逻辑
- **未调用不生成代码**：整个项目从未调用过某类型的 `drop()`，则不生成任何 drop 相关函数体，零开销

`delete` 是释放对象的统一入口。Phase 1 是在**已落地的最小版**（0.1.8：`delete p;` → `if (p) free(p);`，
只对已登记的 ct-struct 指针生效）之上**扩展**出 `drop()` 调用，**不是重复规划**：

```c
MyDevice *d = MyDevice::create();
// ... 使用 ...
delete d;    // 展开为：if (d) { d->drop(); free(d); }
```

| 场景 | 展开行为 |
| --- | --- |
| 堆对象（指针）+ `use Drop` | `T_drop(ptr); free(ptr);` |
| 堆对象 + 无 Drop | `free(ptr);` |
| 栈对象 | 编译错误（或只调 `drop()`，不 `free`） |
| 空指针 | `if (ptr)` 保护，安全无操作 |
| 基本类型指针 | 等价于 `free(ptr)` |

数组释放用 `delete[]`：对每个元素调 `drop()`，然后 `free`。

**编译期泄漏警告（Phase 1 简单版）**：函数末尾检查局部变量的分配/释放状态——分配了但没 `delete`、没 `return`、没存全局 → 警告。路径敏感版（分析所有 return 路径）归 Phase 5（展望）。警告同时输出人可读列表与 JSON（供 VS Code 插件消费）：

```json
{
  "warnings": [{
    "type": "potential_leak",
    "file": "src/main.ct",
    "line": 23,
    "variable": "sensor",
    "type_name": "BME280*",
    "message": "allocated but never deleted"
  }]
}
```

抑制方式：`#[allow(leak)]` 标注有意不释放的分配（如全局存活对象）。

#### map 语法与反向映射表（已定，Phase 6 落地）

`map` 关键字将 trait 方法映射到具体实例的 SDK 调用：

```c
map trait Controller for instance huart1 {
    send(data, len) → HAL_UART_Transmit(&huart1, data, len, HAL_MAX_DELAY);
    recv(buf, len) → HAL_UART_Receive(&huart1, buf, len, HAL_MAX_DELAY);
}
```

编译器生成对应的 vtable 条目，使 `huart1` 可以作为 `Controller` trait 的实例使用。

编译器同时维护**反向映射表**（生成代码中的 C 符号 ← CT 中的哪个 trait/方法），用于：错误信息中给出有意义的回溯、VS Code 插件「跳转到定义」、反编译时恢复 CT 语义。

> **排期（D8，用户 2026-10-14 拍板）**：自越位实现中移出，排在 Phase 6 最后实现。理由：
> `map` 属生态绑定方向而非自举主线的主题，出口标准与自举前置清单均不依赖它；其真实消费者
> （官方 bindings）尚不存在，过早冻结实例语义会凭想象用例定死设计。落地时与官方 bindings 清单一并定案。

#### JSON 诊断输出与插件薄客户端（已定，越位实现落地）

`ctc` 输出 JSON 格式：编译错误/警告（含泄漏警告）、符号表（namespace / trait / struct / 函数位置）、调用关系图。VS Code 插件作为薄客户端消费 JSON，实现内联错误提示、跳转到定义、自动补全、悬停类型信息；插件本身不做编译、不做分析，编译器升级时插件无需改动。

> **首版（Phase 1.7，用户 2026-10-13 拍板 Q1=A）**：`--diagnostics=json` **只输出诊断列表**（`{"warnings":[…]}`），
> 符号表与调用图**尚未实现**，另开子项。`--diagnostics=text`（默认）为人可读 stderr。

#### 自举策略与单文件边界（已定；`ctc.c` 自举启动即冻结，目录随布局定型落地）

- **渐进自举**：L0（C 写的最简 trait 编译器，即今天的 `ctc.c`）→ L1（CT trait-only 子集写的基础编译器）→ L2（全特性 CT 写的完整编译器）。
- **Phase 0 边界**：`ctc.c` 留在仓库根目录、保持单文件（2026-10-11 用户确认）；不建 `src/`、不拆分。自举启动后才谈搬迁。
- **最小可自举版（2026-10-14 用户确认）**：优先用**单文件**（不用 namespace / `import` / 多文件）达成自举，
  以绕开前置条件 #1「跨单元引用带 trait 的对象」（vtable 变量为 `static`、`.h` 只放类型，跨翻译单元
  既写不了 vptr 也无法派发）。单文件路径的唯一硬阻塞是「`impl` 方法体内无法跨对象派发」，已由
  **Phase 1.9c** 解决（方法体走与顶层完全相同的重写管线：登记 `self` / 方法参数后逐行 `transform_line`）。
  结论：**单文件 + 完全 OO 已可自举**——namespace、多文件、诊断等非 OO 特性**不作为自举前提**，一律改用 CT 实现；C 侧的越位实现**先剥除归档（Phase 0.3）**，再由 Phase 2–5 用 CT 重做。
- **冻结与搬迁**：**Phase 0.3 剥离完成后（即自举启动时）** `ctc.c` 即冻结为 **L0 + 差分 oracle**（只修 bug，不加特性）；移入 `ctrait/` 随自举结构稳定时一并做——**2026-10-15 用户确认：CT 侧布局定型前不搬**，`ctc.c` 继续留在仓库根目录。理由：这次搬迁并非单文件 `git mv`——草案里 `ctrait/` = 「`ctc.c` + 它自己的 `test/`」，隐含「把今天的 `test/` 拆成 L0 单测 vs 集成测试」这一设计任务；而 L1/L2 的 `src/` 分文件又依赖 L2 恢复多文件。故搬迁与 `src/` + `test/` 布局定型合并为**一次**独立 `chore` 提交，不做半次搬迁（见 [design/bootstrap.md](design/bootstrap.md)）。新特性一律在 CT 侧实现。
- **清理口径（2026-10-14 修订为「剥离在前」）**：**先**把越位落在 C 里的 namespace / 多文件 / import / Drop / `#line` / 诊断从 `ctc.c` **移出并归档为 oracle**（Phase 0.3），使 L0 成为**纯 OO 核心**（+底层设施）；**再**自举（Phase 1）；**最后**由 Phase 2 用 CT 逐项重做并向归档对差。两条硬前提：① **移出件不销毁**——归档件既是种子（唯一能生产 L1 的那个行为基准）也是差分 oracle（唯一能产出 byte-identical golden 的对照实现）；② **`ctc.c` 永不整体删除**，作为种子与差分 oracle 长期保留（先例：Rust 长期保留 stage0，Go 1.5 起弃用 stage0，两者皆可）。
- **阶梯约束（源语言滞后一级）**：第 n 级编译器只能编译「第 n−1 级所支持的语法子集」写成的源码。因此 L1 源码只能用**单文件 + OO 子集**；CT 侧要**使用** namespace / Drop / import 组织编译器源码，必须先有支持它们的 CT 级编译器。**"重写完就删 C"顺序错**，必须逐级爬升。
- **单仓库**：跨层编译与特性耦合决定了不拆仓库；`ctrait/` 需要独立分发时用 `git subtree` / `git filter-repo` 无损拆分。

目标目录结构、分层规则、构建流程与里程碑（M1–M6）见 [design/bootstrap.md](design/bootstrap.md)（设计草案，未实现）。

#### 自举前置条件（清单）

L1 / L2 要用 CT 写编译器，下列能力必须先成立（**2026-10-11 逐条实测**；除注明外均为当前缺口）：

| # | 前置条件 | 为什么自举需要 | 落地 | 状态 |
| --- | --- | --- | --- | --- |
| 1 | **多文件编译 + namespace**（`.h.ct` / `import` / `pub`） | 否则全部代码挤在单文件，没有模块边界 | 越位实现 → 自举期回归 CT | ⚠️ namespace + 多文件（`ct build`）+ `pub` + `import` + `.h.ct` 命名 + `-I` 搜索根已实现；跨单元引用带 trait 的对象尚不可。单文件自举路径**不需要**此项（见上方「最小可自举版」） |
| 2 | **堆对象的语言级创建** | AST / 符号表需动态分配；当前只能手写 `q->__<trait>_vptr = &…;`（可用，但漏写即运行期崩） | C 侧（自举前置；与 Drop 一起定） | ✅ `T *p = malloc(...)`（含 `calloc`）已在声明后自动写 vptr（含嵌套值字段，D1=A）；`use Drop` + `delete` 递归释放已实现 |
| 3 | **文件作用域的对象数组** | 全局符号表；实测 `Person ps[2];` 在文件作用域直接 `die` | C 侧（自举前置；"对象住哪儿"设计） | ✅ Phase 1.6：文件作用域对象 / 数组的 vptr 由生成的构造器 `__ct_init`（`__attribute__((constructor))`，D5=A）在 `main` 前写入；`static` 前缀的同款声明也已识别（`static Person g;` / `static Person gs[2];`，Phase 1） |
| 4 | **`delete` 覆盖 `char *`** | 字符串 / 缓冲区；实测 `delete buf;`（`char *buf`）原样透传 → 编译错，只能改用 `free()` | 越位实现 → 自举期回归 CT | ✅ `delete p;` 已对任意指针生效（`char *` → `if (p) free(p);`） |
| 5 | **`#line` 指令** | 生成的 C 报错行号要映回 `.ct`，否则自举产物无法调试 | 越位实现 → 自举期回归 CT | ✅ 多文件模式**默认**在 `.c` 发出 `#line`（D4=A），单文件默认关；gcc/clang 报错映回 `.ct` 行 |
| 6 | **方法调用的接收者可以是更一般的表达式** | 变量 / 表达式下标、指针数组元素、指针字段链（`ps[i].m()`、`ptrs[i]->m()`、`b.who->m()`）由 Phase 1.9a 支持；rvalue 接收者 `f().m()` / `mk()->m()`（含字段跳 `f().a.b.m()`）由 Phase 1.9b 支持 | C 侧（自举前置，1.9） | ✅ 1.9a + 1.9b 均落地（Q1=A 值/指针返回、Q2=A 仅语句行首或初始化式 RHS 提升、Q3=A 其它位置 `die`） |
| 7 | 位置式初始化 / 方法体内互调 | — | 已完成（0.1.1 / 0.1.4 / 1.9c） | ✅ 方法体自 **Phase 1.9c** 起走与顶层相同的重写管线：方法体内的局部变量接收者、字段链递归与参数接收者均正常派发 |

**AST 的形状**：ct **无继承**，AST 只能用 `trait Node { … }` + 各 `struct impl`，靠**接口值**（Phase 0.2）
承载——这让自举同时成为 Phase 0.2 的压力测试。注意**声明顺序**：`struct Binary { Node *lhs; }` 要求
`trait Node` 先声明；两个 struct **以值互相引用**会失败（经接口指针引用则不受影响）。

第 6 项是一类问题（"接收者既不是已登记的标识符、也不是常量下标 / 值字段链"），可单独推进；其余 1–5 项
与**越位实现期**高度重叠——**自举的前置条件基本等于越位实现期的产出**。

> **2026-10-14 修订（配合 Phase 0.3）**：按「纯 OO 单文件」口径，前置 **#1（多文件 + namespace）与 #5（`#line`）退役**（随 Phase 0.3 一并移出，单文件路径本就不需要）；**#2（堆创建）、#3（文件作用域对象/数组）、#4（`delete` 覆盖 `char *`）、#6（一般接收者）、#7（方法体同一管线）保留**并归入 Phase 0 核心（2026-10-14 逐条确认「留」）。退役后自举**不再有硬阻塞**（原 #1 附带的「跨单元带 trait 对象」随之消失）。

### Phase 0：用 trait 写「完整 OO」

**出口标准（2026-10-11 用户确认，重新定义）**：Phase 0 是否完成，不按"结构转换跑通"判断，而按
**能否借助 trait 写出一段完整的面向对象程序**判断。ct 的 OO 语义是 **trait 接口 + 组合，不含继承**。

「完整 OO」在 ct 里 = 下列能力全部成立：

| # | 能力 | 状态 |
| --- | --- | --- |
| 1 | **封装**：`struct` 字段 + `impl` 方法；方法体内访问 `self->field` | ✅ |
| 2 | **接口**：`trait` 声明 + 每个 `struct` 各自 `impl … for` | ✅ |
| 3 | **派发**：值/指针接收者的 `.m()` / `->m()`，以及方法体内兄弟调用 `self->m()` | ✅（0.1.4 收尾） |
| 4 | **传递**：对象作为函数/方法的**参数与返回值**（签名里的 struct 类型） | ✅ 见 0.1.5 |
| 5 | **组合**：struct 字段为另一 struct 类型；字段链式调用 `a.b.m()` | ✅ 见 0.1.6 |
| 6 | **存储**：数组元素上的方法调用与元素 vptr 初始化 | ✅ 见 0.1.7 |
| 7 | **创建与释放**：**创建 = 栈上的 struct 声明**（指定 / 位置式 / 无初始化式 / 嵌套 / 数组，均写 vptr）✅；**释放 = `delete q;`** → `if (q) free(q);` ✅；**堆对象无语言级创建入口**，推迟到 Phase 1（与 Drop 一起定；当前需手写 vptr） | ✅ 见 0.1.8 |
| 8 | **作用域**（正确性前提）：变量/参数按块作用域回滚，不跨函数串味 | ✅ 见 0.1.9 |
| 9 | **接口多态**：能声明 trait 类型的变量/参数，运行时派发到不同 `struct` | ✅ 见 Phase 0.2 |

第 4–8 项属**实现覆盖缺口**（沿用 [AGENTS.md](../AGENTS.md) §4「不允许静默产出编不过的 C」的口径，按缺陷修）；
第 9 项属**语言特性**（需要新的类型表示与语法），**必须先设计后实现**，不能当缺陷补。

既有验收（仍适用：零警告构建 + golden + 回归套件）：

```bash
gcc -Wall -Wextra -std=c99 ctc.c -o ctc                            # 零警告
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c             # 无报错，同时生成 /tmp/greeter.h
gcc -Wall -Wextra /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
# Hello, I'm Tom, age 36
# Hello Jerry, I'm Tom
```

（Phase 0 期间这批命令用的是仓库根目录的 `example.ct`；后续示例收进 `examples/`，生成物不再入库。）

明确的非目标（仍不在 Phase 0 内）：类型检查、优化、错误恢复、namespace、泛型、多文件、嵌套定义、继承。

### Phase 0.1：缺陷修复与回归测试（建议优先）

#### 0.1.1 修复指针声明缺陷 ✅ 已完成

- **问题**：`Person *p = &a;` 曾生成成 `struct *p = &a;`（丢失类型名），产出非法 C。
- **修复**：`try_var_decl()` 的 `*p == '*'` 分支补回类型名，现生成 `struct Person *p = &a;`。
  指针变量当时**不登记**进变量表（此为临时状态）；`p->m()` 的重写已在 0.1.4 补齐。
- **验收**：`Person *p = &a;` 生成 `struct Person *p = &a;` 且编译通过；该用例纳入 0.1.3 的回归集。

#### 0.1.2 支持位置式初始化 ✅ 已完成

- **问题**：`Person p = { "Tom", 36 };` 不追加 vptr，运行时调用方法解引用空指针。
- **修复**：去掉「必须全为指定初始化」的限制（移除 `is_designated_list()`），只要 struct 有
  `use`，无论指定初始化、位置式还是空列表，都在 `}` 前追加 `.__x_vptr = &…_vtable`。
  已验证 C99/C11 允许 `{ 1, .v = 0 }` 这种混用（gcc 无警告）。
- **验收**：`test/cases/07_positional_init.ct` 位置式初始化可正确运行。

#### 0.1.3 建立回归测试 ✅ 已完成

- **结构**（已落地）：

  ```
  test/
  ├── run.sh                 驱动器：构建 → 单测 → golden → 负例；退出码 0 = 通过
  ├── unit/test_helpers.c    白盒单测：include ctc.c 直接调 static 纯函数，40 项断言
  ├── cases/                 golden 正例：<name>.ct + <name>.expected.c / .h / .out
  └── errors/                负例：<name>.ct + <name>.expected-err（期望的诊断子串）
  ```

- **断言**：① 构建层——`ctc` 自身零警告；② 单测层——`trim` / `param_type_only` /
  `parse_params` / `split_decl` / `decl_end_is_bare` / `put_vptr_designators` / `word_at` /
  `match_delim` 等纯函数行为；
  ③ golden 层——`ctc` 退出 0、生成物与 `.expected.c`/`.expected.h` 逐字节一致、生成物能编译、
  含 `main` 的用例 stdout 与 `.expected.out` 一致；④ 负例层——必须非 0 退出，且诊断带
  `文件:行:列: error:` 前缀并包含期望文案。
- **覆盖清单（已实现）**：单 trait、多 trait + `use` 换行 + 嵌套调用、无 trait struct 与透传
  （`#define` / 字符串 / 中英文字面量与转义 / 行注释 / 块注释内不重写）、签名形态
  （`void f(void)`、多词类型、空 struct、嵌套花括号）、变量声明（指定初始化、`struct` 限定形式、
  指针声明）、跨 trait 方法名冲突（取 `use` 顺序第一个）、位置式初始化、方法体内互调、
  指针接收者、无初始化式声明；负例覆盖未定义 trait / 未定义 struct /
  未声明方法 / 未实现方法 / struct 未 use 该 trait / 括号不配对。
- **未纳入**：`MAX_*` 容量上限的越界行为（依赖容量策略决策）。
- **验收**：`./test/run.sh` 全绿（当前 20 项：1 构建 + 1 单测 + 10 正例 + 2 示例 + 6 负例）。
  额外增加 examples 层，直接校验 `examples/**` 的端到端可运行性（生成 → 构建 → 运行 → 比对
  `.expected.out`），因此示例不会随编译器演进悄悄失效。
  已验证其有效性：在临时副本中注入「改坏 golden / 改错期望诊断 / 断言失败」三处错误，
  三层都能报告失败并以退出码 1 结束。

#### 0.1.4 补齐 vptr 覆盖：指针接收者 / 方法体内互调 / 无初始化声明 ✅ 已完成

- **问题**（同一类：静默产出编不过或空 vptr 的 C，违反 [AGENTS.md](../AGENTS.md) §4）：
  1. `impl` 方法体内的 `self->other()` 只被改写成 `_self->other()`，产出非法 C；
  2. 指针变量不登记，`p->m()` 不被重写，产出非法 C；
  3. 无初始化式声明 `Person p;` 不写 vptr，调用方法解引用未初始化指针。
- **修复**：
  1. `Var` 增加 `ptr` 标记；`try_var_decl()` 登记指针变量；`transform_calls()` 增加 `->` 分支
     （传指针本身，**不补 `&`**），且不对指针变量误用 `.` 规则；
  2. 方法体内的 `self->m(...)` 在 `replace_self()` 内一并重写为
     `_self->__<trait>_vptr->m(_self, …)`；检测到此类调用时，在方法函数前补一行 vtable
     前向声明（C tentative definition）；
  3. 无初始化式声明改写为 `struct Person p = { .__<trait>_vptr = &…_vtable };`。
- **用例**：`test/cases/08_self_call.ct` / `09_pointer_receiver.ct` / `10_uninit_decl.ct`
  （均含 `main`，走运行型断言）。
- **验收**：四条最小复现都能编译并正确运行；`./test/run.sh` 全绿。

#### 0.1.5 函数/方法签名里的 struct 类型 ✅ 已完成

- **问题**：普通函数的返回类型与参数类型里的裸 struct 名不做 `struct ` 限定，静默产出编不过的 C；
  参数不登记，参数上的 `.m()` / `->m()` 不重写。实测失败形态：`static Point make(...)`、
  `Point *pick(...)`（返回类型对、参数错）、`void f(Person p)`、`void f(Person *q)`、
  `void move(Point *pt, int dx)`、函数原型 `void f(Person *q);`。
  `Point make(...)`（裸返回类型且行首）之所以"能过"，是被 `try_var_decl()` 误当行首变量声明补了
  `struct `——属**巧合而非设计**。
- **修复**：新增 `parse_func_sig()`，在 `emit_raw_line()` 中**先于** `try_var_decl()` 判定该行是否为
  函数定义/原型（识别 `static` 等前缀词、多词返回类型、指针返回、原型；`if/while/else if` 等语句
  不会误判）。对返回类型与参数类型中已知 struct 名原位插入 `struct `（保序保格式，不动其它字符），
  并在**有函数体时**把参数登记进变量表（值 `ptr=0` / 指针 `ptr=1`）。命中函数形态的行不再走
  `try_var_decl()`，因此顺带消除了"函数名被误登记为变量"的副作用。
- **限制**：参数列表本身跨多行的签名不识别（按行处理，与"跨行调用不重写"同类）。
- **用例**：`test/cases/11_value_param.ct` / `12_pointer_param.ct` / `13_signature_types.ct`
  （含 `static` 返回、指针返回、原型、多词类型）。

#### 0.1.6 组合：struct 字段为另一 struct 类型 ✅ 已完成

- **机制说明（0.1.6–0.1.8 共享）**：[construction.md](construction.md)——构造语义（vptr 由谁、在何时写入），
  决策 D1–D5 见其第 6 节。

- **问题**：struct 体按设计原样透传，字段类型不做限定（`struct Shop { Person owner; }` → 编译失败）；
  字段链式调用 `s.owner.greet()` 不重写。
- **修复**（分三段落地）：**a** 新增 `parse_fields()` 部分解析 struct 体，给已知 struct 类型的字段补
  `struct `，并把「值是 ct struct」的字段记进 `Struct` 字段表；**b** 声明对象时递归写入嵌套字段的
  vptr（**用声明后的赋值语句**，避免追加的 `.owner` 指定初始化覆盖用户自己写的 `.owner = {…}`）；
  **c** `transform_calls()` 改为沿字段链推导静态类型，支持 `s.owner.m(...)` → `s.owner.__<trait>_vptr->m(&s.owner, …)`。
- **限制**：含嵌套对象的对象**必须在函数内声明**（文件作用域无法安放赋值语句，越界 `die`）。—— **Phase 1.6 已解除**：文件作用域的这类对象由构造器 `__ct_init` 在 `main` 前写 vptr。
- **用例**：`test/cases/15_composition.ct`。

#### 0.1.7 存储：数组元素 ✅ 已完成

- **问题**：`Person ps[2];` 声明被限定但元素 vptr 未初始化；`ps[0].greet()` 不重写（编译失败）。
- **修复**：`Person ps[<n>];` 展开为声明 + 一个块内循环（`__ct_i`），逐元素写入 vptr（含嵌套字段）；
  调用侧支持 `ps[<常量>].m()` → `ps[0].__<trait>_vptr->m(&ps[0], …)`。
- **限制**（D2）：只支持**无初始化式**声明 + 常量下标；其它形态在需要初始化时 `die`。
- **用例**：`test/cases/16_arrays.ct`。

#### 0.1.8 释放：`delete` ✅ 已完成（堆对象的**创建**推迟到 Phase 1）

- **问题**：`Person *q = malloc(...); q->greet();` 调用被重写但 vptr 从未设置 → 运行期段错误。
- **本次落地**：`delete q;` → `if (q) free(q);`（`q` 必须是已登记的指针变量；靠词边界 + 形态判定，
  因此普通 C 里叫 `delete` 的标识符不会被误判）。Drop 版（`d->drop(); free(d);`）仍留 Phase 1。
- **未落地：堆对象的自动创建**。曾试引入 `new`（D3），复核后认为它不在计划内、且**并未真正堵住**
  `malloc` 那条洞（`malloc` 出来的对象依旧静默无 vptr、调用即崩），故**已移除**。堆对象的创建方式
  推迟到 Phase 1，与 Drop/delete 一起定——那时 `drop()` 也需要 vptr，必然要有结论。
- **现状**：堆对象需**手写** `q->__<trait>_vptr = &…;`（该行原样透传），之后 `delete q;` 可正常释放。
- **用例**：`test/cases/17_heap.ct`（手写 vptr + `delete`）。

#### 0.1.9 变量作用域 ✅ 已完成

- **问题**：`find_var()` 首命中、`g_vars` 只增不减；多函数同名变量/参数互相串味，产出非法 C。
- **修复**：`scope_track()` 在主扫描里跟踪花括号（跳过字符串/注释），每个 `{` 压栈当时的 `g_nvars`，
  遇到 `}` 弹栈回滚；函数体左花括号（含"花括号另起一行"的写法）单独用**参数登记前**的值压栈，
  保证参数随函数一起出作用域。这同时修掉了既有局部变量的跨函数串味。
- **备注**：本节原被排在 Phase 1，因 0.1.5 要登记参数而提前。
- **用例**：`test/cases/14_scope_shadow.ct`（两个函数各自声明同名 `d`、两个函数各自用同名参数 `x`，
  分属不同 struct；改动前编译失败）。

### Phase 0.2：接口多态（设计先行 → 已实现）

**机制说明**：[polymorphism.md](polymorphism.md)——「接口值 = 胖指针 `{ self, vt }`」方案，
决策 D1–D7 已冻结（含落地实现注记）。

**目标**：能声明 **trait 类型的变量/参数**（如 `Greeter g`），运行时把不同 `struct` 派发进来，
即真正的「面向接口编程」。

**已落地（0.2a–0.2d）**：

- 新产物 `struct <Trait>_iface { void *self; struct <Trait>_vtbl *vt; };`（不改既有命名与布局）；
- 类型展开：裸 trait 名 `Greeter g` / 参数 / 返回值 → `struct Greeter_iface …`；
- 装箱：`(struct Greeter_iface){ (void *)&p, &Person_Greeter_vtable }`，覆盖**声明、赋值、实参、`return`**；
  实参装箱依赖**函数签名表**（定义先于使用）；
- 派发：`g.greet()` → `g.vt->greet(g.self)`；
- 校验：struct 未 `use` 该 trait、跨 trait 装箱、无法推断类型的表达式 → 一律 `die`，不产出坏 C。

**暂未做**：接口**数组**（声明即 `die`）；接口**字段**的构造期自动装箱（指定初始化器里的接口字段不装箱）。
接口字段本身已可用（Phase 1 补齐）：值字段 `T x` → `struct T_iface x`、指针字段 `struct T *x` → `struct T_iface *x`；
`s.x.m()` 经字段自身的 vt 派发，值字段的语句赋值 `s.x = v;` 自动装箱（指针字段赋值保持原样）。

**用例**：`test/cases/18_polymorphism.ct`（同一 `announce(Greeter)` 服务 `Person` 与 `Shop`，
外加接口变量重赋值与接口返回值）。

### Phase 0.3：剥离越位特性（回到纯 OO 的 `ctc.c`）

**主题**：把 Phase 0 之后越位实现在 C 侧的语言特性**从 `ctc.c` 移出**，让主线回到「只做 Phase 0 出口 1–9 的纯 OO」+ 底层设施。移出件**不销毁**：归档为 **oracle**（仍可构建出对照程序），供 Phase 2–5 用 CT 重做时对差。

**剥离清单（2026-10-14 用户确认：只剥这四组）**：

| 能力 | 判断 |
| --- | --- |
| namespace（1.1）、多文件 `ct build` + `.h.ct` + `pub`（1.2）、`import`（1.3） | **剥**：非 OO；且多文件正是「跨单元引用带 trait 对象」这一自举唯一硬阻塞的来源 |
| `Drop`（1.4） | **剥**：非 OO（`delete q;` → `if (q) free(q);` 属出口第 7 项，保留） |
| `#line`（1.5） | **剥**：只在多文件下有意义，随多文件一并移出（自举前置 #5 随之**退役**） |
| 泄漏警告 + `--diagnostics=json`（1.7） | **剥**：非 OO |

**保留清单（看着像越位，实则属 Phase 0 出口或自举必需）**：

| 能力 | 判断 |
| --- | --- |
| 堆对象创建 `T *p = malloc(...)` 自动写 vptr（1.4） | **留**：出口第 7 项「创建」；且是**自举前置 #2**（AST / 符号表需动态分配，剥掉就要处处手写 vptr，「漏写即运行期崩」） |
| `delete` 放宽到 `char *`（1.4） | **留**：出口第 7 项「释放」+ **自举前置 #4** |
| 一般接收者（1.9a：变量下标 / 指针数组 / 指针字段链） | **留**：出口第 5/6 项「组合 / 存储」的覆盖 + **自举前置 #6** |
| 方法体接入同一重写管线（1.9c） | **留**：出口第 1/3 项（方法体内派发）的必要条件 |
| 接口**字段**（0.2 补做） | **留**：属 Phase 0.2 接口多态（出口第 9 项） |
| 右值接收者 `f().m()`（1.9b） | **留（2026-10-14 定）**：与 1.9a 同源，单独剥会造成「下标可以、右值不行」的不一致 |
| 文件作用域对象 / 数组 + `__ct_init` + `static`（1.6） | **留（2026-10-14 定）**：**自举前置 #3**（全局符号表要它） |

> **对自举就绪度的影响**：剥离项**都不在**自举前置清单里（或随多文件退役），故剥离**不会**削弱就绪度；反而移除了唯一的硬阻塞（跨单元带 trait 对象）与不再需要的 `#line`（前置 #5）。保留下的 #2/#3/#4/#6/#7 恰是「剥离后仍需留在 Phase 0 核心」的那几项——**这也给出了「纯 OO」的可操作判据：自举前置清单 ∩ 非越位特性**。

**连带处理（必须同批完成，否则验证与文档失真）**：

- **归档 oracle**：剥离前给当前 `ctc.c` 打 tag / 存档，并确认它能构建出对照二进制——否则 Phase 2–5 面对旧 golden 将没有可比对的实现。
- **测试收缩**：`test/import/`、`test/multifile/` 整目录，`test/cases/19_namespace`、`20_namespace_nested`、`22_drop`，`test/errors/` 中 `namespace_*` / `ns_*` / `drop_*` / `too_many_warnings`，`run.sh` 里的 `#line` 层，以及 `test/unit/test_helpers.c` 里针对被移出函数的断言，**全部移入归档**并退出 `run.sh`（否则套件必红，违反 [AGENTS.md](../AGENTS.md) §6）。（保留项用例——`test/cases/23_file_scope`、`27_static_file_scope`、`24`–`26` 接收者用例——**不动**。）
- **文档如实标注**：`README.md` 语法表与 `docs/language-spec.md` 相关条目须标「**已移出 L0，Phase 2–5 用 CT 回归**」，不得继续列为当前可用；`editors/vscode` 语法高亮**维持不动**（语法决策仍冻结，且高亮与编译器无关）。

**出口标准**：① `./test/run.sh` 在**收缩后**的套件上全绿；② `ctc.c` 只余 Phase 0 出口 1–9（+设施），`grep` 不到 namespace / 多文件 / `import` / Drop / `#line` / `--diagnostics` 的处理路径；③ 归档件可独立构建并复现旧 golden。

**完成记录（2026-10-14）**：

- `ctc.c` **3836 → 2897** 行（−939），删除 6 组越位实现；保留项的 golden **逐字节未变**（归档全部以 rename 形式记录，内容零改动）。
- 越位 fixture 移入 **[`test/archive/`](../test/archive/)**（`cases/` `errors/` `import/` `multifile/`，17 个 `.ct`），退出 `run.sh`，留作 Phase 2–5 的对差基线；完整旧实现见 git tag **`overreach-oracle`**。
- 套件 **146 → 110** 项全绿（收缩 42 项：multifile / import / `#line` / warnings 四层 + 相关 errors 与 cli 断言；新增 6 项「已移出特性必须报错」的断言）。
- **补了一道 fail-loud 守卫**：`namespace` / `import` / `pub` 若成构造形态出现，报 `'xxx' is not supported by this compiler`（exit 1），`ct build` 报 `'build' (multi-file) is not supported by this compiler`——否则这些语法会**静默透传**成编不过的 C，违反 [AGENTS.md](../AGENTS.md) §4。对应负例：`test/errors/removed_{namespace,import,pub}.ct`。
- 文档同步：`README.md`（CLI 表、语法表、测试计数）、`docs/language-spec.md`（§1–§10 逐节标注已移出）。

### Phase 1：自举（第一目标）

**主题（目标单一）**：把 Phase 0 的 **OO 化 C 语言**（剥离后的纯 OO `ctc.c`，即 L0）**用 CT 重写一遍**——与 L0 的目标完全一致，**唯一目的就是自举**。写法：OO 子集、**单文件**（L0 已无 namespace / import / 多文件，L1 无法分文件组织，见下）；出口是与 L0 **逐字节一致**。其余一切排在自举之后。

> **本阶段既不新增语言特性，也不恢复被剥离的特性**：只把 Phase 0 出口 1–9 的能力用 CT 重写一遍。特性恢复与新增一律从 Phase 2 开始。

**入口条件**：Phase 0.3 完成即满足。纯 OO 前提下自举**没有剩余硬阻塞**——就绪报告点名的「跨单元引用带 trait 对象」已随多文件一并移出；报告余下的表达力缺口（接口数组 `die`、构造期装箱、按行重写纪律）仍是 L1 源码必须遵守的纪律，见 [自举就绪总结报告](../reports/selfhost-readiness/selfhost-readiness.html) 与下方「已知约束」。

**L1 出口标准（go/no-go 门）**：L1 能被冻结的 `ctc`（L0）端到端编译并运行，且对同一批语料与 C 版输出**逐字节一致**。

**开工决策（2026-10-14 用户确认）**：

1. **零复用**：L1 **不** `#include ctc.c`，自带全部设施（`Buf` / 分配器 / `die` / 逐行扫描原语，约 200 行，以普通 C 透传写就）。理由：剥离后的 `ctc.c` = 纯 OO + 设施，include 进来会连 C 的 OO 核心一并复用，等于没自举，且「逐字节一致」退化为同义反复。早先「`#include` 只复用设施」的设想**作废**（它与「L1 必须用 CT 重写 OO」自相矛盾）。
2. **banner 逐字节相同**：L1 原样发出 `Generated by ctc v0.0.1 from <输入路径>`（含许可行）。否则 `test/cases/**` 全量 golden 需要重新生成，而重生成会掩盖真实差异；版本号与命令名的变更是独立事件，等单入口 `ct` 落地时一次性处理。
3. **源码位置与切片**：L1 源码为单文件 **`selfhost/ctc.ct`**（新增目录，用户已批准）。首个里程碑 **M2-a** 只覆盖 `test/cases/01_trait_basic.ct` 所需子集（trait / struct / impl / use、方法调用重写、`.h` 生成、banner），出口是对 `01_trait_basic.expected.c` / `.expected.h` **逐字节相等**；此后按 golden 用例逐个补齐剩余能力。用 golden 做**增量 oracle**，而不是一次性翻写。
4. **出口附加一项**：Phase 1 的完成判据除「与 L0 逐字节一致」外，还要**用 L1 编译 `selfhost/ctc.ct` 自身**成功（L1 是纯 OO 子集写的，功能完整后应当直接可行）——这是「真自举」的硬证据。
5. **L1 必须是 CT OO 风格**（2026-10-15 用户确认）：L1 的**数据模型层**（`Trait` / `Struct` / `Var` / `FuncSig` 等符号表）与**管线层**（逐行扫描、行重写、发射）必须用 CT 的 `struct` + `use` + `impl` 写成 OO 形态，**不得**退回 plain-C 直通；只有**设施层**（`Buf` / 分配器 / `die` / 扫描原语，约 200 行）按决策 1 保持 plain-C 透传。理由：CT 是 C 的严格超集，纯 C 直通的文件也「合法」，但对 OO 机制是**零证明**——那等于没自举（与决策 1 同构）。节奏为**分片推进**：先数据模型层 → 跑 `selfhost/check-m2a.sh` → 再管线层；每片以 byte-identical **不退化**为准绳，而不是以「跑得动」为准。附注（2026-10-15 实测）：L0 的 `MAX_FUNCS`（64）把 L1 里**每个 plain-C 函数签名**计入（定义与原型同等计数），而 `impl` 方法**不计**——该上限压力正是促使 L1 走 CT OO 风格的**健康约束**，不是要绕开的障碍；`ctc.c` 已冻结，**不得**为放宽它而改动。落地附注（2026-10-15）：管线层最终由**两个** trait 承载——`PipeOps`（主流程：构造解析、发射器、入口、CLI）与 `RewriteOps`（逐行重写层），`struct Pipe` 同时 `use` 二者；新增方法按归属放进对应的一半，避免单侧逼近 `MAX_METHOD`（32）。
6. **增量 oracle 落地为常驻关卡**（2026-10-15 用户确认）：`selfhost/check-goldens.sh` 把「L1 vs 全部 `test/cases/**` golden」做成一条命令，逐例比对 `.c` / `.h` 的字节，输出 `PASS / NEW / PENDING / REGRESSION` 四态与计数。脚本内的 baseline 名单是**棘轮**：只有已在名单里的用例失配才算回归并令关卡非零退出，未实现的族记 `PENDING`（连同 L1 的拒绝原因）不阻塞。起点实测（2026-10-15）：**13 pass / 0 new / 12 pending / 0 regression（共 25 例）**——12 个 pending 全部是 L1 主动 `die` 报「不支持」的留空能力族，不是算错。补齐顺序按**由小到大**：`13` 初始化形式 → `17` heap → 接口值（`21` → `18` → `28`）→ arrays（`16`）→ composition（`15`）→ 回头收互锁的 `23/24/25/26/27`（这些同时要 arrays 与 composition）。每片的出口是「byte-identical 不退化 + 把新通过的用例提升进 baseline 名单」。
7. **M2 达成，且 L1′ 自举闭环成为常驻关卡**（2026-10-15 实测）：`test/cases/**` 全量 **25 例逐字节一致**（25 pass / 0 new / 0 pending / **0 regression**），M2 出口达成。更强的一条也已实测——**L1 编译 L1 自身**得到 L1′，L1′ 以 `-Wall -Wextra -std=c99` **零警告**构建，再用**同一批语料**重跑，仍 **25 例逐字节一致**（`.c` / `.h` 与 L0 完全相同，含 banner）。这两条都固化进 `selfhost/check-goldens.sh`：第 4 步是 L1 vs golden，**第 5 步**是 L1′=L1 源码经 L1 编译 → 零警告构建 → 与 golden 逐字节比对，任一不符即令关卡非零退出。至此决策 4 的**出口附加项**（用 L1 编译自身）满足：Phase 1 的 go/no-go 门通过。此后新增能力一律排在 Phase 2 起（CT 侧重做），`ctc.c` 仍只接受 bug 修复。

**阶梯（M1→M2 属本阶段；M3–M6 属 Phase 2–5）**：L1 仅用 OO 子集写就；此后按 [bootstrap.md](design/bootstrap.md) 逐层爬升，每层以 **byte-identical golden** 为出口：

| 层 | 用 CT 实现 / 搬入 CT | 归属 |
| --- | --- | --- |
| L1（M2） | 用 CT（单文件、OO 子集）重写剥离后的纯 OO `ctc.c` | **Phase 1** |
| L2（M3） | namespace | Phase 2（前半） |
| L3（M4） | import + Drop | Phase 2（后半）+ Phase 3 |
| L4（M5） | JSON 诊断 + 泄漏警告 | Phase 4 |
| L5（M6） | 自举闭环（全功能对齐归档 oracle） | Phase 5 |

**阶梯约束（源语言滞后一级）**：第 n 级编译器只能编译「第 n−1 级所支持的语法子集」写成的源码。因此 CT 侧要**使用** namespace / Drop / import 组织编译器源码，必须先有支持它们的 CT 级编译器；**L1 只能是单文件**（Phase 0.3 已把多文件移出 L0），到 L2 起才能分文件组织。

> **名的歧义（2026-10-16 说明）**：「L2」在两个语境下含义不同——
> ① **能力阶梯**里的 L2 = 「支持 namespace 的那一级编译器」（M3，上表用法）；
> ② **本仓库实际产物**里的 L2 = 「L1 用 `build` 把 `selfhost/src/**` 编出来的那个二进制」（Phase 2 拆分产物，也是 Phase 3 起 ratchet 的被测对象）。
> 二者当前**能力不等**：产物 L2 已含 Drop（Phase 3），而阶梯意义上的 L2/L3 是对能力层级的抽象描述。为避免混淆，下文与关卡脚本里说「L2」一律指 ②。

**顺序原则（2026-10-14 更新为「剥离在前」）**：越位特性**在 Phase 0.3 就先从 `ctc.c` 移出**——先拿到干净的纯 OO L0，自举目标才最小；移出件**归档为 oracle**、不销毁，Phase 2–5 用 CT 逐项重做时向它差分。

**长期目标**：`ctc.c` **长期保留**为纯 OO 的种子与 oracle，不整体删除；Phase 2 起新增的一切能力都由 CT 层承担，`ctc.c` 不再增长。

#### 新 `ct` 与 `ctc.c`：`#include` 复用底层设施的设想（2026-10-14 提出；落地方式待定）

> **待定**：剥离后 `ctc.c` = 纯 OO + 设施，而 L1 又必须**用 CT 重写 OO**、不得复用 C 的 OO 实现。所以「只 include 设施」还需额外手段（设施与 OO 分段并以宏隔离；或把设施抽成独立小文件——但后者与「单文件」规约冲突），或者 L1 干脆**自带设施、零复用**（最纯的自举）。选定前本节仅作方向记录。

新 `ct` 用 CT 写、由冻结的 `ctc.c` 编译；它复用 `ctc.c` 的方式是 **`#include ctc.c`**（unity build，同 sqlite amalgamation），**不是**链接。边界：

- **保留在 C（被复用）**：**底层设施**——`Buf` / `xmalloc` / `xstrndup` / `die`（诊断）/ 逐行扫描原语 / 代码生成原语。
- **用 CT 重写（不复用）**：**OO 核心**（trait / struct / impl / use 转换）与**全部语言特性**。
- **include 是可收缩复用层**：随 CT 覆盖扩大，被 include 的 C 部分**逐步缩小**，最终只剩最底层设施。

> 为什么"只复用设施"而非"连特性一起复用"：被 include 的特性其实现仍是 C，等于没自举；且差分验证会失效（L1 的行为就是 `ctc.c` 的行为，"逐字节一致"成为同义反复）。只复用设施，才能既"避免重复"又保持自举与差分验证有效。

**落地前提（须在"只修 bug"冻结前一次性做完）**：

- `ctc.c` 的 `main` 需加 `#ifndef CTC_NO_MAIN` 守卫——否则与新 `ct` 的 `main` 落在同一 TU，重定义报错。**这是冻结前唯一一次结构性改造。**
- CT 代码必须**系统避开 `ctc.c` 的全部 `static` 标识符**（`buf_puts` / `die` / `word_at` / `emit_raw_line` …）；namespace 不修饰普通函数名，同 TU 重名即报错。
- `ctc.c` 的 `die()` → `exit(1)` 与进程级 `g_*` 需为**可复用 / 可重入**留出口（多文件 `ct build` 需逐单元、可按单元报错）。

**已知约束（开工前必须先接受）**：

- **接口数组声明即 `die`** → AST 子节点列表不能用 `Node kids[N]`，只能靠**接口指针 + 链表**；而指针接口字段的**赋值目前原样透传**（需手工构造胖指针）。**订正（2026-10-17）**：该「接口指针 + 链表」退路**本身不可靠**——指针接口字段赋值会**段错误**，且「接口指针局部声明」也 `die`；实测与订正见下方「三处表达力缺口与 AST 主线」。
- **接口字段不参与构造点递归、指定初始化式不装箱** → 装配 AST 时手工装箱代码增多（注：接口值字段的**赋值**其实已装箱，只有**构造点**没走 box 路径——见下方实测）。
- **按行重写**（构造与语句同行不处理、单行函数体不处理）→ 编译器源码必须遵守「一语句一行」的纪律，否则**静默不重写、产物编不过**。
- **声明必须先于使用 + 单趟扫描** → trait / struct 需人工拓扑排序；相互递归只能经接口指针。
- **namespace 只修饰 struct / trait / impl 符号，普通函数名不修饰** → 若按 namespace 切分源码，普通函数会在 C 层重名冲突（这也是先走单文件路径的一个动机）。

**三处表达力缺口与 AST 主线（2026-10-17 用户决定）**

自举就绪报告点名的三处缺口已由 [test/acceptance/run.sh](../test/acceptance/run.sh) **实测枚举**。L0 无错误恢复（一个错误即终止），故逐构造隔离成微探针——否则编译一次只会看见第一条 `die`：

| 微探针 | 缺口 | 实测现象 |
| --- | --- | --- |
| `p01` / `p02` | 接口**数组**声明（`Node kids[2]`、`Node *kids[2]`） | `die`：`unsupported declaration of interface type` |
| `p03` / `p04` | 数组元素**赋值 / 派发**（`kids[0] = a; kids[0].eval()`） | 受上一条门禁，当前不可达 |
| `p05` | 接口**值字段**在**构造点**装箱（`Pair p = { .l = a, .r = b }`） | ctc 产出**编不过的 C**（`void *` 收 `struct Leaf`） |
| `p06` | 接口值字段**赋值**（`p.l = a;`） | ✅ **已支持**（走既有 box 路径） |
| `p07` / `p08` | 接口**指针字段**（构造 / 赋值，`p.l = &a`） | ctc 静默透传 → 编译过（抑制 warning）→ **运行段错误 exit 139** |
| `p09`–`p11` | 对照组：接口局部来自值 / 指针、函数返回接口 | ✅ **已支持**（证明 box 子系统存在，harness 能诚实抵达 PASS） |

**订正**：「用**接口指针 + 链表**绕过数组缺口」这条退路**本身是坏的**——指针接口字段赋值静默透传并段错误，且**接口指针局部声明**（`T *g = 0;`，[test/errors/iface_pointer_init.ct](../test/errors/iface_pointer_init.ct)）同样 `die`。故 AST 子节点既不能数组、也不能指针链表，只能手工构造胖指针。三处缺口对外全部可见（`die` 或坏 C / 崩溃），**不存在隐藏的静默降级**。**三例连归档 oracle 都不支持**（oracle 对同三例同样 `die` / 产出坏 C / 段错误），故它们是**新增**而非「恢复」。

**用户决定（2026-10-17，三项均取推荐项）**：

1. **落点 = CT 侧（`selfhost/src/**`），`ctc.c` 保持冻结**——既然 trio 无归档 oracle 可对差（不属 Phase 2–4「恢复」类），就不该在 C 侧加；且 `ctc.c` 的 `MAX_FUNCS` 余量仅 1，C 侧无处可加。鸡生蛋问题有解：**先让 L1/L2 在纯子集里把缺口当作「它提供的一项特性」实现**（其源码不用该特性），再由它编出用该特性的新编译器——L0 全程不动。
2. **顺序 = 先落验收关卡、再逐条补**（消费者驱动：完整缺口清单从编译报错中长出，而非靠读码推断）。
3. **定位 = AST 版编译器作**新主线**，旧 `selfhost/ctc.ct`（L1）打 tag 归档**；出口口径由 **byte-identical** 换成 **行为等价**（同输入、同运行输出，不要求产物逐字节相同）。

**关卡**：[test/acceptance/run.sh](../test/acceptance/run.sh)（`PASS` / `PENDING` / `NEW PASS` / `REGRESSION` 四态，基线 `BASELINE` 现只含 `p06 p09 p10 p11`；退出码仅 `REGRESSION` 非零）。**故意不进 `./test/run.sh`**——`run.sh` 的绿必须继续意味着「编译器正确」，而非「编译器完备」。补齐后三条 PENDING 主项转 PASS、`ast_spike.ct`（[test/acceptance/ast_spike.ct](../test/acceptance/ast_spike.ct)）转 PASS，且 `test/errors/{iface_array,iface_pointer_init}.ct` 两条负例须**退役**（它们钉的是缺口存在，特性落地后不再 `die`）。

**过渡期纪律**：自举启动后**冻结一切新的 C 侧语言特性**；`ctc.c` 只接受 bug 修复。若 L1 暴露出 ct 表达力缺口，须先判定它属「语言特性」（放到 CT 层实现）还是「种子核心能力」（必须在 C 侧补）——后者要作为 **Phase 0 核心的修订定义**显式记录，不得顺手打补丁（这正是 Phase 0 历史偏差的复发点）。

**自举之后的恢复与新增（Phase 2–5 共用前提）**

自举（Phase 1）完成后才动手。出口判据按**类别**分两类（不再按子阶段分）：Phase 2–4 是**恢复**（有归档 oracle + 冻结 golden，出口 = **byte-identical**，无需再拍设计）；Phase 5 是**新增**（无 oracle 可对差，出口 = **设计冻结 + 新用例 + `run.sh` 全绿**）。实现层面的设计见 [design/restore.md](design/restore.md)（决策 D1–D8，仅 D6 / D7 待定；D8：`map` 移出，见 Phase 6）。

**实现方针——保真优先（2026-10-16 用户确认）**：用 CT 重做这些特性时，以**与归档 oracle 逐字节一致**为准，**包括复刻其既有行为与限制**（例如跨行块注释的 `/* … */` **续行**会被当作普通代码行处理，见 [language-spec](language-spec.md) §6.2）。因此**不修改 `test/archive/**` 的输入、也不重新生成任何归档 golden**——fixture 与 golden 都是冻结的 oracle；既有缺陷照实写进 §6.2，而不是靠改语料把它绕开。对差关卡是 [selfhost/check-archive.sh](../selfhost/check-archive.sh)。

**次序的三条硬约束（不能乱）**：

1. **Phase 2 必须最先**——只有 namespace + 多文件落地，CT 编译器源码才能分文件；`import` 也晚于它（依赖路径 / 符号解析）。
2. **Phase 3 是 Phase 5 的前置**——AutoDrop 依赖 Drop，路径敏感分析依赖作用域 + Drop。
3. **目录 = namespace 绑定依赖 Phase 2**，只能落在 Phase 5。

与 [bootstrap.md](design/bootstrap.md) 的阶梯对齐：M3 → Phase 2 前半；M4 → Phase 2 后半 + Phase 3；M5 → Phase 4；**M6（全功能对齐）在 Phase 5 收口**。

### Phase 2：模块化（原 2.1）

- **CT 重做**：namespace（`parse_namespace` + 限定查找 + 产物前缀 `<Ns>_<Struct>_<Trait>_<method>`）、多文件 `ct build` / `.h.ct` / `pub`（类型下沉 `.h`、`.c` `#include` 自己的头、可见性规则）、`import`（路径解析 + 递归编入 + 跨单元符号累积）。
- **出口**：归档用例**逐字节一致**；**编译器源码切成多文件**（后半程的最大红利，✅ 2026-10-16 达成 → `selfhost/src/**` 由 L1 建出 L2，见下条进展）。
- **对差依据**：`test/archive/cases/19_namespace`、`test/archive/cases/20_namespace_nested`、`test/archive/multifile/`、`test/archive/import/`。
- **风险**：命名前缀一经发布即契约，须先冻结；多文件破坏「`.c` 自包含」，须与 `pub` 可见性规则一起定案；`-I` 已定（**本地优先**：先查导入方所在目录，再按命令行顺序逐个查 `-I` 根）；跨单元 vtable 可见性**已定**（2026-10-16 拆分实测：vtable 发射为 `static`，**符号不可跨单元**，跨单元派发只走对象内已存的 vptr；头单元也无法携带 `MAX_*` / `size_t` / `FILE`——`pub` 前缀进不了 `.h`）。
- **进展（2026-10-16）**：**namespace 已达成**——`selfhost/check-archive.sh` 报 `19_namespace` 与 `20_namespace_nested` 逐字节一致（嵌套命名空间顺带达成），另有 4 条 namespace 负例（`namespace_bad_path` / `namespace_path_too_long` / `ns_path_nested` / `ns_qualified_name`，含逐字相同的诊断）通过并提升进关卡基线；Phase 1 出口不退化（`check-goldens.sh` 25/25、L1′ 一致）。实现要点：`g_ns` 扁平前缀、`read_qual_ref` 解析限定声明头、`transform_calls` 的 `::` 链重写、`compile_range` 的 namespace 分支（递归 + 压/还前缀）。**待做**：多文件 `.h.ct` / `pub` / `ct build` / `import`——`test/archive/{multifile,import}/` 的四个单元仍 PENDING。
- **进展（2026-10-16，切片 2d/2e + `.h.ct`/`-I`）**：**多文件 `ct build`、`pub`、`import` 与 `.h.ct` / `-I` 均达成**——`test/archive/{multifile,import}/` 四单元逐字节一致（`.c` 与 `.h` 两侧）并提升进 `baseline_multi`；本轮再补 **`.h.ct` 附加式命名**（基名剥 `.h.ct` → `foo.c` + `foo.h`，`import foo;` 回退命中 `foo.h.ct`）与 **`-I <dir>` 搜索根**（可重复；解析顺序 = 导入方目录优先，再按命令行顺序）。CLI 增 `build` 子命令（`compile` 兼作显式别名，build 模式 `-o` 为输出**目录**）；驱动 `collect_imports` / `resolve_import` / `unit_visit` / `build_output` / `build_main` 解析每个 `import a::b;`、按依赖后序逐单元以多文件模式编译并打印建议的 `cc` 命令。`pub` 函数行剥掉 `pub` 但原型进 `.h`（`.c` 留空行），`pub trait` / `pub struct` 只把类型放进 `.h`，`import` 行被消费，`#line` 映射（`line_of` / `line_at` / `line_break`）落在多文件 `.c` 里。**新语义的用例**放 `test/modules/**`，由 `check-archive.sh` **第 7 组 designed** 覆盖（无归档 oracle，自比对 golden + 端到端运行）：`hdr`（`.h.ct` 命名 + 回退）、`inc`（`-I` 使能用）、`inc_missing`（不给 `-I` 则必须报 `cannot resolve import`）、`precedence`（同名时导入方目录优先于 `-I` 根，钉住「本地优先」）。**待做**：`--line` / `--no-line` 覆盖开关（归 Phase 4）。
- **进展（2026-10-16，源码拆分 → L2）**：**后半程红利落地**——CT 编译器源码已从单文件种子 `selfhost/ctc.ct` 拆成多单元源码树 `selfhost/src/**`（`core.ct` + `driver.ct`），由 **L1 自身的 `build`**（多文件 + `import`）编译，产出 **L2**；出口判据 = **L2 对 `test/cases/**` 与 L1 逐字节一致（25/25）**，已达成（`check-goldens.sh` 第 6 步）。拆分触发的能力与**硬约束**（T0 探针实测）：① `pub` 前缀**进不了 `.h`**——`ctc.ct` 对 `#` 开头的行直接 verbatim 写进 `.c` 并提前 return，绕过 `pub` 路由，故**头单元无法携带 `MAX_*` / `size_t` / `FILE`**；数据、宏与单例只能留在 `core.ct`（落进 `core.c`），`driver.ct` 自带同值 `MAX_*` 副本。② `impl` / vtable 原生发射为 `static`，**符号无法跨单元引用**——跨单元派发只能经由对象内已存的 vptr（即"用访问器返回 `struct Pipe *` / `struct SymTab *` 后再 `->method()`"）。③ `MAX_FUNCS` 只对**顶层 plain-C 签名**累积（`pub` 原型 + 定义计一次）；本拆分只导出 10 个 `pub` 标量包装器（`ct_read_file` / `ct_is_ident_char` / `ct_usage` / `ct_default_output` / `ct_begin_imports` / `ct_add_import` / `ct_compile_file` / `ct_cc_reset` / `ct_cc_add` / `ct_cc_finish`）。**订正（2026-10-16，Phase 3 实测）**：该上限**也计入 `static` 顶层签名**，故余量其实很小——Phase 3 新增辅助函数已必须改用 `impl` 方法，详见 Phase 3 进展。**同源、不互相生成**：`selfhost/src/**` 与手写种子 `selfhost/ctc.ct`（L1）都是手写源码，种子保留。（**Phase 3 起改为「L1 冻结、新能力只落 `src/**`」**——双写不可持续，见 Phase 3 开工决策。）**新关卡**：`check-goldens.sh` 第 6 步（**硬判据**：L1 `build selfhost/src/driver.ct` → L2 → 语料逐字节）、`check-archive.sh` 3b、`check-m2a.sh` 第 7 步、`ct-tour.sh` 第 6 步。**新设计用例** `test/modules/split`（`pub trait` + `pub struct` 在头单元、`impl`（含 static vtable）在另一单元、第三单元经访问器返回的指针派发）钉住该跨单元契约，登记进 `check-archive.sh` 第 7 组 `baseline_designed`。**待做**：Phase 2 的 `--line` 与 Phase 3+ 的恢复项；`--line` / `--no-line` 覆盖开关仍归 Phase 4。
- **收口（2026-10-16 用户确认，口径 A）**：**Phase 2 到此结束**——**不 bump 版本号**（`CTC_VERSION` 保持 `v0.0.1`，冻结期不改），只打**非版本 tag `phase2-multifile-split`**；`v0.1.0` / `v0.2.0` 的 bump 与「单入口 `ct`」一并落地，届时一次性重生成全部 golden。两个出口均已达成，故本阶段无遗留功能项；`--line` / `--no-line` 归 Phase 4。

### Phase 3：内存（原 2.2）

- **CT 重做**：`Drop`（内置保留名 trait、惰性生成、递归释值字段）+ `delete` 放宽（任意指针 → `if (p) free(p);`）。
- **出口**：drop 用例**逐字节一致**。✅ 已达成（2026-10-16）。
- **对差依据**：`test/archive/cases/22_drop`、`test/archive/errors/drop_*`。
- **风险**：用户 `impl Drop` 与默认体的合并语义需定死。
- **开工决策（2026-10-16 用户确认，方案 B：L1 冻结）**：本阶段**不动 `selfhost/ctc.ct`（L1）**——L1 自此成为**冻结种子**（能力停在 Phase 2），新能力只落 `selfhost/src/**`。理由是双写不可持续：按 Phase 2 的「L1 与 `src/**` 同源」字面执行，Phase 3–7 每项特性都要写两遍。这与上一级同构——`ctc.c` 冻结后开发搬到 L1，L1 冻结后开发搬到 `src/**`。**代价是关卡语义改变**：`check-archive.sh` 的 ratchet 从 L1 换成 **L2**（L1 `build` `src/**` 得到），并新增 `check-goldens.sh` **第 7 步不动点**（L2 也编 `src/**`，产出须与 L1 逐字节一致）。
- **进展（2026-10-16，Drop 落地）**：**`Drop` 与 `delete` 分流均已在 `selfhost/src/core.ct` 实现**，`22_drop` 的 `.c`/`.h`/运行输出三侧与归档 oracle **逐字节一致**，5 条 drop 负例（`drop_reserved` / `drop_impl_undefined_struct` / `drop_impl_not_used` / `drop_impl_no_method` / `drop_impl_no_body`）全部通过——`check-archive.sh` 的 `baseline_cases` 增至 3 例、`baseline_errors` 增至 9 条。实现要点：`Struct` 增 `has_drop` / `has_user_drop` / `drop_used` / `drop_bstart` / `drop_blen` / `def_line`；`use Drop` 只置标记（**不进 vtable、不加 vptr**）；`trait Drop` 报保留名；`parse_impl` 特判 `impl Drop for T` 并抓用户函数体；`delete p` 对 Drop 类型改发 `if (p) { T_Drop_drop(p); free(p); }`；发射分两处——**原型在图前、定义在图后**（`compile_file` 为此把主体先写进 `tmpfile()` 再回填，与 oracle 同构），且只对 `delete` 真正触达的类型发射（`mark_drop_closure` 做传递闭包），避免 `-Wunused-function`。**签名上限的实测教训**：`MAX_FUNCS`（64）**计入所有顶层 plain-C 签名（`static` 也算）**，`src/**` 余量已近乎为零——两个新辅助函数因此改为 `impl` 方法（`SymTabOps::mark_drop_closure`、`RewriteOps::body_uses_self`），不是风格偏好而是硬约束；`PipeOps` 现为 31/32。
- **验证（2026-10-16）**：`check-goldens.sh` 25/25 + L1′ 25/25 + L2 25/25 + **不动点 2/2 单位一致**；`check-archive.sh` 0 退化（单单元 3 pass、诊断 9 pass / 1 pending、多单元 4 pass、designed 5 pass）；`check-m2a.sh` 与 `ct-tour.sh` 退出 0；`./test/run.sh` 115 项全绿（沙箱内摘除 `cli/compile-cannot-write` 后实跑 114/0）；`ctc.c` 与 `selfhost/ctc.ct` 相对 `audit-1` 无改动。

### Phase 4：诊断与溯源（原 2.3）

- **CT 重做**：`#line`（多文件默认开，D4 = A）、泄漏警告 + `--diagnostics=json`（首版范围见 1.7）。
- **新增（无 oracle，须配新用例）**：多错误报告 + 错误恢复（跳到下一个行首 / `}`）、语义诊断（重复 trait / struct 定义报错、方法签名与 trait 不一致时告警）。
- **出口**：诊断层全绿；`#line` 能把 gcc 报错映回 `.ct` 行。
- **对差依据**：`test/archive/errors/*`、`run.sh` 的 `#line` 层。
- **风险**：错误计数与重同步点容易产生级联误报；语义诊断要与「不做类型检查」的定位边界划清。
- **进展（2026-10-16，切片 1：`#line` 开关收尾）**：`--line` / `--no-line` 已在 `selfhost/src/**` 落地——`core.ct` 新增全局 `g_line_force`（`-1` 随模式 / `0` 强制关 / `1` 强制开），`g_emit_line = (g_line_force >= 0) ? g_line_force : multi;`；`ct_compile_file` 增第 4 个参数 `line_force`，`compile_main` 与 `build_main` 两条 CLI 路径均解析并透传，usage 文本补上两行。新增两个 designed fixture（`test/modules/noline/`：`build --no-line` 抑制多文件默认开；`test/modules/line/`：`compile --line` 单文件强制开），`check-archive.sh` 第 7 组由此扩展出 `compile.args` 分支（单文件用例在暂存副本里原样跑参数，banner 路径才与 golden 对齐），`baseline_designed` 增至 7 例。**单文件默认仍为关**，故 L2 单文件产物与 L0 逐字节一致。**尚未做**：语义诊断（4）。新代码一律进 `impl`（`MAX_FUNCS` 余量仅 1）。
- **进展（2026-10-16，切片 2：泄漏警告 + `--diagnostics`）**：oracle 的保守、路径不敏感泄漏警告已在 `selfhost/src/**` 恢复——`Var` 增 `owned` / `own_line`，指针声明处的 `malloc` / `calloc` 记为持有（`new_var` 复用槽位时清这两个字段），`delete` 与 `return` / 逃逸赋值清标记，作用域闭合时 `leak_check_scope` 收集仍持有的对象，`emit_warnings` 按 `--diagnostics=json` 发 JSON（compile 走 stdout、build 走 stderr，后者把 stdout 留给 cc 命令）、按 text 发 stderr。归档负例 `too_many_warnings` 由 PENDING 转 PASS（超 `MAX_WARNS` 仍 `die`）。**5 个新方法全部进 `SymTabOps`（9 → 14）**，warning 输出复用既有 pub 包装器（单文件 `ct_compile_file`、build `ct_cc_finish`），**顶层函数零新增**——`MAX_FUNCS` 余量仍是 1。新增 3 个 designed fixture：`leak`（compile text）、`leak_json`（compile json → stdout）、`leak_build`（build json → stderr），`check-archive.sh` 第 7 组新增 `expected.stdout` / `expected.stderr` 逐字节断言。**尚未做**：语义诊断（4）。
- **验证（2026-10-16，切片 2）**：三套 golden 全部由 tag `overreach-oracle` 编出的 oracle 生成，L2 与之在 `.c` / `.h` / stderr / stdout 四侧逐字节一致（含 `--diagnostics=bad` 的 `unknown diagnostics format` 报错）；`check-archive.sh` 0 退化（单单元 3 pass、诊断 **10 pass / 0 pending**、多单元 4 pass、designed **10 pass**）；`check-goldens.sh` 25/25 + L1′ 25/25 + L2 25/25 + 不动点 2/2；`check-m2a.sh` / `ct-tour.sh` 退出 0；`./test/run.sh` 115/115；手工三件套通过，L2 单文件产物与 L0 逐字节一致。
- **进展（2026-10-16，切片 3：多错误报告 + 重同步）**：`die` 不再一律退出——`compile_range` 的逐行循环每轮用 `setjmp` 设一个守卫，`die` 报告后 `longjmp` 回守卫（无守卫时仍是原来的「一处错误即停」，OOM 亦然）。守卫处快照、处理分支里还原 `sym->nvars` / `g_nscope` / `g_body_abs`（长跳转会把 `emit_body` 的还原跳过），嵌套 namespace 的递归靠保存/拷回 `jmp_buf` 保住外层守卫。重同步点由 `RewriteOps::recover_pos` 给出：自错误处向后，取「下一个 `}` 之后」与「下一行行首」的先到者（跳过字符串与注释），并保证严格前进。错误上限 `MAX_ERRORS=20`，超过即打印 `ctc: too many errors, stopping` 后退出 1。失败的编译按本次调用的错误增量**删除**已写的 `.c`/`.h`，并在 stderr 末尾补 `ctc: N error(s) generated`。**尚未做**：语义诊断（切片 4）。
- **验证（2026-10-16，切片 3）**：3 处错误的样例三处全报 + 摘要 + 退出 1 + 无产物；`MAX_ERRORS` 边界（第 21 处后停止）、namespace 嵌套内错误、函数体内错误均符合预期，且后一处错误的位置不受前一处长跳转影响（与 L0 的既有位置一致）。`check-archive.sh` 0 退化（designed **12 pass**，新增 `multi_err` / `multi_err_build`）；`check-goldens.sh` 25/25 + L1′ 25/25 + L2 25/25 + 不动点 2/2；`check-m2a.sh` / `ct-tour.sh` 退出 0；`./test/run.sh` 115/115；手工三件套通过。

### Phase 5：新增特性（原 2.4）

- **AutoDrop**：被标记的变量在作用域结束时自动 `drop()`（不 `free`，只释放其持有的资源）。
- **路径敏感泄漏分析**：分析所有 `return` 路径，标出「某些路径上未释放」。
- **目录 = namespace 强制绑定**。
- **出口**：**设计先行 → 冻结 → 新用例 → `run.sh` 全绿**；明确**不追求** byte-identical（无 oracle 可对）。此处同时收口阶梯 **M6**。

**需用户先定位、暂不排期**：是否引入**类型检查**（若引入，编译器性质改变，需要 AST 而非逐行扫描）；是否引入**泛型**（需在 `.c` 侧单态化展开）；是否要保证**生成物可读性**的硬指标（最大嵌套缩进、命名长度上限）。

### Phase 6：生态与扩展（原 Phase 3）

- **生态绑定**：`map` + 反向映射表（经 D8 移出自举主线；落定时与官方 bindings 清单一并定案）。
- **方言系统（Dialect）**：写在注释里的领域专用语法，由编译器之外的展开器脚本转成纯 CT，`ctc` 全程零感知。设计已定型但未实现，**排期在本阶段**（2026-10-13 用户确认；排期口径随 2026-10-14 相位重排更新）——排序选择而非技术依赖，展开器是外部脚本、不与自举耦合。落地前须先修订与 [AGENTS.md](../AGENTS.md) §2 的三处边界冲突（代码生成脚本 / 插件调用编译器 / 包管理分发）。详见 [design/dialect.md](design/dialect.md)（设计草案，未实现）。
- **构建**：增量编译缓存、跨函数泄漏分析、多目标编译。

### Phase 7：工具链形态（单入口 `ct`）

- **落地内容**：一个 `ct` 命令承载全部功能，靠子命令区分——`ct compile`（即现有编译能力）/ `ct build` / `ct get` / `ct install`；按 `argv[0]` 分派，`ctc` 作为软链或副本保留为**兼容别名**（同 busybox 的做法）。设计已冻结（见「已定的设计决策 · 工具链形态」），**本阶段只差落地**。
- **出口**：`ct compile` 可用，且既有 `ctc …` 调用不失效；README 与脚本中的命令统一换成 `ct`。
- **依赖**：`ct build` 属 Phase 2（多文件），故本阶段排在其后；`ct get` / `ct install` 依赖包管理器（名字待定，见「决策待定项」）。
- **风险**：命令改名会波及 README、脚本与全部既有文档里的 `ctc` 用法，必须一次性替换并复核。

自举的目录结构、分层规则（L0/L1/L2）与构建流程见 [design/bootstrap.md](design/bootstrap.md)。

### 决策待定项

| 问题 | 候选 | 影响 |
| --- | --- | --- |
| `.c` 是否 `#include` 自己的 `.h` | ✅ 已定：多文件场景下 `.h.ct` 生成 `.h` + `.c`，`.c` 包含自己的头（见「文件命名约定与 `pub` 可见性」） | 越位实现时打破 Phase 0 自包含约定 |
| 位置式初始化的语义 | ✅ 已定：A. 自动追加 vptr（0.1.2） | 允许 `{ "Tom", 36 }` 写法 |
| 指针声明的处理 | ✅ 已定：修正生成（`struct Person *p`）并登记为指针，`p->m()` 重写 | 已落地于 Phase 0.1.1 / 0.1.4 |
| 工具链形态 | ✅ 已定：单入口 `ct`，`ctc` 保留为兼容别名 | 见「已定的设计决策」，**尚未落地** |
| 包管理器的名字 | A. `ct-pkg`／B. `ctpm`／C. 独立品牌词 | registry 与组织名需趁早占位 |
| 容量上限策略 | A. 继续固定上限／B. 超限即报错／C. 改动态分配 | 与「失败要响」原则的落地方式 |
| 过渡期是否冻结一切新特性 | ✅ 已定：自举（Phase 1）启动起冻结一切新的 C 侧语言特性，`ctc.c` 只接受 bug 修复（2026-10-14 相位重排） | 防止 Phase 0 历史偏差复发 |
| C 实现最终删除还是归档 | ✅ 已定（2026-10-14）：「**剥离在前**」——Phase 0.3 先把越位特性移出 `ctc.c` 并**归档为 oracle**（不销毁），Phase 2 起用 CT 逐项重做并向归档对差；`ctc.c` 剥回纯 OO 核心并**永不整体删除** | 见「Phase 0.3」「自举策略与单文件边界」 |
| 类型检查 / 泛型 / 生成物可读性硬指标 | 待定，见「Phase 5」 | 若引入类型检查，编译器性质改变，需要 AST |

---

## English

This file records **plans only**, never current behaviour — see [README](../README.md) and
[language-spec](language-spec.md) for what exists today. Everything below is a proposal unless marked
as confirmed by the user.

### Phase overview

| Phase | Theme | Class | Status | Exit criteria |
| --- | --- | --- | --- | --- |
| 0 | Writing full OO with traits (encapsulation / interfaces / dispatch / passing / composition / creation & release / interface polymorphism) | build | ✅ done (exits 1–9 hold; **automatic heap creation** is deferred to after Phase 0 per 0.1.8, and has landed) | every exit below holds |
| 0.1 | Defect fixes + regression tests | build | ✅ done (0.1.1–0.1.9) | composition / arrays / scoping / interface polymorphism all covered; golden tests green |
| 0.2 | Interface polymorphism: traits as types, dispatching at run time | build | ✅ done (design first → implemented) | interface **arrays** are not implemented; interface **fields** landed |
| 0.3 | **Strip the over-reach**: move the C-side over-reaching features (namespaces / multi-file / import / Drop / diagnostics) out of `ctc.c` so it returns to **pure OO + low-level facilities**; the extracted code is **archived as the oracle** (never destroyed) | build | ✅ done (2026-10-14) | `ctc.c` 3836 → 2897 lines; the suite went 146 → 110 and is green; the archive lives in `test/archive/` + tag `overreach-oracle` |
| 1 | **Self-hosting (the first goal)**: with the stripped, pure-OO `ctc.c` as L0, rewrite **all of its capabilities** in CT (OO subset, single file), exiting on **byte-identical** output with L0 | build | ✅ done (2026-10-15: M2 at 25/25, and the L1′ self-hosting loop passes) | only rungs M1→M2 (L1); every layer exits on a **byte-identical golden** |
| 2 | **Module system**: namespaces / multi-file `ct build` / `pub` / `import` | restore | ✅ done (2026-10-16; non-version tag `phase2-multifile-split`) | archived cases **byte-identical**; the compiler source itself becomes multi-file |
| 3 | **Memory**: Drop / loosened `delete` | restore | ✅ done (2026-10-16; implemented under `selfhost/src/**`, L1 frozen) | drop cases **byte-identical** |
| 4 | **Diagnostics & traceability**: `#line` / leak warnings / `--diagnostics` + multi-error recovery / semantic checks | restore + new | 🚧 in progress (from 2026-10-16; slice 1: `--line` / `--no-line` landed) | the diagnostics layers are green; `#line` maps a gcc error back to the `.ct` line |
| 5 | **New features**: AutoDrop / path-sensitive leak analysis / directory = namespace | new | 🔭 outlook | design frozen + new cases green; rung **M6** closes here |
| 6 | **Ecosystem and extension**: `map` + the reverse mapping table (D8), the dialect system; incremental compilation, cross-function analysis, multi-target | extension | 🔭 outlook | — |
| 7 | **Toolchain shape**: single-entry `ct` + the `ctc` compatibility alias (design frozen, only the landing is left) | landing | 🔭 outlook | `ct compile` works and existing `ctc …` invocations keep working |

> **Historical note**: right after Phase 0 the namespace / import / Drop / diagnostics / multi-file
> features were once implemented **directly in C** (`ctc.c`, the old "Phase 1"). Under this roadmap
> they count as **over-reach**: the syntax decisions stay frozen, but the **implementations are to be
> redone in CT** — **Phase 0.3** moves them out of `ctc.c` and archives them as the oracle, and
> **Phases 2–5** restore them in CT (the list is under "Restoring and adding features after
> self-hosting" below).
>
> **Numbering convention**: the labels `Phase 1.0`–`Phase 1.9`, `Phase 1.6/1.7/1.9c` below are
> **historical sub-phase numbers of the over-reach period** and have nothing to do with the new
> **Phase 1 (self-hosting)**. `Phase 0.1` / `0.2` / `0.3` are **historical sub-phases of Phase 0** and
> keep their numbers.
>
> **Renumbering record (confirmed by the user on 2026-10-16)**: the old "Phase 2 (4 sub-phases) +
> Phase 3" dressed **feature families** up as sub-phases (2.1–2.3 actually share one DoD class,
> "restore") and could not be mapped one-to-one onto versions. The sub-phases are now **promoted to
> first-level phases**, the **Class** (restore / new) became a column of the overview table, and a
> Phase 7 was added:

| Old | New | Theme |
| --- | --- | --- |
| Phase 2.1 | **Phase 2** | module system (namespaces / multi-file / `pub` / `import`) |
| Phase 2.2 | **Phase 3** | memory (Drop / loosened `delete`) |
| Phase 2.3 | **Phase 4** | diagnostics & traceability (`#line` / leak warnings / `--diagnostics`) |
| Phase 2.4 | **Phase 5** | new features (AutoDrop / path-sensitive analysis / directory = namespace) |
| Phase 3 | **Phase 6** | ecosystem and extension (`map` / dialect system / incremental compilation …) |
| (none) | **Phase 7** | toolchain shape (single-entry `ct` + the `ctc` alias) |

> When reading an older document (or an older report under `reports/`) that says "Phase 2" or
> "Phase 3", convert it with the table above. Phase numbers and versions are now **one-to-one**:
> Phase *n* ↔ `v0.n.x` (see "Versions").

### Versions

| Version | Phase | Contents |
| --- | --- | --- |
| v0.0.1 | Phase 0 | trait / struct / impl / use rewriting, method-call rewriting, matching `.h`, five-layer regression suite |
| v0.1.0 | Phase 1 self-hosting (**milestone reached, not bumped yet**) | L1 (`selfhost/ctc.ct`) is byte-identical with L0 on all of `test/cases/**` (25/25), and L1 compiling itself (L1′) reproduces the same corpus byte for byte |
| v0.2.0 | Phase 2 module system (**milestone reached, not bumped yet**) | namespaces / multi-file `ct build` / `pub` / `import` / `.h.ct` / `-I`; the archived cases are byte-identical and the compiler source is split into `selfhost/src/**` (L1 builds L2, byte-identical on `test/cases/**` 25/25) |
| v0.3.0 | Phase 3 memory (**milestone reached, not bumped yet**) | Drop / loosened `delete`, restored under `selfhost/src/**` (L1 frozen); `22_drop` byte-identical |
| v0.4.0 | Phase 4 diagnostics & traceability | outlook: `#line` / leak warnings / `--diagnostics` |
| v0.5.0 | Phase 5 new features | outlook: AutoDrop / path-sensitive analysis / directory = namespace |
| v0.6.0 | Phase 6 ecosystem and extension | outlook: `map` / dialect system / incremental compilation |
| v0.7.0 | Phase 7 toolchain shape | outlook: single-entry `ct` + the `ctc` alias |

The version lives in `CTC_VERSION` inside `ctc.c` and is written into the generated comments, so
changing it requires regenerating every golden (see [AGENTS.md](../AGENTS.md) §5).

**Version rules (confirmed by the user on 2026-10-15)**:

- Versions look like **`v0.<phase>.<patch>`** and are bumped **only at phase boundaries**; the `patch`
  slot is reserved for in-phase fixes that require regenerating goldens. The mapping is **one-to-one**:
  `0.<n>.x` = Phase *n* — `0.0.x` = Phase 0 (done, currently v0.0.1), `0.1.x` = Phase 1 self-hosting
  (done, not bumped yet), `0.2.x` = Phase 2 module system, `0.3.x` = Phase 3 memory, `0.4.x` = Phase 4
  diagnostics, `0.5.x` = Phase 5 new features, `0.6.x` = Phase 6 ecosystem, `0.7.x` = Phase 7 toolchain;
  `1.0.0` = the language is final.
- **A tag name must equal `CTC_VERSION`.** Hence "no bump, no `v`-numbered tag"; a milestone that is
  not bumped gets a non-version tag (today `phase1-m2` marks the v0.1.0 milestone).
- **Why a bump must be careful**: `CTC_VERSION` goes into the output banner, so one bump means
  regenerating every golden under `test/cases/**` plus the examples' `.expected.out`, and changing
  **both** `ctc.c` and `selfhost/ctc.ct` (L1 carries its own copy of the version, line 84) — if the two
  disagree, `selfhost/check-goldens.sh` goes red immediately. Changing `CTC_VERSION` during the freeze
  is a "not allowed" item and needs one explicit user-authorised exception.

### Decided design decisions

#### Toolchain shape: a single-entry `ct` (decided, not implemented yet)

- **Final shape:** one `ct` command carries everything, with subcommands — `ct compile` (today's
  compiler), `ct build`, `ct get` / `ct install` (package management, to be built).
- **`ctc` stays as a compatibility alias**, so existing docs, scripts and habits keep working.
- **Implementation (to confirm when we build it):** dispatch on `argv[0]` in a single binary, the way
  busybox does, with `ctc` as a symlink or copy of `ct`.
- **Status: not implemented.** Today's binary is still `ctc`; neither `ct` nor its subcommands exist,
  so commands in the README are still written as `ctc`. They get replaced in one pass when the
  implementation lands, so the docs never point at a command that does not run.

Migration checklist (executed from the over-reach phase on): add subcommand parsing to `main` (`compile` as the
default, `ctc` dispatching by `argv[0]`); build as `gcc ctc.c -o ct` plus a `ctc` alias; change the
generated comment from `Generated by ctc …` to `Generated by ct …` (**requires regenerating every
golden under `test/cases/**`**); update every `ctc` command in `README.md`, `AGENTS.md` and `docs/*`;
and update the build/invocation paths in `test/run.sh`.

#### What package management needs first (more important than naming)

- Its real prerequisite is **multi-file compilation** (already listed for Phase 1): type definitions
  move down into `.h` and the generated `.c` starts to `#include` its own header. That breaks the
  Phase 0 promise that the `.c` is self-contained — a breaking change.
- A package's interface boundary is naturally a **trait**: a package is a set of `.ct` files plus the
  `.h` it exposes (the trait declarations). This decides what a package manager and a registry can
  look like.

#### Naming the package manager (open)

- Candidates: `ct-pkg` (descriptive), `ctpm` (in the spirit of npm), or a standalone brand word like
  `cargo` / `dub` / `mix` (more distinctive, but newcomers will not guess it belongs to ct).
- **Claim the registry and organisation names early.** Both `github.com/ct-lang` (registered 2022) and
  `github.com/ctlang` (registered 2019) are held by dormant accounts with one repository and no
  followers, so an organisation needs a different name.

#### License (decided and shipped)

- The **compiler** is GPL-3.0-or-later (`LICENSE`); **`.ct` sources and the generated output are not
  covered by the GPL** (`LICENSE.EXCEPTION`, following the GNU Bison precedent and travelling with the
  output); **`examples/` and `test/` are MIT**.
- The exception is not optional: ctc inserts boilerplate of its own into the output (vtable structs,
  vptr fields, the `_self` cast line), so whether compiler output counts as a derivative work is
  ambiguous — leaving it unstated blocks adoption, especially with corporate legal review.

#### Namespace path rules (decided, landed in the over-reach phase)

CT uses hybrid path access: **`::` walks the namespace path, and the final step uses `.` to call a
method or access a field**. The final step is always `.`.

```c
// Correct
HAL::UART::huart1.send(data, len);
HAL::GPIO::pinA5.set(1);

// Static functions use ::
HAL::UART::get_default_config();

// Wrong
HAL::UART::huart1::send(...);   // the final step cannot use ::
HAL.UART.huart1.send(...);      // the middle cannot use .
```

| Situation | Symbol | Example |
| --- | --- | --- |
| Namespace path navigation | `::` | `HAL::UART` |
| Method call / field access | `.` | `huart1.send(...)` |
| Static function call | `::` | `HAL::UART::init()` |
| Trait method reference | `.` | `obj.method()` |

When this lands it is written into [language-spec](language-spec.md) and enforced by the compiler.

#### import and the module system (decided, landed in the over-reach phase)

`import` is not syntactic sugar for `#include` — it is a **compilation-unit declaration**. The
compiler builds the module dependency graph from `import`s and handles symbol references, compilation
order and linking automatically:

```c
import HAL::UART;      // tells the compiler: HAL::UART symbols live under hal/uart/
import Driver::Sensor; // tells the compiler: Driver::Sensor symbols live under driver/sensor/
```

Internal behaviour:

1. scan every `.ct` file and build the module table (namespace → source path)
2. resolve `import` edges into a dependency DAG
3. compile in topological order
4. each `.ct` → `.c` + `.h`
5. link every `.o`

Phase 0 has no `import` (single file); Phase 1 implements it.

#### File-naming convention and `pub` visibility (decided, landed in the over-reach phase)

The file name decides what the compiler emits — no extra keywords or config files:

| File name | What is generated |
| --- | --- |
| `foo.ct` | only `foo.c` (implementation; nothing exported), symbols are file-local by default |
| `foo.h.ct` | `foo.h` + `foo.c` (interface / implementation split) |

The compiler recognises the symbols to export via the `pub` keyword and generates the `.h` (with
`#ifndef` guards, struct definitions, function declarations, vtable types) and the `.c` (with the
implementations):

```c
// uart.h.ct
namespace HAL::UART {
    pub trait Controller {
        void send(uint8_t *data, int len);
        int recv(uint8_t *buf, int len);
    }

    pub struct UartDevice {
        int baud;
        int fd;
    }

    pub UartDevice init(int baud);
    pub void deinit(UartDevice *d);
}
```

Visibility modifiers:

| Modifier | Effect |
| --- | --- |
| `pub` | exported (goes into the `.h`) |
| `static` | file-private (not in the `.h`, not in the symbol table) |
| `pub readonly` | readable but not writable from outside (`const` or a getter is generated) |

Visibility applies to declarations inside a namespace, to struct fields, and to trait methods; the
compiler enforces it and rejects violations. Encapsulation is enforced by the compiler, so the
"implemented in the `.c` but never declared in the `.h`" inconsistency cannot happen.

#### Memory management: Drop and delete (decided, landed in the over-reach phase)

The compiler has a built-in `Drop` trait. Declaring `use Drop` on a struct makes the compiler
generate the release logic:

```c
struct MyDevice {
    uint8_t *buf;
    Filter *filter;
} use Drop;
```

Generation rules:

- for each field whose type also has `use Drop` → call `drop()` recursively
- scalar types (int / char / float / raw pointers) → untouched
- if the struct itself is heap-allocated → `free(self)`
- users can customise with `impl Drop for MyDevice { void drop() { ... } }`
- **no call, no code**: if nothing in the project ever calls a type's `drop()`, no drop-related
  function body is generated at all — zero overhead

`delete` is the single entry point for releasing an object. Phase 1 **extends** the minimal version
already landed (0.1.8: `delete p;` → `if (p) free(p);`, only for registered ct-struct pointers) by
adding the `drop()` call — it is **not** a re-plan: the `delete` form and entry point already exist:

```c
MyDevice *d = MyDevice::create();
// ... use ...
delete d;    // expands to: if (d) { d->drop(); free(d); }
```

| Situation | Expansion |
| --- | --- |
| Heap object (pointer) + `use Drop` | `T_drop(ptr); free(ptr);` |
| Heap object without Drop | `free(ptr);` |
| Stack object | compile error (or only `drop()`, no `free`) |
| NULL pointer | guarded by `if (ptr)`, a safe no-op |
| Pointer to a scalar | equivalent to `free(ptr)` |

Arrays are released with `delete[]`: `drop()` each element, then `free`.

**Compile-time leak warnings (Phase 1, simple version):** at the end of a function, a local that was
allocated but never `delete`d, `return`ed, or stored globally produces a warning. The path-sensitive
version (analysing every return path) is Phase 5 (outlook). Warnings are emitted both as a human-readable list
and as JSON for the VS Code extension:

```json
{
  "warnings": [{
    "type": "potential_leak",
    "file": "src/main.ct",
    "line": 23,
    "variable": "sensor",
    "type_name": "BME280*",
    "message": "allocated but never deleted"
  }]
}
```

Suppression: annotate intentional leaks (e.g. objects living globally) with `#[allow(leak)]`.

#### The map syntax and the reverse mapping table (decided, lands in Phase 6)

The `map` keyword maps trait methods onto SDK calls of a concrete instance:

```c
map trait Controller for instance huart1 {
    send(data, len) → HAL_UART_Transmit(&huart1, data, len, HAL_MAX_DELAY);
    recv(buf, len) → HAL_UART_Receive(&huart1, buf, len, HAL_MAX_DELAY);
}
```

The compiler generates the corresponding vtable entries so `huart1` can be used as an instance of the
`Controller` trait.

The compiler also maintains a **reverse mapping table** (which C symbol in the output came from which
CT trait/method), used for: meaningful provenance in error messages, "go to definition" in the VS Code
extension, and recovering CT semantics when decompiling.

> **Scheduling (D8, decided by the user on 2026-10-14)**: moved off the self-hosting mainline and
> scheduled for Phase 6, implemented last. `map` is an ecosystem-binding feature, not part of the self-hosting mainline;
> neither the exit criteria nor the bootstrap checklist depend on it, and its real
> consumer (the official bindings) does not exist yet — freezing instance semantics early would design
> against imagined use cases. Settle it together with the bindings list when it lands.

#### JSON diagnostics and the thin-client extension (decided, landed in the over-reach phase)

`ctc` emits JSON: compile errors/warnings (including leak warnings), the symbol table (positions of
namespaces / traits / structs / functions), and the call graph. The VS Code extension consumes the
JSON as a thin client — inline diagnostics, go to definition, completion, hover types — and does no
compilation or analysis of its own, so compiler upgrades never require extension changes.

> **First cut (Phase 1.7, Q1=A decided by the user on 2026-10-13)**: `--diagnostics=json` emits the
> **diagnostic list only** (`{"warnings":[…]}`); the symbol table and call graph are **not implemented
> yet** and are separate sub-items. `--diagnostics=text` (the default) is human-readable stderr.

#### Bootstrap strategy and the single-file boundary (decided; `ctc.c` freezes when self-hosting starts, the layout lands once it settles)

- **Progressive self-hosting**: L0 (the minimal trait compiler in C — today's `ctc.c`) → L1 (a base
  compiler written in the CT trait-only subset) → L2 (the full compiler written in full-featured CT).
- **Phase 0 boundary**: `ctc.c` stays at the repository root as a single file (confirmed by the
  user on 2026-10-11); no `src/`, no splitting. The move is only discussed once self-hosting starts.
- **Minimal self-hostable version (confirmed by the user on 2026-10-14)**: aim for self-hosting in a
  **single file** first (no namespaces / `import` / multi-file), side-stepping prerequisite #1
  "referencing a trait-carrying object across units" (vtable variables are `static` and the `.h`
  carries types only, so another translation unit can neither write a vptr nor dispatch). The one hard
  blocker on the single-file path — "an `impl` method body cannot dispatch across objects" — was
  removed by **Phase 1.9c** (a body now goes through the very same pipeline as top-level code:
  `self` / method parameters are registered, then every line runs `transform_line`). Conclusion: a
  **single-file, fully-OO program is self-hostable now** — non-OO features (namespaces, multi-file,
  diagnostics) are not a prerequisite for self-hosting; they are to be implemented in CT, while the C
  side over-reach is **stripped and archived first (Phase 0.3)** and redone in CT in Phases 2–5.
- **Freezing and moving**: **once Phase 0.3's strip is done (i.e. when self-hosting starts)**,
  `ctc.c` freezes as **L0 + the differential oracle** (bug fixes only, no new features); moving it into
  `ctrait/` happens once the self-hosting layout settles — **confirmed by the user on 2026-10-15: do
  not move before the CT-side layout settles**, so `ctc.c` stays at the repository root for now. The
  reason is that this is not a single-file `git mv`: in the draft `ctrait/` = "`ctc.c` + its own
  `test/`", which implies the design task of splitting today's `test/` into L0 unit tests vs
  integration tests; and the L1/L2 `src/` split depends on L2 restoring multi-file. So the move is
  merged with the `src/` + `test/` layout work into **one** `chore` commit rather than done half-way
  (see [design/bootstrap.md](design/bootstrap.md)). New features are written in CT from then on.
- **Cleanup scope (revised 2026-10-14 to "strip first")**: **first** move the namespace / multi-file /
  import / Drop / `#line` / diagnostics implementations that over-reached into C **out of `ctc.c` and
  into the archive as the oracle** (Phase 0.3), so L0 becomes the **pure-OO core** (+ low-level
  facilities); **then** self-host (Phase 1); **finally** Phases 2–5 redo each in CT, diffed against the
  archive. Two hard preconditions: ① **the extracted code is never destroyed** — the archive is both
  the seed (the behavioural baseline that alone can produce L1) and the differential oracle (the only
  reference that can emit a byte-identical golden); ② **`ctc.c` is never deleted outright** — it is
  kept long-term as the seed and the differential oracle (precedents: Rust keeps stage0 long-term,
  Go deprecated stage0 at 1.5 — either is acceptable).
- **The ladder constraint (the source language lags one level)**: a level-n compiler can only compile
  source written in "the syntax subset supported by level n−1". So L1 source must stay **single-file +
  OO subset**; to *use* namespaces / Drop / import when organising the compiler source in CT, a
  CT-level compiler that supports them must already exist. **"Rewrite, then delete the C" is the wrong
  order** — the climb has to be level by level.
- **Single repository**: cross-layer compilation and feature coupling rule out splitting repos; if
  `ctrait/` ever needs standalone distribution, `git subtree` / `git filter-repo` splits it without
  losing history.

The target layout, layering rules, build flow and milestones (M1–M6) live in
[design/bootstrap.md](design/bootstrap.md) (design draft, not implemented).

#### Bootstrap prerequisites (checklist)

For L1 / L2 to write a compiler in CT, the following must exist first (**each one verified by hand on
2026-10-11**; all are current gaps unless noted):

| # | Prerequisite | Why self-hosting needs it | Landing | Status |
| --- | --- | --- | --- | --- |
| 1 | **Multi-file compilation + namespaces** (`.h.ct` / `import` / `pub`) | otherwise all code lands in one file with no module boundary | over-reach → reclaimed in CT | ⚠️ namespaces + multi-file (`ct build`) + `pub` + `import` + `.h.ct` file names + `-I` search roots landed; referencing a trait-carrying object across units not yet. The single-file bootstrap path **does not need** this (see "Minimal self-hostable version" above) |
| 2 | **Language-level heap creation** | the AST and symbol tables must allocate dynamically; today you can only hand-write `q->__<trait>_vptr = &…;` (workable, but forgetting it crashes at run time) | C-side, self-hosting prereq (with Drop) | ✅ `T *p = malloc(...)` (incl. `calloc`) writes the vptrs automatically right after the declaration (nested value fields included, D1=A); `use Drop` + recursive release via `delete` landed |
| 3 | **Object arrays at file scope** | global symbol tables; `Person ps[2];` at file scope `die`s (verified) | C-side, self-hosting prereq ("where objects live") | ✅ Phase 1.6: the vptrs of file-scope objects / arrays are written before `main` by the generated constructor `__ct_init` (`__attribute__((constructor))`, D5=A); the `static`-prefixed form is recognised too (`static Person g;` / `static Person gs[2];`, Phase 1) |
| 4 | **`delete` covering `char *`** | strings / buffers; `delete buf;` on a `char *buf` is passed through verbatim → compile error, so `free()` must be used instead | over-reach → reclaimed in CT | ✅ `delete p;` now works for any pointer (`char *` → `if (p) free(p);`) |
| 5 | **`#line` directives** | errors in the generated C must map back to `.ct` lines, or the self-hosted product cannot be debugged | over-reach → reclaimed in CT | ✅ multi-file mode emits `#line` in the `.c` **by default** (D4=A), off in single-file; gcc/clang errors map back to the `.ct` line |
| 6 | **A method call may have a more general receiver expression** | variable / expression subscripts, pointer-array elements and pointer field chains (`ps[i].m()`, `ptrs[i]->m()`, `b.who->m()`) are supported since Phase 1.9a; rvalue receivers `f().m()` / `mk()->m()` (including the field hop `f().a.b.m()`) since Phase 1.9b | C-side, self-hosting prereq (1.9) | ✅ 1.9a + 1.9b both landed (Q1=A value/pointer returns, Q2=A hoist only at a statement head or an initialiser RHS, Q3=A `die` elsewhere) |
| 7 | Positional initialisers / calls between sibling methods | — | done (0.1.1 / 0.1.4 / 1.9c) | ✅ since **Phase 1.9c** a method body shares the top-level pipeline: local-variable receivers, recursive field chains and parameter receivers all dispatch |

**The shape of the AST**: ct has **no inheritance**, so an AST must use `trait Node { … }` plus one
`struct impl` per node kind and carry them as **interface values** (Phase 0.2) — which makes
self-hosting a stress test for Phase 0.2. Mind the **declaration order**: `struct Binary { Node *lhs; }`
requires `trait Node` to be declared first; two structs referencing each other **by value** fail
(referencing through an interface pointer is unaffected).

Item 6 is one class of problem ("the receiver is neither a registered identifier nor a constant
subscript / value field chain") and can be advanced on its own; items 1–5 overlap heavily with
**the over-reach phase** — **the bootstrap prerequisites are essentially the over-reach phase's output**.

### Phase 0: writing full OO with traits

**Exit criterion (redefined, confirmed by the user on 2026-10-11)**: whether Phase 0 is done is no
longer judged by "structure rewriting works" but by **whether a complete object-oriented program can
be written with traits**. ct's OO semantics are **trait interfaces + composition, without
inheritance**.

"Full OO" in ct means all of the following hold:

| # | Capability | Status |
| --- | --- | --- |
| 1 | **Encapsulation**: `struct` fields + `impl` methods; `self->field` inside a body | ✅ |
| 2 | **Interfaces**: a `trait` declaration + a separate `impl … for` per `struct` | ✅ |
| 3 | **Dispatch**: `.m()` / `->m()` for value and pointer receivers, plus sibling calls `self->m()` inside a body | ✅ (finished in 0.1.4) |
| 4 | **Passing**: objects as **parameters and return values** of functions/methods (struct types in signatures) | ✅ see 0.1.5 |
| 5 | **Composition**: a struct field whose type is another struct; chained calls `a.b.m()` | ✅ see 0.1.6 |
| 6 | **Storage**: method calls on array elements and vptr initialisation for elements | ✅ see 0.1.7 |
| 7 | **Creation & release**: **creation = a stack `struct` declaration** (designated / positional / no initialiser / nested / array, all writing the vptr) ✅; **release = `delete q;`** → `if (q) free(q);` ✅; **heap objects have no language-level creation entry**, deferred to Phase 1 (with Drop; today the vptr must be written by hand) | ✅ see 0.1.8 |
| 8 | **Scoping** (correctness prerequisite): variables/parameters roll back at block scope, no bleeding across functions | ✅ see 0.1.9 |
| 9 | **Interface polymorphism**: variables/parameters typed as a trait, dispatched to different `struct`s at run time | ✅ see Phase 0.2 |

Items 4–8 are **implementation coverage gaps** (they fall under [AGENTS.md](../AGENTS.md) §4, "never
emit C known not to compile", so they are fixed as defects); item 9 is a **language feature** (it needs
a new type representation and syntax), so it **must be designed before it is implemented** and is not a
defect to patch.

The existing acceptance still applies (warning-free build + goldens + the regression suite):

```bash
gcc -Wall -Wextra -std=c99 ctc.c -o ctc                            # zero warnings
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c             # no errors; also emits /tmp/greeter.h
gcc -Wall -Wextra /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
# Hello, I'm Tom, age 36
# Hello Jerry, I'm Tom
```

(During Phase 0 these commands used `example.ct` at the repository root; the examples later moved
into `examples/`, and generated files are no longer committed.)

Explicit non-goals (still out of Phase 0 scope): type checking, optimisation, error recovery,
namespaces, generics, multi-file support, nested definitions, inheritance.

### Phase 0.1 — fixes and regression tests (recommended first)

#### 0.1.1 Fix the pointer-declaration defect — ✅ done

- **Problem**: `Person *p = &a;` used to emit `struct *p = &a;` (the type name was lost), which is
  invalid C.
- **Fix**: the `*p == '*'` branch of `try_var_decl()` restores the type name and now emits
  `struct Person *p = &a;`. Pointer variables were deliberately **not registered** at the time (a
  temporary state); rewriting `p->m()` was completed in 0.1.4.
- **Acceptance**: `Person *p = &a;` emits `struct Person *p = &a;` and compiles; the case is part
  of the 0.1.3 regression set.

#### 0.1.2 Support positional initialisers — ✅ done

- **Problem**: `Person p = { "Tom", 36 };` gets no appended vptr, so calling a method dereferences
  a null pointer at run time.
- **Fix**: drop the "fully designated" restriction (removing `is_designated_list()`); as long as the
  struct has a `use` clause, designated, positional and empty lists alike get
  `.__x_vptr = &…_vtable` appended before `}`. C99/C11 permits the mixed form `{ 1, .v = 0 }`
  (verified with gcc, no warnings).
- **Acceptance**: `test/cases/07_positional_init.ct` runs correctly.

#### 0.1.3 Add regression tests — ✅ done

- **Structure** (landed):

  ```
  test/
  ├── run.sh                 driver: build → unit → golden → negatives; exit 0 = pass
  ├── unit/test_helpers.c    white-box unit tests: includes ctc.c to call the static helpers, 40 assertions
  ├── cases/                 golden positives: <name>.ct + <name>.expected.c / .h / .out
  └── errors/                negatives: <name>.ct + <name>.expected-err (expected diagnostic substring)
  ```

- **Assertions**: ① build layer — `ctc` itself compiles warning-free; ② unit layer — behaviour of
  the pure helpers `trim` / `param_type_only` / `parse_params` / `split_decl` / `decl_end_is_bare` /
  `put_vptr_designators` / `word_at` / `match_delim`, …; ③ golden layer — `ctc` exits 0, the output
  is byte-identical to `.expected.c`/`.expected.h`, the generated C compiles, and cases with a
  `main` match `.expected.out` on stdout; ④ negative layer — must exit non-zero, and the
  diagnostics carry the `file:line:col: error:` prefix and contain the expected text.
- **Coverage (implemented)**: single trait; multiple traits with a wrapped `use` and nested calls;
  trait-less structs and pass-through (`#define` / strings / CJK literals and escapes / line and
  block comments are never rewritten); signature shapes (`void f(void)`, multi-word types, empty
  structs, nested braces); declarations (designated init, `struct`-qualified form, pointer
  declaration); a method-name collision across traits (first in `use` order wins); positional
  initialisers; calls between methods; pointer receivers; declarations without an initialiser. The
  negatives cover undefined trait / undefined struct / undeclared method / unimplemented method /
  struct not using the trait / unbalanced brackets.
- **Not covered yet**: `MAX_*` overflow behaviour (blocked on the capacity decision).
- **Acceptance**: `./test/run.sh` is green (currently 20 checks: 1 build + 1 unit + 10 golden +
  2 examples + 6 negatives). An additional examples layer checks every `examples/**` demo end to
  end (generate → build → run → compare `.expected.out`), so the demos cannot rot silently as the
  compiler evolves. Its own effectiveness was verified by injecting three failures into a scratch
  copy — a corrupted golden, a wrong expected diagnostic, and a bad assertion — all three were
  reported and the run exited 1.

#### 0.1.4 Complete the vptr coverage: pointer receivers / calls between methods / declarations without an initialiser — ✅ done

- **Problems** (one class: silently emitting C that does not compile, or carries a null vptr,
  violating [AGENTS.md](../AGENTS.md) §4):
  1. `self->other()` inside an `impl` body only became `_self->other()`, which is invalid C;
  2. pointer variables were not registered, so `p->m()` was not rewritten — invalid C;
  3. a declaration without an initialiser (`Person p;`) wrote no vptr, so calling a method
     dereferenced an uninitialised pointer.
- **Fixes**:
  1. `Var` gained a `ptr` flag; `try_var_decl()` registers pointer variables; `transform_calls()`
     gained a `->` branch (passing the pointer itself, **without** `&`), and the `.` rule is never
     applied to a pointer variable;
  2. `self->m(...)` inside a body is rewritten in `replace_self()` to
     `_self->__<trait>_vptr->m(_self, …)`; when such a call exists, a vtable forward declaration
     (a C tentative definition) is emitted before the method functions;
  3. a declaration without an initialiser becomes
     `struct Person p = { .__<trait>_vptr = &…_vtable };`.
- **Cases**: `test/cases/08_self_call.ct` / `09_pointer_receiver.ct` / `10_uninit_decl.ct`
  (all with a `main`, so they run).
- **Acceptance**: all four minimal reproductions compile and run correctly; `./test/run.sh` is green.

#### 0.1.5 Struct types in function/method signatures — ✅ done

- **Problem**: bare struct names in an ordinary function's return type or parameter types are not
  qualified with `struct `, silently emitting C that does not compile; parameters are not registered,
  so `.m()` / `->m()` on a parameter is not rewritten. Confirmed failing forms:
  `static Point make(...)`, `Point *pick(...)` (return type fine, parameters wrong),
  `void f(Person p)`, `void f(Person *q)`, `void move(Point *pt, int dx)`, and the prototype
  `void f(Person *q);`. `Point make(...)` (bare return type at line start) only "passes" because
  `try_var_decl()` mistakes it for a line-initial variable declaration and adds `struct ` — an
  **accident, not a design**.
- **Fix**: a new `parse_func_sig()` decides — **before** `try_var_decl()` in `emit_raw_line()` —
  whether a line is a function definition or prototype (handling `static`-style prefixes, multi-word
  return types, pointer returns and prototypes, while `if` / `while` / `else if` never match). It
  inserts `struct ` in place for known struct names in the return type and in the parameter types
  (formatting elsewhere untouched) and, **when a body follows**, registers the parameters in the
  variable table (values `ptr=0`, pointers `ptr=1`). Lines recognised as functions no longer go
  through `try_var_decl()`, which also removes the "function name gets registered as a variable"
  side effect.
- **Limitation**: a signature whose parameter list itself spans multiple lines is not recognised
  (line-by-line processing, like multi-line calls).
- **Cases**: `test/cases/11_value_param.ct` / `12_pointer_param.ct` / `13_signature_types.ct`
  (covering `static` returns, pointer returns, prototypes and multi-word types).

#### 0.1.6 Composition: a struct field whose type is another struct — ✅ done

- **Mechanism note (shared by 0.1.6–0.1.8)**: [construction.md](construction.md) — construction semantics
  (who writes an object's vptr, and when); decisions D1–D5 are in its §6.
  "construction semantics" draft; decisions D1–D5 are now frozen.

- **Problem**: struct bodies are passed through verbatim by design, so field types are not qualified
  (`struct Shop { Person owner; }` fails to compile); a chained call `s.owner.greet()` is not rewritten.
- **Fix** (landed in three parts): **a** a new `parse_fields()` partially parses the struct body,
  adds `struct ` to fields of known struct types and records them in the struct's field table;
  **b** declaring an object recursively writes the nested fields' vptrs (**as post-declaration
  assignments**, so an appended `.owner` designator can never override a `.owner = {…}` the user
  wrote); **c** `transform_calls()` walks the field chain to infer static types, so
  `s.owner.m(...)` → `s.owner.__<trait>_vptr->m(&s.owner, …)`.
- **Limitation**: an object with nested objects **must be declared inside a function** (there is
  nowhere at file scope to put the statements; the compiler `die`s). — **lifted by Phase 1.6**: such
  file-scope objects get their vptrs written before `main` by the `__ct_init` constructor.
- **Case**: `test/cases/15_composition.ct`.

#### 0.1.7 Storage: array elements — ✅ done

- **Problem**: `Person ps[2];` has its declaration qualified but no vptr is initialised for the
  elements, and `ps[0].greet()` is not rewritten (fails to compile).
- **Fix**: `Person ps[<n>];` expands into the declaration plus a scoped loop (`__ct_i`) writing each
  element's vptr (nested fields included); the call side supports
  `ps[<const>].m()` → `ps[0].__<trait>_vptr->m(&ps[0], …)`.
- **Limitation** (D2): uninitialised declarations plus constant subscripts only; anything else `die`s
  when initialisation is required.
- **Case**: `test/cases/16_arrays.ct`.

#### 0.1.8 Release: `delete` — ✅ done (automatic heap **creation** is deferred to Phase 1)

- **Problem**: `Person *q = malloc(...); q->greet();` has the call rewritten but the vptr is never
  set → a run-time segfault.
- **Landed**: `delete q;` → `if (q) free(q);` (`q` must be a registered pointer variable; word-boundary
  plus shape checks mean a plain-C identifier called `delete` is never mistaken for it). The Drop
  version (`d->drop(); free(d);`) stays in Phase 1.
- **Not landed: automatic heap creation.** `new` was tried (D3) and then **removed**: it was not in the
  plan and it never actually closed the `malloc` hole (objects from `malloc` still silently have no
  vptr and crash on the first call). How heap objects are created is deferred to Phase 1 together with
  Drop/delete — `drop()` needs a vptr too, so a decision is unavoidable there.
- **Today**: a heap object needs a hand-written `q->__<trait>_vptr = &…;` (that line is passed through
  verbatim), after which `delete q;` releases it.
- **Case**: `test/cases/17_heap.ct` (hand-written vptr + `delete`).

#### 0.1.9 Variable scoping — ✅ done

- **Problem**: `find_var()` returns the first match and `g_vars` only grows, so same-named variables
  and parameters across functions bleed into each other and emit invalid C.
- **Fix**: `scope_track()` tracks braces in the main scan (skipping strings and comments), pushing
  the current `g_nvars` at every `{` and restoring it at the matching `}`; a function body's opening
  brace (including the "brace on its own line" style) is pushed with the value from **before** its
  parameters were registered, so parameters leave scope with the function. This also fixes the
  pre-existing cross-function bleeding of ordinary locals.
- **Note**: originally scheduled for Phase 1; moved forward because 0.1.5 registers parameters.
- **Case**: `test/cases/14_scope_shadow.ct` (two functions each declaring a local `d` and each taking
  a parameter `x`, of different structs; it fails to compile before the fix).

### Phase 0.2: interface polymorphism (designed first → implemented)

**Mechanism note**: [polymorphism.md](polymorphism.md) — the "interface value = fat pointer
`{ self, vt }`" approach; decisions D1–D7 are frozen (with implementation notes).

**Goal**: declare **variables/parameters typed as a trait** (e.g. `Greeter g`) and dispatch to
different `struct`s at run time — i.e. real "program to an interface".

**Landed (0.2a–0.2d)**:

- a new artifact `struct <Trait>_iface { void *self; struct <Trait>_vtbl *vt; };` (no change to
  existing names or layouts);
- type expansion: a bare trait name in a declaration / parameter / return type becomes
  `struct Greeter_iface …`;
- boxing `(struct Greeter_iface){ (void *)&p, &Person_Greeter_vtable }` for **declarations,
  assignments, arguments and `return`**; argument boxing relies on the **signature table**
  (definition-before-use);
- dispatch: `g.greet()` → `g.vt->greet(g.self)`;
- checks: a struct that does not `use` the trait, boxing across different traits, and expressions
  whose type cannot be inferred all `die` instead of emitting bad C.

**Not done yet**: interface **arrays** (`die` at the declaration); automatic boxing of interface
**fields** at construction (an interface field in a designated initialiser is not boxed). Interface
fields themselves are usable now (landed in Phase 1): a value field `T x` → `struct T_iface x`, a
pointer field `struct T *x` → `struct T_iface *x`; `s.x.m()` dispatches through the field's own vt,
and statement assignment of a value field `s.x = v;` boxes automatically (a pointer field's assignment
is left as written).

**Case**: `test/cases/18_polymorphism.ct` (one `announce(Greeter)` serving `Person` and `Shop`, plus
interface re-assignment and an interface return value).

### Phase 0.3 — strip the over-reach (back to a pure-OO `ctc.c`)

**Theme**: move the features that over-reached into C after Phase 0 out of `ctc.c`, so the mainline
returns to "Phase 0 exits 1–9 only" + the low-level facilities. The extracted code is **archived as the
oracle** (it still builds a reference binary) so Phases 2–5 can diff their CT rewrites against it.

**Strip list (confirmed by the user on 2026-10-14: these four groups only)**:

| Capability | Verdict |
| --- | --- |
| namespaces (1.1), multi-file `ct build` + `.h.ct` + `pub` (1.2), `import` (1.3) | **strip**: not OO; multi-file is also the source of the one hard bootstrap blocker (referencing a trait-carrying object across units) |
| `Drop` (1.4) | **strip**: not OO (Phase 0's `delete q;` → `if (q) free(q);` stays, being exit #7) |
| `#line` (1.5) | **strip**: only matters in multi-file mode, so it leaves with multi-file (prerequisite #5 **retires**) |
| leak warnings + `--diagnostics=json` (1.7) | **strip**: not OO |

**Keep list (looks like over-reach, but is really a Phase 0 exit or a bootstrap must)**:

| Capability | Verdict |
| --- | --- |
| heap creation `T *p = malloc(...)` writing vptrs (1.4) | **keep**: exit #7 "creation", and **prerequisite #2** (the AST / symbol tables need dynamic allocation; stripping it means hand-writing vptrs everywhere — "forget one and it crashes at run time") |
| loosened `delete` covering `char *` (1.4) | **keep**: exit #7 "release" + **prerequisite #4** |
| general receivers (1.9a: variable subscripts / pointer arrays / pointer field chains) | **keep**: covers exits #5/#6 "composition / storage" + **prerequisite #6** |
| method bodies on the same rewrite pipeline (1.9c) | **keep**: a precondition of exits #1/#3 (dispatch inside method bodies) |
| interface **fields** (added under 0.2) | **keep**: part of Phase 0.2 interface polymorphism (exit #9) |
| rvalue receivers `f().m()` (1.9b) | **keep (decided 2026-10-14)**: same origin as 1.9a; stripping it alone leaves the inconsistency "subscripts work, rvalues don't" |
| file-scope objects / arrays + `__ct_init` + `static` (1.6) | **keep (decided 2026-10-14)**: **prerequisite #3** (the global symbol table wants it) |

> **Impact on bootstrap readiness**: nothing on the strip list is on the bootstrap prerequisite list
> (or it retires with multi-file), so stripping **does not** weaken readiness — it removes the one hard
> blocker (cross-unit trait-carrying objects) and the no-longer-needed `#line` (prerequisite #5). The
> survivors #2/#3/#4/#6/#7 are exactly what must stay in the Phase 0 core — which gives an operable
> definition of "pure OO": **the bootstrap prerequisite list ∩ everything that is not over-reach**.

**Knock-on work (must land in the same batch, or verification and docs go stale)**:

- **Archive the oracle**: tag/archive today's `ctc.c` *before* stripping and confirm it builds a
  reference binary — otherwise Phases 2–5 would have nothing to diff against the old goldens.
- **Shrink the tests**: `test/import/` and `test/multifile/` wholesale; `test/cases/19_namespace`,
  `20_namespace_nested`, `22_drop`; `namespace_*` / `ns_*` / `drop_*` / `too_many_warnings` under
  `test/errors/`; the `#line` layer in `run.sh`; and the assertions on removed functions in
  `test/unit/test_helpers.c` — all move to the archive and leave `run.sh` (otherwise the suite goes
  red, violating [AGENTS.md](../AGENTS.md) §6). (Cases for kept items — `test/cases/23_file_scope`,
  `27_static_file_scope` and the `24`–`26` receiver cases — **stay untouched**.)
- **Mark the docs honestly**: the syntax tables in `README.md` and `docs/language-spec.md` must say
  "**moved out of L0, returns in CT during Phases 2–5**" instead of listing them as available;
  `editors/vscode` highlighting **stays as is** (the syntax decisions are still frozen, and
  highlighting is independent of the compiler).

**Exit criteria**: ① `./test/run.sh` is green on the **shrunk** suite; ② `ctc.c` only implements
Phase 0 exits 1–9 (+ facilities) — no code path for namespaces / multi-file / `import` / Drop /
`#line` / `--diagnostics`;
③ the archive builds standalone and reproduces the old goldens.

**Completion record (2026-10-14)**:

- `ctc.c` **3836 → 2897** lines (−939) with six over-reach groups deleted; the goldens of kept items are
  **byte-identical** (the archive is recorded purely as renames — no content changed).
- The over-reach fixtures moved into **[`test/archive/`](../test/archive/)** (`cases/` `errors/`
  `import/` `multifile/`, 17 `.ct` files) and left `run.sh`; they are the diff baseline for Phases 2–5. The
  feature-complete old compiler is kept as the git tag **`overreach-oracle`**.
- The suite went **146 → 110** and is green (42 assertions retired: the multifile / import / `#line` /
  warnings layers plus the related errors and cli checks; 6 added for "removed features must fail").
- **A fail-loud guard was added**: `namespace` / `import` / `pub` appearing as a construct report
  `'xxx' is not supported by this compiler` (exit 1), and `ct build` reports
  `'build' (multi-file) is not supported by this compiler` — otherwise these would be silently passed
  through as C that cannot compile, breaking [AGENTS.md](../AGENTS.md) §4. Negative cases:
  `test/errors/removed_{namespace,import,pub}.ct`.
- Docs synced: `README.md` (CLI table, syntax table, test counts) and `docs/language-spec.md`
  (§1–§10 marked section by section).

### Phase 1 — self-hosting (the first goal)

**Theme (a single goal)**: **rewrite Phase 0's OO-in-C** (the stripped, pure-OO `ctc.c` — i.e. L0) **in
CT** — the goal is exactly L0's goal, and the **only purpose is self-hosting**. How: the OO subset, a
**single file** (L0 has no namespaces / import / multi-file, so L1 cannot be split across files — see
below); the exit is **byte-identical** output with L0. Everything else comes after self-hosting.

> **This phase neither adds language features nor restores the stripped ones.** It only rewrites
> Phase 0 exits 1–9 in CT. Restoring and adding features starts in Phase 2.

**Entry condition**: met once Phase 0.3 is done. On a pure-OO base there is **no remaining hard
blocker** — the cross-unit trait-carrying object named by the readiness report went out with
multi-file; the report's remaining expressiveness gaps (interface arrays `die`, boxing at
construction, the line-rewriting discipline) stay as rules L1's source must follow — see the
[self-hosting readiness report](../reports/selfhost-readiness/selfhost-readiness.html) and
"Known constraints" below.

**L1 exit criterion (the go/no-go gate)**: L1 is compiled end to end by the frozen `ctc` (L0) and runs,
and its output is **byte-identical** to the C version's for the same corpus.

**Kick-off decisions (confirmed by the user on 2026-10-14)**:

1. **Zero reuse**: L1 does **not** `#include ctc.c`; it carries all of its own facilities (`Buf` /
   allocators / `die` / the line-scanning primitives, ~200 lines, written as plain-C passthrough). The
   reason: the stripped `ctc.c` is pure OO + facilities, so including it would reuse the C OO core too
   — that is not self-hosting, and "byte-identical" would become a tautology. The earlier "`#include`
   the facilities only" idea is **dropped** (it contradicts "L1 must rewrite the OO in CT").
2. **Banner stays byte-identical**: L1 emits `Generated by ctc v0.0.1 from <input path>` (license line
   included) verbatim. Otherwise every golden under `test/cases/**` would have to be regenerated, and
   regenerating hides real differences; a version/command-name change is a separate event, done in one
   go once the single-entry `ct` lands.
3. **Source location and slicing**: L1 lives in the single file **`selfhost/ctc.ct`** (new directory,
   approved by the user). The first milestone **M2-a** covers only the subset needed by
   `test/cases/01_trait_basic.ct` (trait / struct / impl / use, method-call rewriting, `.h` output,
   banner), exiting on a **byte-identical** match with `01_trait_basic.expected.c` / `.expected.h`;
   the remaining capabilities are added golden by golden. The goldens are the **incremental oracle**
   rather than a single big-bang rewrite.
4. **One extra exit item**: beyond "byte-identical with L0", Phase 1 is done only when **L1 compiles
   `selfhost/ctc.ct` itself** (L1 is written in the pure OO subset, so this should work once it is
   complete) — the hard evidence of real self-hosting.
5. **L1 must be written in CT OO style** (confirmed by the user on 2026-10-15): L1's **data-model layer**
   (`Trait` / `Struct` / `Var` / `FuncSig` symbol tables) and **pipeline layer** (line scanning, line
   rewriting, emission) must be written in the CT OO shape — `struct` + `use` + `impl` — and must **not**
   fall back to plain-C passthrough; only the **facilities layer** (`Buf` / allocators / `die` / the
   scanning primitives, ~200 lines) stays plain-C per decision 1. The reason: CT is a strict superset of
   C, so a pure-C file is also "legal", but it proves **nothing** about the OO machinery — that is not
   self-hosting (isomorphic to decision 1). The rhythm is **slice by slice**: the data-model layer
   first, then `selfhost/check-m2a.sh`, then the pipeline layer; each slice is judged by byte-identical
   output **not regressing**, not merely by "it runs". Note (measured 2026-10-15): L0's `MAX_FUNCS` (64)
   counts **every plain-C function signature** in L1 (definitions and prototypes alike) while `impl`
   methods do **not** count — that ceiling is a **healthy constraint** that pushes L1 towards CT OO
   style, not an obstacle to work around; `ctc.c` is frozen, so it must **not** be changed to relax it.
   Landing note (2026-10-15): the pipeline layer ended up carried by **two** traits — `PipeOps` (the
   main flow: construct parsers, emitters, entry points, CLI) and `RewriteOps` (the per-line rewriting
   layer) — with `struct Pipe` `use`-ing both; new methods go into whichever half they belong to, so
   neither side drifts towards `MAX_METHOD` (32).
6. **The incremental oracle becomes a standing gate** (confirmed by the user on 2026-10-15):
   `selfhost/check-goldens.sh` reduces "L1 vs every `test/cases/**` golden" to one command — it diffs
   each generated `.c` / `.h` byte for byte and reports `PASS / NEW / PENDING / REGRESSION` with counts.
   The baseline list inside the script is a **ratchet**: only a case already on the list that stops
   matching counts as a regression and fails the gate, while an unimplemented family is reported as
   `PENDING` (with L1's refusal reason) and does not block. Starting point, measured 2026-10-15:
   **13 pass / 0 new / 12 pending / 0 regression (of 25 cases)** — all 12 pending cases are capability
   families L1 deliberately left out with an explicit `die`, not wrong output. The climb goes
   **smallest first**: `13` initialisers → `17` heap → interface values (`21` → `18` → `28`) → arrays
   (`16`) → composition (`15`) → then the interlocked `23/24/25/26/27` (they need both arrays and
   composition). Each slice exits on "byte-identical without regressing, and its newly passing case
   promoted onto the baseline list".
7. **M2 reached, and the L1′ self-hosting loop becomes a standing gate** (measured 2026-10-15): the full
   `test/cases/**` corpus is **byte-identical at 25/25** (25 pass / 0 new / 0 pending / **0 regression**),
   so the M2 exit is met. The stronger claim was measured too — **L1 compiles L1 itself** into L1′, L1′
   builds **warning-free** under `-Wall -Wextra -std=c99`, and re-running it over the **same corpus** is
   still **byte-identical at 25/25** (`.c` / `.h` identical to L0, banner included). Both are pinned into
   `selfhost/check-goldens.sh`: step 4 is L1 vs the goldens, and **step 5** is L1′ = L1's own source
   compiled by L1 → warning-free build → byte-compare against the goldens; any disagreement fails the
   gate. This satisfies the **extra exit item** of decision 4 (L1 compiling itself): the Phase 1 go/no-go
   gate passes. Every new capability is from now on scheduled for Phase 2 onward (redone on the CT side), and
   `ctc.c` still accepts bug fixes only.

**The ladder (M1→M2 in this phase; M3–M6 in Phases 2–5)**: L1 is written purely in the OO subset;
afterwards climb layer by layer per [design/bootstrap.md](design/bootstrap.md), every layer exiting on a
**byte-identical golden**:

| Layer | Implemented in CT / moved into CT | Phase |
| --- | --- | --- |
| L1 (M2) | rewrite the stripped pure-OO `ctc.c` in CT (single file, OO subset) | **Phase 1** |
| L2 (M3) | namespaces | Phase 2 (first half) |
| L3 (M4) | import + Drop | Phase 2 (second half) + Phase 3 |
| L4 (M5) | JSON diagnostics + leak warnings | Phase 4 |
| L5 (M6) | self-hosting closed loop (full alignment with the archived oracle) | Phase 5 |

**The ladder constraint (the source language lags one level)**: a level-n compiler can only compile
source written in "the syntax subset supported by level n−1". So to *use* namespaces / Drop / import
when organising the compiler source in CT, a CT-level compiler that supports them must already exist; **L1
is therefore necessarily a single file** (Phase 0.3 moved multi-file out of L0), and only L2 onwards can
split across files.

> **A name with two meanings (noted 2026-10-16)**: "L2" is used in two senses — ① in the **capability
> ladder**, L2 = "the compiler that supports namespaces" (M3, the sense used in the tables above);
> ② in **this repository's artefacts**, L2 = "the binary L1 builds out of `selfhost/src/**` with
> `build`" (the Phase 2 split's product, and the object the ratchet tests from Phase 3 on). The two
> **do not carry the same capability today**: the artefact L2 already has Drop (Phase 3), whereas the
> ladder's L2/L3 are an abstract description of capability levels. To avoid confusion, "L2" below and
> in the gate scripts always means ②.

**Ordering principle (updated 2026-10-14 to "strip first")**: unlike the earlier plan, the over-reach
features leave `ctc.c` **already in Phase 0.3** — a clean pure-OO L0 keeps the self-hosting target
minimal; the extracted code is **archived as the oracle**, not destroyed, so Phases 2–5 can diff their CT
rewrite against it.

**The long-term goal**: `ctc.c` is **kept long-term** as the pure-OO seed and oracle and never removed
wholesale; from Phase 2 on, every new capability lives in the CT layer and `ctc.c` stops growing.

**The peel-C iron rule (superseded by "strip first", see the ordering principle above)**: the archived
C implementation must not be **destroyed** until the matching CT version passes differential
verification; until then it is both the seed (the only thing that can produce L1) and the differential
oracle (the only thing that can emit a golden). "Strip first" moves the code to the archive instead of
deleting it, so this rule still holds in spirit.

**The long-term shape (confirmed by the user on 2026-10-14)**: `ctc.c` stays **peeled back to its core**
— the Phase 0 trait / struct / impl / use rewriting plus the **low-level facilities** — and is **kept
long-term** as the seed and differential oracle, never deleted outright.

#### The new `ct` and `ctc.c`: the `#include` facility-reuse idea (raised 2026-10-14; landing still open)

> **Open**: after the strip, `ctc.c` = pure OO + facilities, yet L1 must **rewrite the OO in CT** and may
> not reuse the C OO implementation. Reusing "facilities only" therefore needs an extra mechanism
> (splitting facilities from the OO core behind a macro guard; or extracting the facilities into a small
> standalone file — which conflicts with the single-file rule), or L1 simply **carries its own
> facilities with zero reuse** (the purest self-hosting). This section is a direction note until that is
> decided.

The new `ct` is written in CT and compiled by the frozen `ctc.c`; it reuses `ctc.c` by **`#include
ctc.c`** (a unity build, like sqlite's amalgamation), **not** by linking. The boundary:

- **Stays in C (reused)**: the **low-level facilities** — `Buf` / `xmalloc` / `xstrndup` / `die`
  (diagnostics) / the line-scanning primitives / the code-generation primitives.
- **Rewritten in CT (not reused)**: the **OO core** (trait / struct / impl / use rewriting) and **all
  language features**.
- **The include is a shrinkable reuse layer**: as CT coverage grows, the included C part **shrinks**,
  ending with the lowest facilities only.

> Why reuse "facilities only" rather than "facilities + features": an included feature is still
> implemented in C — that is not self-hosting; and it makes differential verification vacuous (L1's
> behaviour simply *is* `ctc.c`'s behaviour, so "byte-identical" is a tautology). Reusing facilities only
> keeps both "avoid duplication" and a meaningful self-hosting + differential check.

**Landing preconditions (do them once, before the "bug fixes only" freeze)**:

- `ctc.c`'s `main` needs an `#ifndef CTC_NO_MAIN` guard — otherwise it collides with the new `ct`'s
  `main` in the same TU. **This is the only structural change before the freeze.**
- CT code must **systematically avoid every `static` identifier in `ctc.c`** (`buf_puts` / `die` /
  `word_at` / `emit_raw_line` …); namespaces do not mangle plain function names, so a same-TU clash is a
  redefinition error.
- `ctc.c`'s `die()` → `exit(1)` and its process-wide `g_*` need an exit for **reuse / reentrancy**
  (multi-file `ct build` needs per-unit compilation and per-unit errors).

**Known constraints (must be accepted before starting)**:

- **Declaring an interface array `die`s** → AST child lists cannot use `Node kids[N]`; they must rely on
  **interface pointers + a linked list**; and assigning to a pointer interface field is **passed
  through verbatim today** (the fat pointer has to be built by hand).
- **Interface fields do not take part in constructor-point recursion, and designated initialisers do
  not box** → more hand-written boxing while assembling the AST.
- **Line-based rewriting** (a construct sharing a line with a statement is not handled; single-line
  function bodies are not handled) → the compiler's own source must follow the "one statement per
  line" discipline, or it is **silently not rewritten and the output will not compile**.
- **Declaration before use + single-pass scanning** → traits / structs must be topologically sorted by
  hand; mutual recursion is only possible through interface pointers.
- **Namespaces mangle only struct / trait / impl symbols, not plain function names** → if the source is
  organised by namespace, plain functions collide at the C level (which is also a motive for taking
  the single-file path first).

**Transition discipline**: **every new C-side language feature is frozen the moment self-hosting
starts**; `ctc.c` accepts bug fixes only. If L1 exposes an expressiveness gap in ct, decide first
whether it is a "language feature" (which goes to the CT layer) or a "seed core capability" (which must
be added on the C side) — the latter must be recorded explicitly as an **amendment to the Phase 0 core
definition**, not patched in passing (this is exactly the relapse point of Phase 0's historical drift).

**Restoring and adding features after self-hosting (shared premise of Phases 2–5)**

Only after self-hosting (Phase 1) is done. Exit criteria are grouped by **Class** (not by sub-phase):
Phases 2–4 are **restoration** (archived oracle + frozen goldens; exit = **byte-identical**, no new
design needed); Phase 5 is **new work** (no oracle to diff against; exit = **design frozen + new cases
+ `run.sh` green**). The implementation-level design is in [design/restore.md](design/restore.md)
(decisions D1–D8, only D6 / D7 open; D8: `map` moves out, see Phase 6).

**Implementation policy — fidelity first (confirmed by the user on 2026-10-16)**: redoing these features
in CT aims at **byte-identical output with the archived oracle**, **including replicating its existing
behaviour and limitations** (for instance the **continuation line** of a multi-line `/* … */` block
comment is treated as ordinary code — see [language-spec](language-spec.md) §6.2). So **neither the
inputs under `test/archive/**` nor the archived goldens are ever edited or regenerated**: fixture and
golden are the frozen oracle; an existing defect is written down in §6.2 instead of being dodged by
changing the corpus. The diff gate is [selfhost/check-archive.sh](../selfhost/check-archive.sh).

**Three hard ordering constraints (not negotiable)**:

1. **Phase 2 must come first** — only once namespaces + multi-file land can the CT compiler source be
   split across files; `import` also follows it (it depends on path / symbol resolution).
2. **Phase 3 precedes Phase 5** — AutoDrop depends on Drop, and path-sensitive analysis on scope + Drop.
3. **Directory = namespace binding depends on Phase 2**, so it can only land in Phase 5.

Alignment with the [bootstrap.md](design/bootstrap.md) ladder: M3 → the first half of Phase 2;
M4 → the second half of Phase 2 + Phase 3; M5 → Phase 4; **M6 (full alignment) closes in Phase 5**.

### Phase 2 — module system (was 2.1)

- **Redone in CT**: namespaces (`parse_namespace` + qualified lookups + prefixed generated names
  `<Ns>_<Struct>_<Trait>_<method>`), multi-file `ct build` / `.h.ct` / `pub` (types sink into `.h`,
  the `.c` includes its own header, visibility rule), `import` (path resolution + recursive inclusion
  + accumulating cross-unit symbols).
- **Exit**: archived cases **byte-identical**; **the compiler source itself becomes multi-file** (the
  single biggest payoff for the rest of the work).
- **Diff against**: `test/archive/cases/19_namespace`, `test/archive/cases/20_namespace_nested`, `test/archive/multifile/`, `test/archive/import/`.
- **Risk**: the name prefix becomes a published contract as soon as it ships, so freeze it first;
  multi-file breaks the self-contained `.c`, so decide it together with the `pub` visibility rule;
  `-I` is decided (**local-first**: the importing file's own directory, then each `-I` root in
  command-line order); cross-unit vtable visibility is still open.
- **Progress (2026-10-16)**: **namespaces are done** — `selfhost/check-archive.sh` reports
  `19_namespace` and `20_namespace_nested` byte-identical (nested namespaces came along for free),
  plus four namespace negatives (`namespace_bad_path` / `namespace_path_too_long` / `ns_path_nested` /
  `ns_qualified_name`, diagnostics verbatim) now pass and are promoted onto the gate's baseline; the
  Phase 1 exit does not regress (`check-goldens.sh` 25/25, L1′ agreeing). The implementation: a flat
  `g_ns` prefix, `read_qual_ref` for a qualified declaration head, the `::` chain rewrite in
  `transform_calls`, and a `namespace` branch in `compile_range` (recurse + save/restore the prefix).
- **Progress (2026-10-16, slice 2d/2e + `.h.ct` / `-I`)**: **multi-file `ct build`, `pub` and `import` are done** — the
  four archived units under `test/archive/{multifile,import}/` (`app` / `calc`, `app` / `shapes`) are
  **NEW** (byte-identical `.c` and `.h` on both sides) and promoted onto `baseline_multi`, so the
  gate now reads 4 pass + 4 pass + 6 pass, 0 regression and exits 0. The CLI grew a `build`
  subcommand (with `compile` accepted as an explicit alias; `-o` means an output **directory** in
  build mode) plus a plain-C driver in `selfhost/ctc.ct` (`collect_imports` / `resolve_import` /
  `unit_visit` / `build_output` / `build_main`): it resolves each `import a::b;` against the importer's
  directory, compiles the units in dependency (post-)order in multi-file mode, and prints the
  suggested `cc` command. In the pipeline, `pub` is stripped from a function line but its prototype is
  routed into the `.h` (leaving a blank line in the `.c`), a `pub trait` / `pub struct` puts only the
  type into the `.h`, an `import` line is consumed, and `#line` mapping (`line_of` / `line_at` /
  `line_break`, three new `PipeOps` methods) lands in the multi-file `.c` so the archived output —
  which carries the directives — matches byte for byte. Cross-unit symbols accumulate (`ntraits` /
  `nstructs` / `nfuncs` reset only in single-file mode). The generated program was also built and run
  end to end (`1 2 5`). **Still to do**: the `--line` / `--no-line` overrides (Phase 4).
  **Also (2026-10-16, `.h.ct` / `-I`)**: **`foo.h.ct` file names and `-I` search roots are done**.
  A `*.h.ct` basename strips the whole `.h.ct` for the output (`foo.h.ct` -> `foo.c` + `foo.h`) and an
  `import foo;` falls back to `foo.h.ct`, so the pair is published under the name a consumer would
  import; a plain `*.ct` keeps producing the `.c`/`.h` pair it always has (its "publishes no header"
  half is deferred to Phase 5 — the frozen archive compares `foo.ct`'s `.h` too). `-I <dir>` is
  repeatable and is searched after the importing file's own directory, in command-line order
  (local-first, the decision D7 recommends). The new semantics are pinned in `test/modules/**` by
  `check-archive.sh` **group 7 (designed)**, which has no archive oracle: each fixture byte-diffs its
  own goldens and, for a positive case, links and runs against an `expected.out` — `hdr` (the `.h.ct`
  name + the import fallback), `inc` (the `-I` root makes the import resolvable), `inc_missing`
  (without the `-I` root the build must fail with `cannot resolve import`), and `precedence` (a
  same-named file in the importing dir beats the `-I` root, pinning "local-first").
- **Progress (2026-10-16, source split → L2)**: **the split landed** — the CT compiler source moved
  from the single-file seed `selfhost/ctc.ct` to the multi-unit tree `selfhost/src/**`
  (`core.ct` + `driver.ct`), built by **L1's own `build`** (multi-file + `import`) into **L2**; the exit
  criterion is **L2 byte-identical with L1 on `test/cases/**` (25/25)** and it holds
  (`check-goldens.sh` step 6). Hard constraints the split surfaced (measured with a T0 probe):
  ① a `pub` prefix **cannot reach the `.h`** — `ctc.ct` writes any `#`-starting line verbatim into the
  `.c` and returns early, bypassing the `pub` routing, so a header unit **cannot carry `MAX_*` /
  `size_t` / `FILE`**; data, macros and the singleton must stay inside `core.ct` (landing in `core.c`)
  and `driver.ct` keeps its own equal-valued `MAX_*` copies. ② an `impl` / vtable is emitted `static`,
  so its **symbol cannot be referenced across units** — cross-unit dispatch goes only through a vptr
  already stored in the object (a `->method()` after an accessor returns `struct Pipe *` /
  `struct SymTab *`). ③ `MAX_FUNCS` counts **top-level plain-C signatures**; this split exported only
  10 `pub` scalar wrappers (`ct_read_file` / `ct_is_ident_char` / `ct_usage` / `ct_default_output` /
  `ct_begin_imports` / `ct_add_import` / `ct_compile_file` / `ct_cc_reset` / `ct_cc_add` /
  `ct_cc_finish`). **Correction (2026-10-16, measured in Phase 3)**: that ceiling **also counts `static`
  top-level signatures**, so the headroom was in fact tiny — Phase 3's new helpers already had to become
  `impl` methods (see the Phase 3 progress). **Same source, neither generated from the other**:
  `selfhost/src/**` and the hand-written seed `selfhost/ctc.ct` (L1) are both hand-written; the seed is
  kept. (**From Phase 3 it becomes "L1 frozen, new capability lands in `src/**` only"** — double-writing
  is unsustainable, see the Phase 3 kick-off decision.) **New gates**: `check-goldens.sh` step 6 (the
  hard criterion: L1 `build selfhost/src/driver.ct` → L2 → corpus byte-identical), `check-archive.sh` 3b,
  `check-m2a.sh` step 7, `ct-tour.sh` step 6. **New designed case** `test/modules/split` (`pub trait` +
  `pub struct` in the header unit, the `impl` (with its static vtable) in another unit, a third unit
  dispatching through the pointer an accessor returns) pins that cross-unit contract and is registered
  in `check-archive.sh` group 7 `baseline_designed`. **Still to do**: Phase 2's `--line` and the Phase 3+
  restoration items; the `--line` / `--no-line` overrides still belong to Phase 4.
- **Close-out (2026-10-16, user-confirmed, option A)**: **Phase 2 ends here** — **no version bump**
  (`CTC_VERSION` stays `v0.0.1`, not touched while frozen), only the **non-version tag
  `phase2-multifile-split`**; the `v0.1.0` / `v0.2.0` bumps land together with the single-entry `ct`,
  regenerating every golden at once. Both exit criteria hold, so the phase leaves no functional item;
  `--line` / `--no-line` belong to Phase 4.

### Phase 3 — memory (was 2.2)

- **Redone in CT**: `Drop` (built-in reserved-name trait, lazy generation, recursive value-field
  release) + loosened `delete` (any pointer → `if (p) free(p);`).
- **Exit**: drop cases **byte-identical**. ✅ met (2026-10-16).
- **Diff against**: `test/archive/cases/22_drop`, `test/archive/errors/drop_*`.
- **Risk**: the merge semantics of a user `impl Drop` and the default body must be nailed down.
- **Kick-off decision (2026-10-16, user-confirmed, option B: L1 frozen)**: this phase **does not touch
  `selfhost/ctc.ct` (L1)** — L1 becomes a **frozen seed** (its capability stops at Phase 2) and new
  capability lands only in `selfhost/src/**`. The reason is that double-writing is unsustainable: read
  Phase 2's "L1 and `src/**` share one source" literally and every Phase 3–7 feature has to be written
  twice. This mirrors the level above — once `ctc.c` froze, development moved to L1; now that L1 has
  frozen, development moves to `src/**`. **The cost is a change of gate meaning**: `check-archive.sh`'s
  ratchet switches from L1 to **L2** (what L1 `build`s `src/**` into), and `check-goldens.sh` gains a
  **step 7 fixpoint** (L2 compiles `src/**` too and its output must be byte-identical with L1's).
- **Progress (2026-10-16, Drop landed)**: **`Drop` and the `delete` split are both implemented in
  `selfhost/src/core.ct`**, `22_drop`'s `.c` / `.h` / run output are all **byte-identical** with the
  archived oracle, and the five drop negatives (`drop_reserved` / `drop_impl_undefined_struct` /
  `drop_impl_not_used` / `drop_impl_no_method` / `drop_impl_no_body`) all pass — `check-archive.sh`'s
  `baseline_cases` grew to 3 and `baseline_errors` to 9. Implementation: `Struct` gains `has_drop` /
  `has_user_drop` / `drop_used` / `drop_bstart` / `drop_blen` / `def_line`; `use Drop` only sets the
  marker (**no vtable entry, no vptr**); `trait Drop` reports the reserved name; `parse_impl`
  special-cases `impl Drop for T` and captures the user body; `delete p` on a Drop type emits
  `if (p) { T_Drop_drop(p); free(p); }`; emission happens in two places — **prototypes before the main
  body, definitions after it** (`compile_file` therefore writes the body into a `tmpfile()` first and
  copies it back, isomorphic to the oracle) — and only for types `delete` actually reaches
  (`mark_drop_closure` takes the transitive closure) so `-Wunused-function` stays quiet. **Measured
  lesson on the signature ceiling**: `MAX_FUNCS` (64) **counts every top-level plain-C signature
  (`static` included)** and `src/**` has almost no headroom left — the two new helpers therefore became
  `impl` methods (`SymTabOps::mark_drop_closure`, `RewriteOps::body_uses_self`), a hard constraint
  rather than a style preference; `PipeOps` now stands at 31/32.
- **Verification (2026-10-16)**: `check-goldens.sh` 25/25 + L1′ 25/25 + L2 25/25 + **fixpoint 2/2 units
  identical**; `check-archive.sh` 0 regressions (single-unit 3 pass, diagnostics 9 pass / 1 pending,
  multi-unit 4 pass, designed 5 pass); `check-m2a.sh` and `ct-tour.sh` exit 0; `./test/run.sh` green at
  115 (114/0 actually run inside the sandbox, with `cli/compile-cannot-write` excised); `ctc.c` and
  `selfhost/ctc.ct` unchanged relative to `audit-1`.

### Phase 4 — diagnostics and traceability (was 2.3)

- **Redone in CT**: `#line` (on by default in multi-file mode, D4 = A), leak warnings +
  `--diagnostics=json` (first-cut scope in 1.7).
- **New (no oracle; needs new cases)**: multiple errors + resync-based recovery (jump to the next line
  start / `}`), semantic checks (reject duplicate trait/struct definitions; warn on signature
  mismatch).
- **Exit**: the diagnostics layers are green; `#line` maps a gcc error back to the `.ct` line.
- **Diff against**: `test/archive/errors/*`, the `#line` layer in `run.sh`.
- **Risk**: error counts plus resync points invite cascading false positives; semantic checks must be
  kept clear of the "no type checking" boundary.
- **Progress (2026-10-16, slice 1: `#line` switch close-out)**: `--line` / `--no-line` landed in
  `selfhost/src/**` — `core.ct` gains a `g_line_force` global (`-1` by mode / `0` force off / `1`
  force on) and `g_emit_line = (g_line_force >= 0) ? g_line_force : multi;`; `ct_compile_file` takes
  a fourth `line_force` argument, parsed and threaded through both `compile_main` and `build_main`,
  and the usage text gains the two lines. Two designed fixtures were added (`test/modules/noline/`:
  `build --no-line` suppresses the multi-file default; `test/modules/line/`: `compile --line` forces
  it on single-file), and `check-archive.sh` group 7 grew a `compile.args` branch (single-file cases
  run their args verbatim from a staging copy so the banner path matches the golden), taking
  `baseline_designed` to 7. **The single-file default stays off**, so L2's single-file output remains
  byte-identical with L0. **Still to do**: semantic checks (4). New code goes
  into `impl` blocks (`MAX_FUNCS` has one slot left).
- **Progress (2026-10-16, slice 2: leak warnings + `--diagnostics`)**: the oracle's conservative,
  path-insensitive leak warnings are restored in `selfhost/src/**` — `Var` gains `owned` /
  `own_line`, a pointer declaration initialised from `malloc` / `calloc` is marked as owned
  (`new_var` clears both fields so a reused slot never inherits stale ownership), `delete` and a
  `return` / escaping assignment clear the mark, a closing scope collects the objects still owned
  via `leak_check_scope`, and `emit_warnings` prints JSON under `--diagnostics=json` (stdout in
  compile mode, stderr in build mode, which keeps stdout for the cc command) or text to stderr.
  The archived negative case `too_many_warnings` flips from PENDING to PASS (overflow past
  `MAX_WARNS` still `die`s). **All five new methods go into `SymTabOps` (9 → 14)** and warning
  output reuses existing pub wrappers (single-file `ct_compile_file`, build `ct_cc_finish`), so
  **no top-level function is added** — `MAX_FUNCS` still has its one slot. Three designed fixtures
  were added (`leak`: compile text; `leak_json`: compile json → stdout; `leak_build`: build json →
  stderr), and `check-archive.sh` group 7 gained `expected.stdout` / `expected.stderr` byte-exact
  assertions. **Still to do**: semantic checks (4).
- **Verification (2026-10-16, slice 2)**: all three goldens were generated by the oracle built from
  tag `overreach-oracle`, and L2 matches it byte for byte across `.c` / `.h` / stderr / stdout
  (including the `unknown diagnostics format` error for `--diagnostics=bad`); `check-archive.sh`
  0 regressions (single-unit 3 pass, diagnostics **10 pass / 0 pending**, multi-unit 4 pass,
  designed **10 pass**); `check-goldens.sh` 25/25 + L1′ 25/25 + L2 25/25 + fixpoint 2/2;
  `check-m2a.sh` / `ct-tour.sh` exit 0; `./test/run.sh` 115/115; the manual three-step passes and
  L2's single-file output matches L0 byte for byte.
- **Progress (2026-10-16, slice 3: multi-error reporting + resync)**: `die` no longer always
  exits — `compile_range`'s per-line loop installs a `setjmp` guard each round, and `die` reports
  and `longjmp`s back to it (without a guard the old one-error-stops behaviour — and OOM — still
  holds). The guard snapshots `sym->nvars` / `g_nscope` / `g_body_abs`, restored in the handler
  because a long jump skips `emit_body`'s own restore, and a recursive namespace body keeps its
  caller's guard by saving and copying back the `jmp_buf`. `RewriteOps::recover_pos` picks the
  resync point: past the next `}` or the start of the next line, whichever comes first (literals
  and comments skipped), always strictly forward. `MAX_ERRORS=20` caps it (`ctc: too many errors,
  stopping`, exit 1). A failing compile deletes the `.c`/`.h` it had written (judged by this call's
  error delta) and closes with `ctc: N error(s) generated`; the exit code is 1. **Still to do**:
  semantic checks (slice 4).
- **Verification (2026-10-16, slice 3)**: a three-error sample reports all three plus the summary,
  exits 1 and leaves no artifact; the `MAX_ERRORS` boundary (stops after the 21st), an error inside
  a nested `namespace`, and one inside a function body all behave as designed, and a later error's
  position is unaffected by an earlier long jump (matching L0's existing positions).
  `check-archive.sh` 0 regressions (designed **12 pass**, adding `multi_err` / `multi_err_build`);
  `check-goldens.sh` 25/25 + L1′ 25/25 + L2 25/25 + fixpoint 2/2; `check-m2a.sh` / `ct-tour.sh`
  exit 0; `./test/run.sh` 115/115; the manual three-step passes.

### Phase 5 — new features (was 2.4)

- **AutoDrop**: a marked variable gets an automatic `drop()` at the end of its scope (no `free` — only
  the held resources are released).
- **Path-sensitive leak analysis**: analyse every return path and flag "not released on some paths".
- **Mandatory directory = namespace binding**.
- **Exit**: **design first → freeze → new cases → `run.sh` green**; **byte-identical is explicitly not
  required** (there is no oracle to diff against). Rung **M6** closes here.

**Needs a user decision first, not scheduled yet**: whether to introduce **type checking** (if so the
compiler changes nature and needs an AST rather than line-based scanning); whether to introduce
**generics** (requires monomorphisation on the `.c` side); whether to guarantee a **hard readability
budget** for the generated output (max nesting indent, name-length caps, …).

### Phase 6 — ecosystem and extension (was Phase 3)

- **Ecosystem binding**: `map` + the reverse mapping table (moved off the self-hosting mainline per D8;
  settled together with the official bindings list when it lands).
- **The dialect system**: domain-specific syntax written inside comments, turned into plain CT by an
  expander script that lives outside the compiler — `ctc` stays unaware of it throughout. The design is
  frozen but unimplemented, and it is **scheduled for this phase** (confirmed by the user on 2026-10-13;
  wording updated with the 2026-10-14 phase realignment and the 2026-10-16 renumbering to Phase 6) — an
  ordering choice, not a technical
  dependency: the expander is an external script and does not couple to self-hosting. Before it lands,
  the three boundary conflicts with [AGENTS.md](../AGENTS.md) §2 must be amended (code-generation
  scripts / the extension invoking the compiler / dialect distribution via the package manager). See
  [design/dialect.md](design/dialect.md) (design draft, not implemented).
- **Build**: incremental compilation cache, cross-function leak analysis, multi-target builds.

### Phase 7 — toolchain shape (single-entry `ct`)

- **What lands**: one `ct` command carries everything, with subcommands — `ct compile` (today's
  compiler) / `ct build` / `ct get` / `ct install`; dispatched on `argv[0]`, with `ctc` kept as a
  symlink or copy for **compatibility** (as busybox does). The design is frozen (see "Decided design
  decisions · toolchain shape"); **this phase is only the landing**.
- **Exit**: `ct compile` works and existing `ctc …` invocations keep working; README and scripts use
  `ct` throughout.
- **Depends on**: `ct build` belongs to Phase 2 (multi-file), so this phase follows it; `ct get` /
  `ct install` depend on the package manager (name still open, see "Open decisions").
- **Risk**: renaming the command touches every `ctc` usage in README, scripts and the rest of the
  documentation — it has to be replaced in one go and re-checked.

The bootstrap target layout, layering rules (L0/L1/L2) and build flow live in
[design/bootstrap.md](design/bootstrap.md).

### Open decisions

Whether fixed capacity limits stay, become hard errors, or turn into dynamic allocation; and what the
package manager should be called. Positional initialisers are decided: they get automatic vptr
designators (0.1.2). Pointer declarations are decided too: they are generated correctly and pointer
variables are registered as pointers so `p->m()` is rewritten (0.1.4). The toolchain shape is decided:
a single-entry `ct` with `ctc` kept as a compatibility alias. And the multi-file shape is decided: a
`.h.ct` file produces a `.h` + `.c` pair whose `.c` includes its own header (see "File-naming
convention and `pub` visibility").

After the 2026-10-14 phase realignment two more are decided: **all new C-side language features are
frozen from self-hosting (Phase 1) on** (`ctc.c` takes bug fixes only), and the **cleanup scope is the
strict version** — `ctc.c` is peeled back to the pure-OO core, the rest of the features are deleted or
archived once their CT versions pass differential verification, and `ctc.c` itself is never deleted
outright (see "Bootstrap strategy and the single-file boundary"). Still open, scheduled for Phase 5:
type checking, generics, and hard readability budgets for the generated output (see "Phase 5").
