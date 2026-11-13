# battle/p39-2-C 判决 — C 方案（`cc -r` 密封归档）

| 字段 | 值 |
| --- | --- |
| battle | p39-2-c（第 3 轮单方案评审） |
| 裁判 | EDITOR（不表态、不投票） |
| HEAD | `ac040d1` |
| 日期 | 2026-11-13 |
| 结论 | **`verdict: rejected`（C 不成立）** |
| 出口 | §7.10 出口 2：open-question |
| ADR | `docs/decisions/D-002.md` |

> 本判决只裁 C 是否可按 §7.10 出口 1 采纳；不裁导出集合（B39-1/D39-2）、`--lib` 命名与确定性（D39-3/D39-4）。

## 0 结论摘要

C 的实测优点成立，但不足以采纳：

- **成立的部分**：两次 `cc -r` 字节确定（VC1）；注入 `visibility("default")` 后 `nm -g` 恰为导出（VC1/VC5）；`__ct_init` 与手写 constructor 不被丢弃（VC1/VC4）；逐单元 `.o` 保留（VC5）；macOS 消费者链接运行（VC1/VC5）。
- **阻断项（按严重度）**：
  1. **J-3 语义被改变**：单成员密封使未使用单元的 constructor 在消费者里运行（counter-review.md:63-75，`CTOR-RAN`；逐成员归档不运行）。C 的 §8.3 只验「不丢」，未验「不多」（`C-proposal.md:149`）。
  2. **J-1 当前形态不成立**：HEAD 未实现 D39-5 的 `visibility("default")`；C §3.1 只写 `-fvisibility=hidden`，且 §4.1 声明不改 Emitter。VC2 证明直接执行会把导出一起本地化（`nm -g` 空，消费者 `Undefined _lib_api`）。VC1 的成立靠 `sed` 模拟该属性，不是 C 的提交形态。
  3. **J-2 严格读不成立**：Linux 只有 `skip`（VC6：podman 不可用）；C 自定 Linux 未测前只发 `--no-seal`（`C-proposal.md:81`），而 `--no-seal` 非洁净，J-1 无平台限定语（counter-review.md:20-23,93）。
  4. **J-4 与 B 同口径不成立**：C 实现 2 文件 + 夹具/门禁 2 文件 = 4 文件，且改 O1/§3.2/R5/D39-5/O3/E39-2（`C-proposal.md:159-166`、`claim-review.md:13,98`、`counter-review.md:96`）。
  5. **`cc -r` 恒有 `ld: warning:`**（VC3）；C 未定 `-nostdlib`（`claim-review.md:60-81` 给出可行解），与零警告基线冲突。

**结论**：C 不成立；按 §7.10 出口 2 登记 open-question，默认规则取 **A（带明确的非 ABI 契约）**，见 §3。

## 1 判据 × 证据矩阵

| 判据 | C | 主要证据（V-id） | 评审行号 |
| --- | --- | --- | --- |
| J-1 ABI 洁净 | **不成立**（当前形态；补 D39-5 后可重审） | VC1、VC2、VC6；counter E1-r3-a | `claim-review.md:10,24,95`；`counter-review.md:9-23,43-61,93` |
| J-2 平台可移植（同一套命令） | **不成立**（严格读） | VC2、VC6 | `claim-review.md:11,20-24,96`；`counter-review.md:25-37,94` |
| J-3 静态链接语义不变 | **不成立** | VC1、VC4、VC5；counter E1-r3-b | `claim-review.md:12,26-29,97`；`counter-review.md:63-75,95` |
| J-4 成本（≤2 文件、≤120 行） | **不成立**（与 B 同口径） | `C-proposal.md:159-166` | `claim-review.md:13,98`；`counter-review.md:96` |
| J-5 可复现 | **成立（macOS；Linux skip）** | VC1、VC3、VC5、VC6 | `claim-review.md:14,99`；`counter-review.md:97` |

### J-1 ABI 洁净

