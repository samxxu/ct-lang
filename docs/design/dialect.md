# 方言系统设计草案（Dialect System）

> 中文 · [English](#english)
>
> **状态：设计草案存档；方言能力已在 Phase 6.6 以「仓库外展开器」形态落地。** 本文描述的是
> 早期「图纸」，其实现形态后来由 [phase6.md](phase6.md) §7（D20）取代：编译器对 DSL **零感知**，
> 展开器只允许出现在 `examples/` 与 `test/` 的 `ct-dialects/` 下，演示见 `examples/07_dialect/`。
> 今天的编译器是 `selfhost/ast/main.ct`（ct-ast，v0.10.0 起提供安装入口）。
>
> **排期：Phase 6（生态与扩展）**（2026-10-13 用户确认；表述随 2026-10-14 相位重排更新）。这是**排序选择，不是技术依赖**——
> 方言展开器是编译器之外的外部脚本，不需要自举，理论上可与自举并行；排在最后是为了先让编译器主语料稳固。
>
> **技术前置**（详见第 0 节）：trait（Phase 0 出口，现役）与 namespace / import / Drop、`ct build` 单入口 CLI、
> 以及「反向映射表 + 诊断」——后几项**曾越位实现在 C 侧，已随 Phase 0.3 从 `ctc.c` 剥离并归档为 oracle**，
> 将由 CT 在 Phase 2–5 重做（诊断与 `#line` 属 Phase 4）；反向映射表经 D8 移至 Phase 6（2026-10-14）。
>
> **落地前必须修订的规约条目见第 0 节**（曾与 [AGENTS.md](../../AGENTS.md) 现行硬性边界存在三处冲突；**已于 Phase 6.6 修订完毕**）。

---

## 中文

### 0. 落地前置：现行规约冲突与依赖

> 本节是 2026-10-13 复核后新增，用来把「排期靠后」掩盖不了的问题提前记录在案。

#### 0.1 与现行规约的硬冲突（落地前必须先修订规约）

| 冲突点 | 现行规约（[AGENTS.md](../../AGENTS.md)） | 方言系统要求 |
|--------|---------------------|-------------|
| 引入代码生成脚本与构建管线 | §2 硬性边界：不引入任何第三方库、构建系统、代码生成脚本 | 方言展开器 + `ct build` 展开管线 |
| 插件不得调用编译器 | §2：`editors/**` 只做高亮与编辑体验，不调用 `ctc` | §9 插件后台自动 expand 或 `--watch` |
| 包管理分发方言 | 包管理（`ct-pkg`）已在 Phase 8 落地（`ct get` / `ct install`）；方言的全局分发仍属远期 | §4.3 全局方言目录、`ct get dialect-html` |

这三条不会因为「排在后面」就消失，落地那一刻必然要改规约。现在记下来，是为了避免最后阶段先撕规约再开工。

> **状态更新（2026-10-17，切片 6.6）**：三条冲突**已在 Phase 6.6 修订**——[AGENTS.md](../../AGENTS.md) §2 新增方言豁免
> （展开器留在**仓库外**、`ctc` **零感知**、**永不**调用展开器、**永不**内置方言；仓库内**只允许**在 `examples/**`
> 与 `test/**` 下携带演示 / 测试用方言插件，约定目录 `ct-dialects/`、文件名 `<名字>.sh`（`/` 换 `-`），且**不得**
> 成为编译器构建步骤），并同步把 §6 的「七层覆盖」改为「八层」（新增 `dialect` 层）。**插件仍不调用编译器**
> （`--watch` / 后台自动展开推迟），**包管理分发方言不在本阶段**。落地记录见 [phase6.md](phase6.md) §7。

#### 0.2 技术依赖

- **已在路线图上**：trait（Phase 0，现役）与 namespace / import / Drop、`ct build` 单入口 CLI
  —— 后四项曾越位实现在 C 侧，**已随 Phase 0.3 剥离归档**，将由 CT 在 Phase 2–5 重做；
  以及**反向映射表 + 诊断**（见 [roadmap](../roadmap.md) 的「已定的设计决策」；诊断 / `#line` 属 Phase 4，
  反向映射表经 D8 移至 Phase 6）。
  后者正是本文 §7.2 sourcemap 与 §8 引用预检的底座，**应复用而非另起一套**。
- **不在自举前置里**：包管理（§4.3 的跨项目分发依赖它）。
- **与自举无关**：展开器是外部可执行文件（bash / Python / awk 均可），不由编译器实现。

#### 0.3 排期：Phase 6（生态与扩展）

**2026-10-13 用户确认（表述随 2026-10-14 相位重排更新）。** 这是**排序选择，不是技术依赖**——方言展开器是编译器之外的外部脚本，
不需要自举，理论上可与自举并行；排在最后是为了先让编译器主语料稳固。

### 1. 定位与核心原则

#### 1.1 什么是方言

方言（Dialect）是**写在注释里的领域专用语法**，由编译器之外的展开器脚本转换成纯 CT 代码，插回原文件供 `ctc` 编译。

```
.ct 源码（含方言注释）
    ↓  方言展开器（用户写的脚本）
纯 .ct 源码
    ↓  ctc
C 代码
```

#### 1.2 三条不可动摇的原则

| 原则 | 说明 |
|------|------|
| **编译器零感知** | `ctc` 看到的输入永远是纯 CT。方言对编译器不存在 |
| **方言基于 CT 语法** | 方言展开的产物是 **CT 代码**，不是 C 代码。生成物反编译回纯 CT，不是方言 |
| **机制对用户完全开放** | 官方预制方言与用户自定义方言走**完全相同**的机制，不开后门、不内置进编译器 |

#### 1.3 为什么不做成编译器特性

- 不引入宏系统 / 模板系统，避免语言核心复杂度失控
- 用户用自己熟悉的脚本语言即可编写，门槛极低
- 每个项目可以有**自己的**模板规则，定制权完全归用户

### 2. 注释协议

#### 2.1 基本形态

```
//@ct-dialect: register/map
//@  0x00 CTRL   | rw | bit7=EN, bit[6:4]=MODE
//@  0x04 STATUS | ro | bit0=RDY
//@gen-begin hash=9f2a DO-NOT-EDIT
struct CTRL { ... }
impl Register for CTRL { ... }
//@gen-end  — 读上方注释即可，本区块由工具生成，请勿手改
```

- `//@ct-dialect: <名字>` —— 声明本块归属哪个方言（路由键）
- `//@  ...` —— DSL 正文（人读、人写）
- `//@gen-begin` / `//@gen-end` —— 生成区分隔行，**告诉阅读者：这段不用读，读注释就行**

#### 2.2 关键性质

所有标记**都是注释**。若不跑展开器直接调 `ctc`：
- 注释被忽略 —— 不会报错
- 生成区不存在 —— 符号缺失而失败

因此**使用方言的项目必须走 `ct build` / 展开器**，不可裸调 `ctc`。

#### 2.3 必须原地插入

方言注释位于哪个 `namespace { }` 内，展开出的 trait / struct 就属于哪个 namespace。

**展开结果必须插入注释下方原处，不可输出到独立文件**，否则作用域丢失。

### 3. 两种落地模式（团队自选）

| | 入库内容 | 优点 | 风险 |
|---|---------|------|------|
| **Lazy（建议默认）** | 仅提交方言注释 | 仓库干净；不可能手改生成代码；无陈旧风险 | 开发时看不到展开结果，需 `ct expand` 物化 |
| **Eager** | 注释 + 生成 CT 一并提交 | 不跑工具也能阅读、编译 | 文件变长；可能被手改；需 hash 检测陈旧 |

推荐：**lazy 入库，`ct expand --in-place` 临时物化供人阅读/评审，`ct build` 时在内存或临时文件中拼接后喂给 `ctc`。**

### 4. 多方言并存与路由

#### 4.1 一个方言文件管一个领域

```
ct-dialects/
├── html.sh          # //@ct-dialect: html/tag
├── statemachine.sh  # //@ct-dialect: fsm/state
├── command.sh       # //@ct-dialect: cmd/dispatch
└── register.sh      # 项目自有：//@ct-dialect: register/map
```

同一 `.ct` 文件可混用多个方言，各块按 `//@ct-dialect:` 名字路由，**互不干扰**。

#### 4.2 命名规则

两段式 `领域/类型`（`html/tag`、`fsm/state`、`cmd/dispatch`），避免团队间撞名。官方与用户共用同一规则。

#### 4.3 注册与发现

- 项目级：展开器扫描 `ct-dialects/` 目录，每个脚本通过 `--meta` 自报家门，建路由表
- 跨项目：将来通过包管理安装到全局方言目录（`ct get dialect-html`）

#### 4.4 执行顺序

默认按文件内出现顺序依次处理。存在依赖时在脚本头部 `depends` 声明。

#### 4.5 作者指南（Phase 12.3 已落地的口径）

可运行的范例是 `examples/07_dialect/`：同一个 `registry.ct` 里混用 `register/map` 与 `fsm/state`
两个方言，分别由 `ct-dialects/register-map.sh` 与 `ct-dialects/fsm-state.sh` 展开。

**调用方式（已实现）**

```
sh ct-dialects/<方言名，/换成->.sh <input.ct> > <expanded.ct>
```

插件从**参数**读入文件、把展开后的纯 CT 写到 **stdout**；不读 stdin、不写文件、不调用编译器。
（§5.1 里的 stdin/stdout 契约尚未启用——当前驱动与演示一律走「参数 + stdout」。）

**归属规则（多方言并存的唯一硬约定）**

- 插件**只处理自己的** `//@ct-dialect: <自己的名字>` 块；
- 其余一切（包括别的方言块、普通代码、注释）必须**原样透传**，一个字节都不改；
- 于是驱动可以按「文件内首次出现的顺序」把各插件**依次**套在同一个文件上：
  前一个插件展开自己的块，后一个插件再展开它的块，互不干扰。

`test/run.sh` 的 `dialect` 层与 `selfhost/check-ast.sh` 的语料段都按这条规则路由，不再只取
第一个方言标记。

**生成区与源注释**

- `//@ ...` 的 DSL 行是**唯一事实来源**，必须保留；
- 展开结果插在块下方，包在 `//@gen-begin … //@gen-end` 之间（由插件打印，供人阅读时跳过）；
- 展开产物不入库（lazy 模式，见 §3）。

**作者检查清单**

- [ ] 文件名 = 方言名把 `/` 换成 `-`，放在项目的 `ct-dialects/` 下
- [ ] 参数不足时打印 `usage:` 到 stderr 并以非零退出
- [ ] 只认自己的 `//@ct-dialect:` 标记；别的块逐字节透传
- [ ] 生成区有 `//@gen-begin` / `//@gen-end`，且不覆盖 `//@` 源行
- [ ] 插件零依赖（POSIX sh + awk 足够；也可用 Python 等）
- [ ] 不调用 `ctc`、不修改输入文件、不联网
- [ ] 一条命令可复现：`sh ct-dialects/<名字>.sh <in.ct> > <out.ct>`

### 5. 脚本接口契约

#### 5.1 语言不限

契约是「可执行文件 + stdin/stdout + 环境变量」，因此 **bash / Python / awk 均可**。文档统一以 bash 为推荐默认，但接口说明须写明"任何可执行文件"。

#### 5.2 头部声明（固定四段）

```bash
#!/usr/bin/env bash
#@dialect: register/map
#@version: 1.0
#@desc: 从寄存器地址表生成 struct + 读写 trait impl
#
#@usage:
#@  //@ct-dialect: register/map
#@  //@  0x00 CTRL | rw | bit7=EN, bit[6:4]=MODE
#
#@sample: |
#@  //@ct-dialect: register/map
#@  //@  0x00 CTRL | rw | bit7=EN
#@  //@gen-begin
#@  //@gen-end
#
#@see: examples/register_demo.ct
```

| 段落 | 作用 |
|------|------|
| `desc` | 一句话判断用不用得上 |
| `usage` | 写的时候对照参数语法 |
| `sample` | **可直接复制的最小可跑样板** |
| `see` | 指向仓库真实示例文件 |

**样板必须保持最小**，只演示核心一两个参数。完整选项放 `usage` 与 `see`。

#### 5.3 三个调用约定

| 调用 | 作用 |
|------|------|
| `./xx.sh --meta` | 输出头部元数据，供 `ct` 扫描注册 |
| `./xx.sh --check` | 自检依赖，exit 0 表示可用 |
| `cat 块 \| ./xx.sh` | 展开：stdin 收 DSL，stdout 吐纯 CT |

#### 5.4 输入 / 输出

- **stdin**：方言块内容，展开器已剥离 `//@` 前缀，给干净文本
- **stdout**：**只吐 CT 代码**
- `//@gen-begin` / `//@gen-end` 分隔符**由展开器统一添加**，脚本不管

> 这条保证所有方言生成区风格一致，且脚本好写。

#### 5.5 上下文（环境变量）

| 变量 | 含义 |
|------|------|
| `CT_FILE` | 当前源文件路径（报错用） |
| `CT_LINE` | 方言注释起始行（回溯用） |
| `CT_NS` | 当前 namespace（生成符号带前缀） |

#### 5.6 错误处理

- 失败 exit 非 0
- stderr 写 `文件:行: error: 描述`
- 展开器接管后转为 ctc 统一风格，**行号用 `CT_LINE` 回溯到方言注释，而非生成区**

#### 5.7 最小骨架（`ct dialect new` 生成）

```bash
#!/usr/bin/env bash
set -euo pipefail
#@dialect: my/thing
#@version: 0.1
#@desc: TODO
#@sample: |

[[ "${1:-}" == "--meta" ]] && { sed -n 's/^#@ *//p' "$0"; exit 0; }
[[ "${1:-}" == "--check" ]] && exit 0

# TODO: 读 stdin → 输出 CT
```

### 6. 执行隔离（fork + execve）

#### 6.1 做法

编译器 `fork` 后 `execve`，**直接构造白名单 `envp` 传给子进程**，父进程环境从头到尾不被修改：

```c
char *envp[] = {
    "CT_FILE=src/drv.ct",
    "CT_LINE=42",
    "CT_NS=Driver::Sensor",
    "PATH=/usr/bin:/bin",
    NULL
};

pid_t pid = fork();
if (pid == 0) {
    dup2(in_fd,  0);
    dup2(out_fd, 1);
    dup2(err_fd, 2);
    execve("./ct-dialects/register.sh", argv, envp);
    _exit(127);
}
```

**不要调 `setenv`** —— 直接构造干净 `envp` 传入。

#### 6.2 核心价值：构建可复现

比"不污染主环境"更重要的是：

> 白名单环境 ⇒ 同一份输入 + 同一脚本 = 永远产出同样 CT

否则开发者 A 机器上是 gawk、B 机器上是 mawk，同一脚本产出不同结果，bug 极难排查；生成代码入库时，两人跑一遍 diff 全是无关差异。

#### 6.3 附带收益

| 收益 | 说明 |
|------|------|
| 崩溃隔离 | 脚本段错误、死循环不拖垮编译器 |
| 可并行 | 各块环境独立，具备并发展开潜力 |
| 安全边界 | 脚本无法修改编译器状态，只能经 stdout 返回结果 |

#### 6.4 四个实现细节

1. **加超时**：`waitpid` 配超时，或 exec 前套 `timeout 10`（脚本死循环会卡死编译）
2. **固定工作目录**：子进程 `chdir` 到项目根，否则相对路径随调用位置漂移
3. **`PATH` 显式给**：清空环境后 `#!/usr/bin/env bash` 可能找不到 bash；或改用 `#!/bin/bash`
4. **捕获 stderr**：转为 `src/drv.ct:42: error: register/map: ...` 统一格式

#### 6.5 安全边界（暂不实现）

`fork+execve` 天然是沙箱入口，将来分发第三方方言时可加只读文件系统、禁网络等限制。**当前不要提前做。**

### 7. 工程配套（必须处理）

#### 7.1 防陈旧与禁止手改

`//@gen-begin` 带方言块哈希。下次展开先比对：
- 一致 → 跳过
- 不一致 → 整块覆盖，并警告"生成区被手改，已重新生成"

分隔行内明确标注 `DO-NOT-EDIT`。

#### 7.2 报错回溯

生成区出错时 ctc 报的是生成后行号，人没写过那行。缓解：

- 展开器输出 sourcemap（生成行 → 方言注释行），`ct build` 翻译回原文件行
- 简单版：生成代码带 `//@src-line: N` 尾注

> 底座已定，无需另起：roadmap 已定的**反向映射表 + JSON 诊断**（JSON 诊断已随 Phase 1.7 落地；反向映射表排期 Phase 6，D8 2026-10-14）就是
> 「生成符号 ← 哪个 CT 声明」的映射载体，sourcemap 在此之上加一层「生成行 → 方言注释行」即可。
> 仍未定的只是本层的**输出格式**（见 §15 第 6 项）。

#### 7.3 IDE 高亮

DSL 在注释里，默认无高亮。给 VS Code 加 snippet 或轻量正则高亮 `//@` 行，成本极低。

#### 7.4 方言版本锁定

脚本升级后产出可能变化，导致老项目生成区突发 diff。

建议 DSL 带版本：`//@ct-dialect: fsm/1.2`，展开器校验匹配，不匹配**报错**而非静默产出不同结果。

### 8. 关键缺口：DSL 引用手写代码

> 这是方言能否真正实用的分水岭，必须在实现前想清楚。

#### 8.1 问题

```
//@ct-dialect: fsm
//@  State: Running  on_enter: motor_start    ← 引用用户手写函数
```

`motor_start` 在别处手写。展开时**展开器并不知道该函数是否存在**：
- 等 ctc 编译才报错
- 报错还指向生成区，用户须自行回溯到 DSL

#### 8.2 解决方向

- DSL 里加"引用声明"，让展开器预检 —— **仍开放，是本节真正待解的语法问题**
- 或靠 sourcemap 精准回溯到 DSL 那一行 —— 底座已定（见 §7.2），复用反向映射表 / JSON 诊断即可，
  不再是开放项，只是落地细节

**没有这个能力，方言只能生成"完全自包含"的代码，实用性打对折。**

### 9. lazy 模式下的 IDE 盲区

只提交注释、不提交生成代码 → VS Code 插件看不到展开结果，跳转定义、自动补全全部失效。

解决（二选一）：
- 插件后台自动跑 expand
- 提供 `ct expand --watch` 生成影子文件供插件读取

**不解决此问题，lazy 模式开发体验会很差。**

> 注意：这两种做法都与 [AGENTS.md](../../AGENTS.md) §2「插件不调用编译器」的现行边界冲突，
> 落地前须先修订规约（见 §0.1）。

### 10. 配套命令

| 命令 | 作用 |
|------|------|
| `ct dialect list` | 列出已注册方言及描述 |
| `ct dialect new NAME` | 生成带头部模板的骨架脚本 |
| `ct dialect sample NAME` | 样板 + 展开结果并排展示 |
| `ct expand FILE` | 展开并输出纯 CT |
| `ct expand --in-place FILE` | 物化生成区到文件（临时查看/评审） |
| `ct expand --watch` | 生成影子文件供 IDE 读取 |

`ct dialect sample NAME --open` 可直接在编辑器打开含样板与结果的临时文件，边看边改。

### 11. 预制方言（官方提供）

#### 11.1 定位：教学样例 + 回归测试

预制方言同时承担三个角色：
1. 开箱即用的能力
2. **用户编写自己方言时的抄写对象**
3. 方言机制的回归测试

#### 11.2 必须用公开机制实现

官方方言**不得**内置进编译器、不得开后门。否则用户看了也学不会，还会觉得"官方能做的我做不到"。

#### 11.3 少而精

一旦官方提供二十几个，用户会默认"这些才是标准用法"，反而不敢写自己的。建议 **3-4 个**。

#### 11.4 优先级建议

| 顺序 | 方言 | 理由 |
|------|------|------|
| 1 | **状态机** | 结构最简单，一眼看懂，收益立竿见影 |
| 2 | **命令 / 消息表** | 嵌入式最常用，纯数据驱动，无递归 |
| 3 | **寄存器映射表** | 同构单元极多，收益大 |
| 4 | **HTML 标签类** | 展示"OO + 树结构 + 递归"综合能力 |

> HTML 标签虽是极佳的 OO 示例（每个标签有属性+行为，几十个高度同构），但因涉及树结构、递归渲染、递归 Drop、属性类型各异，复杂度偏高，**宜作进阶样例而非第一个**。

#### 11.5 真正的主战场

HTML 标签背后是更普适的模式：**"一堆同构的东西，每个只差名字和参数"**。

嵌入式里比 HTML 标签更常见、数量更大：
- 寄存器映射表
- 命令分发表
- 消息 / 事件定义表
- 协议字段表

> **边界待划清**：其中的寄存器映射表、命令分发表与 roadmap 已定的 **`map` 语法**
> （trait 方法 → 具体实例 SDK 调用）职责有重叠。落地前需明确「谁负责什么」，
> 否则同一件事会被规划两遍。见 §15 第 8 项。

### 12. 学习成本与文档策略

#### 12.1 对定义者

方言是自己写的，自己最熟悉，几乎零学习成本。所需仅一份**接口文档**（本文档第 5 节）。

#### 12.2 对新成员

脚本头部即文档，新人学习闭环三步：

```
1. 看 ct-dialects/register.sh 头部 10 行
2. 复制 sample 段到自己的 .ct
3. ct expand → 看生成结果
```

对照参数与产物看一遍即懂，且看到的是**本项目真实用到的东西**。

#### 12.3 文档可执行化

头部 `sample` 段提取出来跑展开，作为回归测试 —— **文档即测试**（类似 rustdoc / Go example test），防止样板失效。

#### 12.4 头部转 snippet

`sample` 段可自动转成 VS Code snippet，输入 `regmap` 即补全整块注释模板。头部文档与编辑器补全共用一份源，不会不同步。

### 13. 收益预期（诚实校准）

| 口径 | 影响 |
|------|------|
| 单个模板化模块 | 作者写代码压缩 **80-90%** |
| 整个工程（摊薄后） | 额外压缩 **5-15%** |
| 生成的 CT / 最终 C | **不减少** |

真正收益是：**人写的代码少、评审时只看几行注释、认知负担大幅下降**。

不是机器产出变少。

### 14. 实现时机

- 方言系统依赖 trait（Phase 0，现役）与 namespace / import / Drop、`ct build` 单入口 CLI —— 后四项**曾越位落地，已随 Phase 0.3 剥离归档**，将由 CT 在 Phase 2–5 重做
- 但方言本身排在**最后**：**排期 = Phase 6（生态与扩展）**（2026-10-13 用户确认）
- 这是**排序选择，不是技术依赖** —— 展开器是编译器之外的外部脚本，不与自举耦合；
  靠后安排是为了先稳固编译器主语料
- 落地前须先处理第 0 节列出的三处**规约冲突**与依赖清单
- 本文档已存档为 `docs/design/dialect.md`；**最终实现形态**见 [phase6.md](phase6.md) §7（D20，仓库外展开器，Phase 6.6 已落地）

### 15. 待办与开放问题

| # | 事项 | 状态 |
|---|------|------|
| 1 | DSL 引用手写函数的预检机制（§8.1） | **开放，实现前必须解决**（sourcemap 部分底座已定，见 §7.2） |
| 2 | lazy 模式下 IDE 支持方案（§9） | 开放（插件后台 expand 或 `--watch`）——**与现行插件边界冲突，须先改规约** |
| 3 | 方言版本锁定语法 | 建议 `fsm/1.2`，待定 |
| 4 | 接口文档独立成页 | 待写 |
| 5 | 官方预制方言清单最终确认 | 建议 3-4 个 |
| 6 | sourcemap 格式 | 底座（反向映射表）已定，**本层输出格式待定** |
| 7 | 包管理分发方言 | 远期（包管理已在 Phase 8 落地；方言的全局分发目录尚未落地） |
| 8 | 与已定 `map` 语法的职责边界（§11.5） | 开放，落地前须划清 |
| 9 | 修订 AGENTS.md §2 硬性边界（§0.1） | 落地前必须处理 |

---

> **文档版本：** v0.1（设计定型）
> **排期：** Phase 6（生态与扩展；排序选择，非技术依赖）
> **下次更新触发：** 自举启动（Phase 1）/ 开放问题 1、2 有结论 / 第 0 节的规约冲突被修订

---

## English

### 0. Prerequisites: conflicts with today's rules, and dependencies

> Added on 2026-10-13, to put on record the problems that "scheduled late" cannot make go away.

#### 0.1 Hard conflicts with today's rules (the rules must be amended before this lands)

| Conflict | Today's rule ([AGENTS.md](../../AGENTS.md)) | What the dialect system needs |
| -------- | ------------------------------------------- | ----------------------------- |
| Code-generation scripts and a build pipeline | §2 hard boundary: no third-party libraries, build systems or code-generation scripts | dialect expanders + the `ct build` expansion pipeline |
| The extension must not invoke the compiler | §2: `editors/**` covers highlighting and editing comfort only and does not call `ctc` | §9 the extension running expand in the background, or `--watch` |
| Dialect distribution via the package manager | the package manager (`ct-pkg`) landed in Phase 8 (`ct get` / `ct install`); dialect distribution through it is still long term | §4.3 a global dialect directory, `ct get dialect-html` |

None of these disappears by being scheduled last — each one has to be amended the moment it lands.
Recording them now avoids having to tear up the rules at the very end before any work can start.

#### 0.2 Technical dependencies

- **Already on the roadmap**: trait (a Phase 0 export, in service) plus namespace / import / Drop and the
  single-entry `ct` CLI — those four over-reached into C and were **stripped out of `ctc.c` and archived
  as the oracle in Phase 0.3**, to be redone in CT during Phases 2–5 — and the **reverse mapping table +
  diagnostics** (see "Decided design decisions" in the [roadmap](../roadmap.md); diagnostics / `#line`
  belong to Phase 4, the reverse mapping table moved to Phase 6 per D8, 2026-10-14). The latter is exactly
  the substrate for the sourcemap in §7.2 and the reference pre-check in §8, so it **should be reused, not
  rebuilt**.
- **Not a self-hosting prerequisite**: the package manager (which §4.3's cross-project distribution
  depends on).
- **Independent of self-hosting**: the expander is an external executable (bash / Python / awk are all
  fine) and is not implemented by the compiler.

#### 0.3 Schedule: Phase 6 (ecosystem and extension)

**Confirmed by the user on 2026-10-13** (wording updated with the 2026-10-14 phase realignment). This is
an **ordering choice, not a technical dependency** — the expander is an external script outside the
compiler, needs no self-hosting, and could in principle run in parallel with self-hosting; it is last so
that the compiler's main body settles first.

### 1. Positioning and core principles

#### 1.1 What a dialect is

A dialect is **domain-specific syntax written inside comments**, converted into plain CT by an expander
script that lives outside the compiler and spliced back into the file for `ctc` to compile.

```
.ct source (with dialect comments)
    ↓  dialect expander (a script the user writes)
plain .ct source
    ↓  ctc
C code
```

#### 1.2 Three unshakeable principles

| Principle | Meaning |
| --------- | ------- |
| **The compiler is unaware** | What `ctc` sees is always plain CT. To the compiler, dialects do not exist |
| **Dialects are based on CT syntax** | A dialect expands into **CT code**, not C. Decompiling the output yields plain CT, not the dialect |
| **The mechanism is fully open to users** | Official dialects and user-written dialects go through **exactly** the same mechanism — no back doors, nothing built into the compiler |

#### 1.3 Why this is not a compiler feature

- No macro system or template system is introduced, so the language core cannot spiral in complexity
- Users can write expanders in whatever scripting language they already know — a very low bar
- Every project can have **its own** template rules; the customisation power belongs entirely to users

### 2. The comment protocol

#### 2.1 Basic shape

```
//@ct-dialect: register/map
//@  0x00 CTRL   | rw | bit7=EN, bit[6:4]=MODE
//@  0x04 STATUS | ro | bit0=RDY
//@gen-begin hash=9f2a DO-NOT-EDIT
struct CTRL { ... }
impl Register for CTRL { ... }
//@gen-end  — just read the comments above; this block is tool-generated, do not hand-edit
```

- `//@ct-dialect: <name>` — declares which dialect the block belongs to (the routing key)
- `//@  ...` — the DSL body (read and written by humans)
- `//@gen-begin` / `//@gen-end` — generated-region markers, **telling the reader: do not read this,
  read the comments**

#### 2.2 The key property

Every marker **is a comment**. If the expander is skipped and `ctc` is called directly:
- the comments are ignored — no error
- the generated region does not exist — the symbols are missing and compilation fails

So **a project that uses dialects must go through `ct build` / the expander** and must never call `ctc`
directly.

#### 2.3 Expansion must be in place

The dialect comment sits inside some `namespace { }`; the traits and structs it expands into belong to
that same namespace.

**The expansion must be inserted in place, right below the comment — never written to a separate
file**, or the scope is lost.

### 3. Two adoption modes (each team picks)

| | What is committed | Pros | Risks |
| --- | ----------------- | ---- | ----- |
| **Lazy (recommended default)** | only the dialect comments | clean repository; hand-editing generated code is impossible; no staleness | the expansion is invisible while developing, so `ct expand` is needed to materialise it |
| **Eager** | comments + the generated CT | readable and compilable without running the tool | longer files; can be hand-edited; staleness needs hash detection |

Recommended: **commit lazily, use `ct expand --in-place` to materialise the expansion temporarily for
reading or review, and have `ct build` splice it in memory or in a temporary file before handing it to
`ctc`.**

### 4. Coexisting dialects and routing

#### 4.1 One dialect file covers one domain

```
ct-dialects/
├── html.sh          # //@ct-dialect: html/tag
├── statemachine.sh  # //@ct-dialect: fsm/state
├── command.sh       # //@ct-dialect: cmd/dispatch
└── register.sh      # project-specific: //@ct-dialect: register/map
```

One `.ct` file may mix several dialects; each block is routed by its `//@ct-dialect:` name and they
**never interfere**.

#### 4.2 Naming

Two segments, `domain/kind` (`html/tag`, `fsm/state`, `cmd/dispatch`), so teams do not collide.
Official and user dialects follow the same rule.

#### 4.3 Registration and discovery

- Project level: the expander scans `ct-dialects/`, each script announces itself via `--meta`, and a
  routing table is built
- Cross-project: later, dialects get installed into a global dialect directory by the package manager
  (`ct get dialect-html`)

#### 4.4 Execution order

By default, blocks are processed in file order. When there is a dependency, declare it with `depends`
in the script header.

#### 4.5 Authoring guide (the shape Phase 12.3 landed)

The runnable example is `examples/07_dialect/`: one `registry.ct` mixes `register/map` and
`fsm/state`, expanded by `ct-dialects/register-map.sh` and `ct-dialects/fsm-state.sh`.

**Invocation (implemented)**

```
sh ct-dialects/<dialect name, / becomes ->.sh <input.ct> > <expanded.ct>
```

A plugin reads the file from its **argument** and writes expanded plain CT to **stdout**; it does not
read stdin, write files or invoke the compiler. (The stdin/stdout contract in §5.1 is not in use yet —
today's drivers and demo always take the argument + stdout shape.)

**The ownership rule (the one hard convention for coexisting dialects)**

- a plugin handles **only its own** `//@ct-dialect: <its name>` block;
- everything else — other dialects' blocks, ordinary code, comments — must be **passed through byte
  for byte**;
- the driver can therefore apply the plugins **in sequence** in first-appearance order: each expands
  its own block and leaves the others untouched.

The `dialect` layer of `test/run.sh` and the corpus section of `selfhost/check-ast.sh` route exactly
this way instead of taking only the first marker.

**Generated regions and source comments**

- the `//@ ...` DSL lines are the **single source of truth** and stay;
- the expansion is spliced below the block inside `//@gen-begin … //@gen-end` (printed by the plugin,
  so a human reader can skip it);
- generated files are never committed (lazy mode, see §3).

**Author checklist**

- [ ] file name = the dialect name with `/` replaced by `-`, under the project's `ct-dialects/`
- [ ] on bad arguments, print `usage:` to stderr and exit non-zero
- [ ] recognise only your own `//@ct-dialect:` marker; pass foreign blocks through byte for byte
- [ ] wrap output in `//@gen-begin` / `//@gen-end` and never overwrite the `//@` source lines
- [ ] stay dependency-free (POSIX sh + awk is enough; Python &c. are fine too)
- [ ] never invoke `ctc`, never modify the input file, never touch the network
- [ ] reproducible with one command: `sh ct-dialects/<name>.sh <in.ct> > <out.ct>`

### 5. The script interface contract

#### 5.1 Any language

The contract is "an executable + stdin/stdout + environment variables", so **bash / Python / awk are
all acceptable**. This document recommends bash by default, but the interface description must say
"any executable".

#### 5.2 Header declaration (four fixed parts)

```bash
#!/usr/bin/env bash
#@dialect: register/map
#@version: 1.0
#@desc: generate a struct plus read/write trait impls from a register address table
#
#@usage:
#@  //@ct-dialect: register/map
#@  //@  0x00 CTRL | rw | bit7=EN, bit[6:4]=MODE
#
#@sample: |
#@  //@ct-dialect: register/map
#@  //@  0x00 CTRL | rw | bit7=EN
#@  //@gen-begin
#@  //@gen-end
#
#@see: examples/register_demo.ct
```

| Part | Purpose |
| ---- | ------- |
| `desc` | one sentence for deciding whether it is useful |
| `usage` | the parameter syntax, to consult while writing |
| `sample` | **a minimum runnable sample that can be copied directly** |
| `see` | points at a real example file in the repository |

**The sample must stay minimal**, demonstrating only one or two core parameters. The full set of
options lives in `usage` and `see`.

#### 5.3 Three calling conventions

| Invocation | Purpose |
| ---------- | ------- |
| `./xx.sh --meta` | print the header metadata so `ct` can scan and register it |
| `./xx.sh --check` | self-check dependencies; exit 0 means usable |
| `cat block \| ./xx.sh` | expand: stdin receives the DSL, stdout emits plain CT |

#### 5.4 Input / output

- **stdin**: the dialect block contents, with the `//@` prefix already stripped by the expander —
  clean text
- **stdout**: **CT code only**
- the `//@gen-begin` / `//@gen-end` markers are **added uniformly by the expander**; scripts never
  handle them

> This keeps every dialect's generated region in the same style and makes scripts easy to write.

#### 5.5 Context (environment variables)

| Variable | Meaning |
| -------- | ------- |
| `CT_FILE` | path of the current source file (for error messages) |
| `CT_LINE` | starting line of the dialect comment (for back-tracing) |
| `CT_NS` | the current namespace (so generated symbols can be prefixed) |

#### 5.6 Error handling

- failures exit non-zero
- stderr carries `file:line: error: description`
- the expander converts this into ctc's uniform style, and **the line number is back-traced to the
  dialect comment via `CT_LINE`, not to the generated region**

#### 5.7 Minimum skeleton (generated by `ct dialect new`)

```bash
#!/usr/bin/env bash
set -euo pipefail
#@dialect: my/thing
#@version: 0.1
#@desc: TODO
#@sample: |

[[ "${1:-}" == "--meta" ]] && { sed -n 's/^#@ *//p' "$0"; exit 0; }
[[ "${1:-}" == "--check" ]] && exit 0

# TODO: read stdin → emit CT
```

### 6. Execution isolation (fork + execve)

#### 6.1 The approach

The compiler `fork`s and `execve`s, **building a whitelist `envp` and passing it straight to the
child**; the parent environment is never modified from start to finish:

```c
char *envp[] = {
    "CT_FILE=src/drv.ct",
    "CT_LINE=42",
    "CT_NS=Driver::Sensor",
    "PATH=/usr/bin:/bin",
    NULL
};

pid_t pid = fork();
if (pid == 0) {
    dup2(in_fd,  0);
    dup2(out_fd, 1);
    dup2(err_fd, 2);
    execve("./ct-dialects/register.sh", argv, envp);
    _exit(127);
}
```

**Do not call `setenv`** — build a clean `envp` and pass it in.

#### 6.2 The core value: reproducible builds

More important than "not polluting the main environment" is this:

> a whitelisted environment ⇒ the same input plus the same script always produces the same CT

Otherwise, developer A has gawk and developer B has mawk, the same script produces different results,
and bugs become extremely hard to chase; when generated code is committed, every diff between two
people's runs is full of irrelevant noise.

#### 6.3 Side benefits

| Benefit | Meaning |
| ------- | ------- |
| Crash isolation | a segfault or infinite loop in a script cannot take the compiler down |
| Parallelisable | each block has its own environment, so expansion could be parallelised |
| Security boundary | a script cannot touch compiler state; it can only return results through stdout |

#### 6.4 Four implementation details

1. **Add a timeout**: `waitpid` with a timeout, or wrap the exec in `timeout 10` (a looping script
   otherwise hangs the whole build)
2. **Fix the working directory**: `chdir` the child to the project root, or relative paths drift with
   the invocation directory
3. **Give `PATH` explicitly**: with a cleared environment, `#!/usr/bin/env bash` may not find bash;
   alternatively use `#!/bin/bash`
4. **Capture stderr**: convert it into the uniform `src/drv.ct:42: error: register/map: ...` form

#### 6.5 Security boundary (not implemented yet)

`fork+execve` is naturally a sandbox entry point; read-only filesystems, network bans and the like can
be added later when third-party dialects are distributed. **Do not build this now.**

### 7. Engineering support (must be handled)

#### 7.1 Staleness detection and the ban on hand-editing

`//@gen-begin` carries a hash of the dialect block. On the next expansion it is compared first:
- identical → skip
- different → overwrite the whole block and warn "the generated region was hand-edited and has been
  regenerated"

The marker line explicitly says `DO-NOT-EDIT`.

#### 7.2 Error back-tracing

When the generated region fails, ctc reports a generated line number that nobody ever wrote. Mitigations:

- the expander emits a sourcemap (generated line → dialect comment line) and `ct build` translates the
  line back to the original file
- simple version: the generated code carries a `//@src-line: N` trailing note

> The substrate is already decided, so nothing needs inventing: the roadmap's **reverse mapping table
> + JSON diagnostics** (JSON diagnostics landed with Phase 1.7; the reverse mapping table lands in
> Phase 6 per D8, 2026-10-14) is precisely the "generated symbol ← which CT declaration"
> mapping, and a sourcemap only adds one more layer on top of it — "generated line → dialect comment
> line". What remains undecided is merely this layer's **output format** (see §15 item 6).

#### 7.3 IDE highlighting

The DSL lives in comments, so there is no highlighting by default. Adding VS Code snippets or a light
regex rule to highlight `//@` lines is very cheap.

#### 7.4 Dialect version pinning

A script upgrade can change its output, making generated regions in old projects suddenly show diffs.

Suggested: put a version in the DSL — `//@ct-dialect: fsm/1.2` — and have the expander verify it,
**erroring out** rather than silently producing a different result on a mismatch.

### 8. The critical gap: a DSL referring to hand-written code

> This is the watershed for whether dialects are genuinely usable, and it must be thought through
> before implementation.

#### 8.1 The problem

```
//@ct-dialect: fsm
//@  State: Running  on_enter: motor_start    ← refers to a user-written function
```

`motor_start` is written by hand elsewhere. At expansion time **the expander has no idea whether that
function exists**:
- the error only surfaces when ctc compiles
- and it points into the generated region, so the user must trace back to the DSL by themselves

#### 8.2 Directions

- add a "reference declaration" to the DSL so the expander can pre-check — **still open; this is the
  real unsolved syntax question in this section**
- or use the sourcemap to trace back precisely to that DSL line — the substrate is already decided
  (see §7.2): reuse the reverse mapping table / JSON diagnostics; this is no longer an open question,
  only an implementation detail

**Without this capability, dialects can only generate fully self-contained code, which halves their
usefulness.**

### 9. The IDE blind spot in lazy mode

Committing only comments and not the generated code means the VS Code extension cannot see the
expansion, so go-to-definition and completion all break.

Two options:
- the extension runs expand in the background
- `ct expand --watch` produces shadow files for the extension to read

**Without solving this, the lazy-mode developer experience is poor.**

> Note: both approaches conflict with the current boundary in [AGENTS.md](../../AGENTS.md) §2,
> "the extension does not invoke the compiler", so the rule must be amended first (see §0.1).

### 10. Companion commands

| Command | Purpose |
| ------- | ------- |
| `ct dialect list` | list the registered dialects with their descriptions |
| `ct dialect new NAME` | generate a skeleton script with the header template |
| `ct dialect sample NAME` | show the sample and its expansion side by side |
| `ct expand FILE` | expand and print plain CT |
| `ct expand --in-place FILE` | materialise the generated region into the file (temporary viewing / review) |
| `ct expand --watch` | produce shadow files for the IDE to read |

`ct dialect sample NAME --open` opens a temporary file containing the sample and its result directly in
the editor, so you can edit while watching.

### 11. Prebuilt dialects (shipped officially)

#### 11.1 Role: teaching samples plus regression tests

A prebuilt dialect plays three roles at once:
1. a capability that works out of the box
2. **something for users to copy when writing their own dialects**
3. a regression test for the dialect mechanism

#### 11.2 They must use the public mechanism

Official dialects **must not** be built into the compiler or use a back door. Otherwise users read them
and still cannot learn, and conclude "what the official team can do, I cannot".

#### 11.3 Few and excellent

Once the official set grows past twenty, users assume "these are the standard way" and stop daring to
write their own. **3–4** is the recommendation.

#### 11.4 Suggested priority

| Order | Dialect | Rationale |
| ----- | ------- | --------- |
| 1 | **State machine** | the simplest structure, obvious at a glance, immediate payoff |
| 2 | **Command / message table** | the most common embedded case, purely data-driven, no recursion |
| 3 | **Register map table** | a great many isomorphic units, high payoff |
| 4 | **HTML-tag-like** | demonstrates the combination of OO + tree structure + recursion |

> HTML tags make an excellent OO example (each tag has attributes and behaviour, dozens are highly
> isomorphic), but with tree structure, recursive rendering, recursive Drop and heterogeneous attribute
> types, the complexity is high, so it **belongs as an advanced sample, not the first one**.

#### 11.5 The real main battlefield

Behind HTML tags lies a more universal pattern: **"a pile of isomorphic things, each differing only in
name and parameters"**.

In embedded work these are more common and more numerous than HTML tags:
- register map tables
- command dispatch tables
- message / event definition tables
- protocol field tables

> **Boundary to be drawn**: among these, the register map table and the command dispatch table overlap
> with the **`map` syntax** already decided on the roadmap (trait method → SDK call on a concrete
> instance). Before landing, it must be made explicit "who does what", or the same job gets planned
> twice. See §15 item 8.

### 12. Learning cost and documentation strategy

#### 12.1 For the definer

The dialect is your own, so you know it best — learning cost is essentially zero. All you need is one
**interface document** (section 5 of this document).

#### 12.2 For a newcomer

The script header is the documentation, and the learning loop is three steps:

```
1. read the first 10 lines of ct-dialects/register.sh
2. copy the sample section into your own .ct
3. ct expand → look at the result
```

Comparing the parameters with the output once is enough, and what you see is **what this project
actually uses**.

#### 12.3 Executable documentation

The header's `sample` section is extracted and expanded as a regression test — **documentation as
tests** (much like rustdoc / Go example tests), so samples cannot rot.

#### 12.4 Header to snippet

The `sample` section can be converted automatically into a VS Code snippet: typing `regmap` inserts the
whole comment template. Header documentation and editor completion share one source and never drift
apart.

### 13. Expected payoff (honestly calibrated)

| Measure | Effect |
| ------- | ------ |
| A single templated module | the author writes **80–90%** less code |
| The whole project (amortised) | an additional **5–15%** reduction |
| Generated CT / final C | **does not shrink** |

The real payoff is: **less code written by hand, reviews that read a few comment lines, and a much
lower cognitive load.**

It is not that the machine produces less.

### 14. When to implement

- The dialect system depends on trait (a Phase 0 export, in service) plus namespace / import / Drop and the
  single-entry `ct` CLI — those four **over-reached, were stripped in Phase 0.3 and are to be redone in CT
  during Phases 2–5**
- Yet dialects themselves come **last**: **scheduled for Phase 6** (confirmed by the
  user on 2026-10-13)
- This is an **ordering choice, not a technical dependency** — the expander is an external script
  outside the compiler and does not couple to self-hosting; it is late so that the compiler's main body
  settles first
- Before landing, the three **rule conflicts** and the dependency list in section 0 must be dealt with
- This document is archived as `docs/design/dialect.md`; the **landed shape** is in
  [phase6.md](phase6.md) §7 (D20 — the expander stays outside the repo, landed in Phase 6.6)

### 15. TODOs and open questions

| # | Item | Status |
| - | ---- | ------ |
| 1 | Pre-checking mechanism for DSL references to hand-written functions (§8.1) | **open; must be solved before implementation** (the sourcemap part's substrate is decided, see §7.2) |
| 2 | IDE support in lazy mode (§9) | open (background expand in the extension, or `--watch`) — **conflicts with the current extension boundary; the rule must change first** |
| 3 | Dialect version-pinning syntax | suggested `fsm/1.2`, undecided |
| 4 | An independent page for the interface document | to be written |
| 5 | Final list of official prebuilt dialects | 3–4 recommended |
| 6 | Sourcemap format | substrate (reverse mapping table) decided, **this layer's output format undecided** |
| 7 | Dialect distribution via the package manager | long term (the package manager landed in Phase 8; a global dialect directory has not) |
| 8 | Boundary with the decided `map` syntax (§11.5) | open; to be drawn before landing |
| 9 | Amend the AGENTS.md §2 hard boundary (§0.1) | must be handled before landing |

---

> **Document version:** v0.1 (design frozen)
> **Schedule:** Phase 6 (ecosystem and extension) — an ordering
> choice, not a technical dependency
> **Next update triggered by:** self-hosting starting (Phase 1) / open questions 1 and 2 resolved / the
> rule conflicts in section 0 amended