- **不成立（按 C 的提交形态）**。VC1 的 `nm -g --defined-only` 只剩 `_run_lib`，但该探针先用 `sed` 给导出注入了 `visibility("default")`，再以 `-fvisibility=hidden` 编译；C 的 §3.1 只写 `-fvisibility=hidden`，§4.1 又明说「不修改 Emitter」（`C-proposal.md:48,87`），没有把 D39-5 的注入列为前置。
- VC2 是直接反证：HEAD 原样生成的 C + `-fvisibility=hidden` → `cc -r` 仍 `rc=0`，但 `nm -g` 为空、`_run_lib` 变 `non-external`；counter-review.md:54-59 的 E1-r3-a 进一步给出消费者链接 `Undefined _lib_api`。**`ld` 退出码不能当成功判据**。
- Linux：C 自定未测前只发 `--no-seal`（`C-proposal.md:81`），归档仍含 vtable/`Str_*`；J-1 没有平台限定语，不能只在 macOS 成立（counter-review.md:20-23,93）。
- 若 C 修订版把「D39-5 注入 + 先实现再密封」写进 §3/§8，并在 Linux 实测后重跑 VC1/VC2，本项可重审；当前不成立。

### J-2 平台可移植（同一套命令）

- **不成立（严格读）**。工具名确实只有 `cc`/`ar`/`nm`，但两平台机制不同：macOS 是**名字白名单**（`-exported_symbols_list`），Linux 是**可见性本地化**（`--localize-hidden`/`--retain-symbols-file`）；Linux 还要求导出定义已带 `visibility("default")`（VC2 的缺口），并依赖 `_` 前缀差异（counter-review.md:31-37）。
- 「只差一个 `-Wl` 参数」低估了两个前置：`_` 前缀与 default 可见性；这不是同一个参数的两种拼法。
- Linux 只有 `skip`（VC6：`podman version`/`info` 均 rc=1，`docker`/`colima`/`lima` MISSING）。claim-review 的「条件成立」（:11,24,96）不足以在 §7.9 判成立；本席与 verdict.md 对 B 的严格读保持一致。

### J-3 静态链接语义不变

- **不成立**。VC1/VC4 只证明 constructor **不被丢弃**；counter-review 的 E1-r3-b（:63-75）证明相反方向：消费者只调用 `lib_api`，单成员密封归档却把无关 `ctor.o` 的 constructor 链入并打印 `CTOR-RAN`，逐成员归档不打印。
- J-3 是「语义不变」，既要不丢、也要不多；C §8.3 只列「constructor 保留」（`C-proposal.md:149`），claim-review 也只按「成立」（:12,28,97）。这是本庭对 C 的**决定性反证**，不是证据缺口。
- 若 C 改成「按依赖分组的多个密封成员」或用户明确批准「未使用单元 constructor 也运行」的语义变更并改 J-3/E39，可重审；当前不成立。

### J-4 成本

- **不成立（与 B 同口径）**。C 自估：实现 2 文件 60–90 行 + 夹具/门禁 2 文件 40–60 行 = **4 文件**，且改 O1/§3.2/R5/D39-5/O3/E39-2（`C-proposal.md:159-166`）。
- verdict.md 判 B 的 J-4 不成立用的正是「改冻结卡交付物形态 + 夹具重写」这一范围口径；C 同样改 O1/§3.2/R5，不能对 B 用宽口径、对 C 用窄口径。claim-review 已要求统一口径（:13,98）；本席统一为：**J-4 计入卡面与夹具 → C 不成立**。若只计实现行数，C 在 120 行内，但这不是本庭对 B 用过的口径。

### J-5 可复现

- **成立（macOS）**。VC1：两次 `cc -r`（间隔 2s）的 `sealed.o` 与 `libg.a` sha256 相同、`cmp` 逐字节相同；VC5：逐单元 `.o` 在密封后仍存在且可 `nm`；VC6：Linux 明确 `skip`，未默绿。
- 残余：VC3 每次 `cc -r` 的 stderr 有一条 `ld: warning: ignoring unexpected dylib .../libSystem.B.tbd`；C 未定 `-nostdlib`（claim-review 的 E1-C2，:60-81，已证 `-nostdlib` 可消除且消费者仍运行）。若 p39 门禁把 stderr 计入失败，C 的默认形态会在 G3 红——这是重开条件，不是 J-5 的默绿。

## 2 §7.9 推导

| §7.9 行 | 适用 | 结果 |
| --- | --- | --- |
| 主张满足全部判据、反证失效条件均被排除 | C 不满足 J-1/J-2/J-3/J-4 | 不适用 `upheld` |
| 判据未被满足，或反证至少一条失效条件被证实 | J-3 有 E1-r3-b 正证；J-1 有 VC2 反证；J-2/J-4 不成立 | **`rejected`** |
| 证据不足以判定任一方向 | 仅 Linux 半边、D39-5 后形态 | 不足以救 C |

**C 的 `verdict` = `rejected`。** J-5 成立、VC1/VC4/VC5 的正面证据都真实，但 J-3 的 constructor 多链与 J-1 的 D39-5 前置缺口是**已证伪/已证不满足**，不是「等 Linux」的未决项。C 被否后按 §7.10 出口 2 处理，不再开第 4 轮。

## 3 §7.10 出口 2：open-question

| 字段 | 内容 |
| --- | --- |
| **owner** | REQ |
| **截止条件** | PH-39 的 R5（逐单元 `.o` + `ar` 归档 + 符号面）开工前；或 **2026-12-01**，取先到者。逾期未决即按下方默认规则执行。 |
| **默认裁决规则** | **默认 A（带明确的非 ABI 契约）**，直到重开条件满足：① `--lib` 归档 = 逐单元 `.o`（A 形态），不跑 `cc -r`；② `<base>.abi.h` banner 与文档明写「`nm -g` 面 ⊋ 导出面；只有 `.abi.h` 里的声明是 ABI；trait vtable 与 `Str_*` 非 ABI」；③ E39-2 改为「**导出集合断言 + 内部符号清单**」：`.abi.h` 原型集合 == 导出名集合，`expected.nm`（或 `<base>.nm`）列内部符号，`nm -g` 必须等于「导出 ∪ 清单」，任一漂移红；④ `<BASE>_ABI_VERSION` 绑定导出集合（可选：内部清单哈希），让 std `pub` 增长不再静默；⑤ Linux 走 A 路径，`--no-seal` 不作为发布形态。 |
| **重开条件（任一满足即重审 C）** | 1. Linux 密封实测：podman/容器可用，GNU ld 的 `-r --localize-hidden` 或 `--retain-symbols-file` 至少一条通过，且导出不丢（VC6 解除）。2. D39-5 的 `visibility("default")` 注入在 Emitter 实现并复跑 VC1/VC2（VC2 不再把导出本地化）。3. constructor 语义：证明单成员密封不会把未使用单元的 constructor 拉进消费者，或用户明确批准该语义变更并同步改 J-3/E39。4. `cc -r` 的 `ld: warning:` 被 `-nostdlib` 或等价方案消除，且 p39 门禁断言 stderr 为空。5. C 修订版补齐 §8 前置（default 可见性、constructor 不多链）、J-4 口径统一、O1/§3.2/R5 卡面改动获用户批准。 |
| **禁止** | 在 open-question 关闭前按 C 实施，或把 `--no-seal` 当作 J-1 的成立依据；也不得把本 open-question 解释为 B 成立（§7.9 `rejected` ≠ B 成立）。 |

## 4 生效范围

- 只约束 PH-39 的归档内部符号处理：O1、§3.2、§3.3、D39-5、O3 边界、E39-2、E39-5 与 p39 夹具。
- 不改导出集合（B39-1/D39-2）、不改 `--lib` 命名与确定性（D39-3/D39-4）、不改主规范；本判决不授权修改源码或 PH-39 卡。
- 默认规则的 E39-2 改动与卡面更新须用户批准（6.2/6.6 T-6）。
- 范围外引用本判决无效；`battle/p39-2/verdict.md` 的 A/B 判决仍有效，但 C 部分以本文件为准。

## 5 证据索引

| 证据 | 一句话 | 本庭用途 |
| --- | --- | --- |
| VC1 | 注入 `visibility("default")` 后两次 `cc -r` 字节相同，`nm -g` 恰为 `_run_lib`，`__ct_init` 保留，消费者 `hi A`/`hi B` | C 的正面机制 |
| VC2 | HEAD 无 attribute 时 `-fvisibility=hidden` + 密封 → `nm -g` 空、`_run_lib` 本地化、消费者 `Undefined _lib_api` | J-1 当前不成立 |
| VC3 | 每次 `cc -r` 的 stderr 有 `ld: warning: ignoring unexpected dylib ...` | 零警告风险 |
| VC4 | 手写 constructor 经密封后运行 `A-init`/`B-init` | constructor 不丢 |
| VC5 | 逐单元 `.o` 保留、归档 1 成员、`nm -g` 恰为导出、消费者 `woof 7` | 逐单元保留与 ABI 面 |
| VC6 | Linux 工具全 skip（podman 不可用） | J-2/J-1 Linux 不成立 |
| counter E1-r3-b | 单成员密封使未使用 `ctor.o` 运行（`CTOR-RAN`），逐成员归档不运行 | **J-3 决定性反证**（`counter-review.md:63-75`） |
