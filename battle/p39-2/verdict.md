# battle/p39-2 判决 — 静态归档的内部符号

| 字段 | 值 |
| --- | --- |
| battle | p39-2 |
| 裁判 | EDITOR（不表态、不投票） |
| HEAD | `ac040d1` |
| 日期 | 2026-11-13 |
| 结论（§7.9） | `verdict: rejected`（对主张 A） |
| 出口（§7.10） | 出口 1：`battle/p39-2/C-proposal.md` |
| ADR | `docs/decisions/D-002.md` |

> 本判决只回答「PH-39 的静态归档内部符号怎么处理」。不裁导出集合（B39-1）、不裁 `--lib` 命名与确定性（D39-3/D39-4），也不授权修改源码、PH-39 卡或主规范。

## 0 结论摘要

1. **J-1 的读法采字面**：`question.md:18` 的通过方式写的是「`nm -g --defined-only` 是否只剩导出函数」，不是「ABI 面是否被文档定义」。按 `counter-r2.md:109`（N-3），改读法等于改判据；按 `claim.md:64` 的请求，本席在此明写：**采字面读**。
2. **A 不成立（`rejected`）**：J-1 字面不满足（V1/V3/V4/V5；`claim.md:269`、`claim.md:352`、`claim-r2.md:9` 自认）；反证清单的 F-1 被 V3 证实，F-5 被 V10 证实，F-3 的符号面一半被 V15 证实（「只改夹具即绿」因无 `--lib` 未复现，见 §3）。
3. **A 被否不等于 B 成立**（§7.9 末条）。B 在 J-1/J-3/J-5 上成立，但在 **J-2（严格「同一套命令」）** 与 **J-4（成本/与 O1 冲突）** 上不成立（`counter-r2.md:99`、`claim-r2.md:48-49`、V6/V7/V8、V10）。
4. B 也不满足全部判据，故按 §7.10 **出口 1** 产出 `C-proposal.md`：工具集收敛为 `cc` + `ar` + `nm`，保留逐单元 `.o` 为构建产物，用 `cc -r` 合并并本地化，`ar` 只归档单个密封对象，`nm` 断言只剩导出。C 须再走一次单方案评审（主张=ARCH、反对=REVIEW、证据=VERIFY），Linux 分支必须实测；C 未过审前不得按 B 或 C 实施。

## 1 判据 × 证据矩阵

| 判据 | A | B | 关键证据（V-id） | 双方原文 |
| --- | --- | --- | --- | --- |
| J-1 ABI 洁净（`nm -g` 只剩导出） | **不成立** | **成立**（字面；含 V9 边界） | V1、V3、V4、V5 / V6、V7、V8、V9 | `claim.md:50,269,352`；`counter.md:25,58-78,243`；`claim-r2.md:9`；`counter-r2.md:97` |
| J-2 平台可移植（同一套命令） | **成立**（macOS 实测；Linux 半边未实测，不作胜证） | **不成立**（严格读；宽松读下成立） | V11 | `claim.md:68-70`；`counter.md:177-194`；`counter-r2.md:99`；`claim-r2.md:46-49` |
| J-3 静态链接语义不变 | **成立** | **成立**（仅合并形态；逐单元形态被 V10 否证） | V6、V7、V8、V10、V14 | `claim.md:74-80`；`counter.md:149-172`；`claim-r2.md:11,32-40`；`counter-r2.md:100,120` |
| J-4 成本（≤2 文件、≤120 行；回退/失败模式） | **无法判定** | **不成立**（成本/范围口径） | V12；V6、V7、V8 | `claim.md:307-326`；`counter.md:224-234`；`counter-r2.md:122-123`；`claim-r2.md:126` |
| J-5 可复现 | **成立**（证据可复现；门禁未复现单列 §3） | **成立**（macOS；Linux 已写 `skip`） | V1、V2、V6、V7、V8、V11、V14；V12 | `claim.md:292-299`；`counter.md:194,231,234`；`counter-r2.md:123` |

---

### J-1 ABI 洁净

**判据原文**（`question.md:18`）：`nm -g --defined-only` 是否只剩导出函数；若 B 能做到而 A 不能，J-1 归 B。

**A：不成立。**

- V1：HEAD 产物上 `nm -g --defined-only` 得 12 个 defined global——9 个 `Str_*`、`D _Dog_Speak_vtable`、`_dog_get`、`_main`；`Str_*` 与 vtable 都不在 `.abi.h`。注意 V1 的归档含 `main.o`，按 L39-3（`docs/design/phase39-draft.md:136`）不是合法 `--lib` 产物；但**合法形态同样含 vtable**（V6 的 `D _Dog_Speak_vtable`、V10 的 `impl_dog.o`），所以「7→1 成员」这个数字不能用于论证归档形态（`verify.json` 的 unreproduced 第 5 条）。
- V3：消费者不 include 任何头、手抄 `struct Dog` / `Speak_vtbl` 布局并 `extern Dog_Speak_vtable`，链接 `rc=0`、运行 `woof 42`；`-fvisibility=hidden` 的归档同样 `rc=0`。
- V4：消费者手抄 `Str` 布局并直接链接内部 `str_len`，运行 `str_len=4`。
- V5：消费者只定义同名 `helper` 就把库内部调用替换为 999（`api=999`），归档字节与 `nm -g` **完全不变**——A 的 `expected.nm` 快照对此恒绿。
- 自认：`claim.md:269`「J-1 按字面归 B，我不否认」；`claim.md:352`「J-1 按字面归 B」；`claim-r2.md:9`「J-1 成立（字面）；A 仅……成立」；`claim-r2.md:30`「字面读下我承认 A 失败」。
- 反证清单：`counter.md:25`（F-1）已被 V3 证实；`counter.md:29`（F-5）已被 V10 证实；`counter.md:27`（F-3）的「符号面随 std `pub` 增长」被 V15 证实，「只需改夹具即绿」因无 `--lib` 未复现（V12，见 §3）。按 §7.9 第 2 行，A 直接 `rejected`。

**B：成立（字面），但边界必须写入。**

- V6/V7/V8：`ld -r -exported_symbols_list` 合并 + `ar` 后，`nm -g --defined-only` 恰为导出集合（V6 `_dog_get`；V7 `_dog_get` + `_via_vtable`；V8 `_run_lib`），消费者链接运行成功（`woof 7`、`hi A`/`hi B`），constructor 未被丢弃（V8、V14）。
- V9 是边界：库里有**非 static 的 tentative 全局**时（HEAD 默认形态；D39-8 尚未实现，V12），`ld -r` 把它标成 `private external`，但 `nm -g` 仍列出 `C _ps`。即 J-1 的「恰只剩导出」在 B 下**不是无条件**成立，须由 D39-8 把非 `pub` 全局发成 `static`，并由门禁作集合相等断言（不得用 allowlist 掩盖 `C`）。本席据此判 B 的 J-1 **成立**（机制已由 V6/V7/V8 复现），但把 V9 列为 B 的生效条件与残余风险，不写成「无条件洁净」。

**J-1 读法裁定**：采字面。理由：判据的通过方式就是 `nm` 命令；「目标读」会把 A 的 `expected.nm` 升级成判据本身，等于先改判据再判 A 成立（`counter-r2.md:109`）。A′（`claim-r2.md:28-30`，发布 `<base>.nm` + 绑定 `ABI_VERSION`）仍不满足字面 J-1（`claim-r2.md:30` 自认），且其门禁/版本证据在 HEAD 无法复现（V12），故 A′ 也不能救 A。

**原文索引（节号）**：`claim.md §2 J-1`（:50, :269）、`§8 自评`（:352）；`claim-r2.md §0`（:9）、`§1.1`（:28-30）；`counter.md §1 F-1`（:25）、`§2 E1-2`（:58-78）、`§4 E2`（:208）；`counter-r2.md §4 C-1`（:97）、`§5`（:119）。

---

### J-2 平台可移植（同一套命令）

**A：成立**（macOS 实测；Linux 半边只作推断，不作胜证）。

- A 的命令集是 `ct build --emit-c`、`cc -c`、`ar rcs`、`nm -g --defined-only`（`claim.md:68`）。平台前提由冻结卡给出：v1 只覆盖 macOS/Linux 的 `cc` + `ar`（`docs/design/phase39-draft.md:46`），A 不需要这之外的任何工具。
- V11：macOS 上 `cc`、`ar`、`nm`、`ld` 都在；`objcopy`/`llvm-objcopy` MISSING。A 不需要它们。
- Linux 未实测（`verify.json` 的 unreproduced 第 3 条）；「GNU nm/GNU ar 也认同一命令」是标准工具链推断，本席不把它当 A 的胜证。

**B：不成立**（严格读）。

- macOS 的可用形态是 `ld -r -exported_symbols_list` + `nmedit`（V11、V6/V7/V8）；Linux 的形态是 `objcopy --localize-hidden` / `--keep-global-symbol`（本机无法测）。这是**两种工具、两种可见性语义**，不是「同一套命令」。
- 双方自认：`counter-r2.md:99`（C-3「Linux 分支是两套命令、非『同一套命令』，成立」）；`claim-r2.md:48-49`（严格读 B 不过，宽松读才过）。
- 本席采严格读，因为判据原文就是「同一套命令」；若按 `counter.md:244` 的宽松读（`command -v` + 两平台命令），B 可过 J-2——但本庭不采用该解释，理由与 J-1 读法一致：判据文字优先，解释改动须走 §7.10/改判据，不能由一方自选。

**原文索引（节号）**：`claim.md §2 J-2`（:51）、`§3 E1.0`（:90-115）；`claim-r2.md §1.3`（:42-49）；`counter.md §2 E1-7`（:174-194）、`§4 E4`（:228）；`counter-r2.md §4 C-3`（:99）。

---

### J-3 静态链接语义不变

**A：成立。**

- V6：`nm -u main.o` 有 `U _dog_get`；V10：`box.o` 有 `U _Dog_Speak_vtable`。A 不本地化，跨单元引用由 external 定义满足，链接运行正常（V6 `woof 7`）。
- A 的「vtable 跨单元引用真实存在」由 V10 证实（`counter.md:112-147` 与 `claim.md:74-80` 同向）。

**B：成立（仅合并形态）。**

- V10：逐单元 `nmedit` 后消费者链接报 `Undefined symbols: _Dog_Speak_vtable`——**逐单元本地化不成立**。
- V6/V7/V8：整档 `ld -r` 合并后，vtable 就地解析并本地化，消费者链接运行成功；V8、V14 证明 `__ct_init` 与手写 constructor 未被丢弃。
- 所以 J-3 对 B 成立，但成立方式是「合并」，这直接产生 J-4 的 O1 冲突（`ar t` 1 成员，V6/V7/V8）。B 的 J-3 不是免费的。

**原文索引（节号）**：`claim.md §2 J-3`（:52）、`§3 E1.3`（:230-269）；`claim-r2.md §1.2`（:32-40）、`§2 E1-r2-b`（:82-105）；`counter.md §2 E1-5`（:112-147）、`E1-6`（:149-172）；`counter-r2.md §5`（:120）。

---

### J-4 成本

**A：无法判定。**

- `claim.md:307-326` 估 2 文件、40–45 行；但 HEAD 无 `--lib`（V12），没有真实实现可量，证据席也把成本列为不可判定（`verify.json` 的 J-4 fact）。本席不把 A 的估算当「A 更便宜」的胜证。

**B：不成立**（不是行数超限，而是成本/范围口径不满足）。

- 行数本身无法测（V12）；`counter.md:224-234` 估 2 文件 35–45 行，`claim.md:320-324` 估 ≥3 文件 150–220 行，两方数字都无法由 HEAD 复现。
- 但 B 的**唯一实测形态**（V6/V7/V8）使归档从 N 个逐单元成员变成 1 个成员（`ar t` 1 行），直接改动冻结的 O1（`docs/design/phase39-draft.md:36`「逐单元 `.o`」）与 §3.2 的产物形态；`counter-r2.md:122,229` 自认这一点，且其 35–45 行估算**未计入**卡片改写、p39 夹具重写与 `nmedit` 每成员清单（`counter.md:194`）。
- 因此 B 不满足 J-4 的「成本」口径：不是「超 120 行」这一条的实测结论，而是「冻结卡交付物形态要改、成本被低估」这一条的证据成立。若只问行数，本项对双方都是无法判定；本席在 J-4 上判 B 不成立，依据是 O1 冲突，不是行数。

**原文索引（节号）**：`claim.md §6`（:303-326）；`claim-r2.md §0`（:12）、`§4`（:126）；`counter.md §5 E4`（:220-234）；`counter-r2.md §5`（:122-123）。

---

### J-5 可复现

**A：成立（证据层面）。**

- V1、V2、V3、V4 在 HEAD 干净源码上可重跑，环境见 `verify.json` 头部（macOS、Apple clang 21、llvm-nm）；Linux 未测，按 `skip` 处理。
- 但 A 的 **P1**（`expected.nm` 加符号变红）与 A′ 的 `<base>.nm`/`ABI_VERSION` 门禁在 HEAD 不存在（V12），属「方案未实现」而非「证据不可复现」；单列在 §3，不计入 J-5 的失败，也不当 A 的胜证。

**B：成立（macOS；Linux 已标 skip）。**

- V6/V7/V8/V11/V14 在 macOS 可重跑；V11 记录 `ld -r` 对清单里不存在的符号 `rc=0` 静默成功，B 必须以 `nm` 断言兜底（`counter.md:194,231` 自认）。
- Linux 分支本机无法测，B 已按 J-5 写 `skip`（`counter-r2.md:123`、`counter.md:234`），不是默绿；这同时是 B 的 J-2 不成立的原因，J-5 本身不因此判负。

**原文索引（节号）**：`claim.md §2 J-5`（:54）、`§5 E3`（:292-299）；`counter.md §2 E1-7`（:174-194）、`§5 E4`（:230-234）；`counter-r2.md §5`（:123）。

---

## 2 §7.9 推导

| §7.9 行 | 适用 | 结果 |
| --- | --- | --- |
| 主张满足全部判据、反证失效条件均被排除 | A 不满足 J-1 | 不适用 `upheld` |
| 判据未被满足，或反证至少一条失效条件被证实 | A 的 J-1 不成立；F-1/F-5 被证实，F-3 的符号面一半被证实 | **`rejected`** |
| 证据不足以判定任一方向 | 仅 J-4 对 A 的部分、Linux 部分 | 不足以免除 J-1 的失败 |

**结论**：`verdict: rejected`（对主张 A）。

**但 §7.9 的 `rejected` 不等于 B 成立**（§7.9 原文：「反对席只承担证伪，不承担替代方案」）。B 不是本庭主张方，本席只记录其在 J-1/J-3/J-5 成立、在 J-2/J-4 不成立，**不产出对 B 的 `upheld`**。B 也不满足全部判据，故进入 §7.10。

## 3 证据席的「无法判定」事项（写入判决，不得作胜证）

| 事项 | 依据 | 处置 |
| --- | --- | --- |
| `--lib` 尚未实现；`.abi.h`、`<BASE>_ABI_VERSION`、`expected.nm`、p39 门禁均不存在 | V12（`ct build --lib` 报 unknown option，rc=1；`check-ast.sh` 无 p39 段；无 `test/modules/p39_lib`） | A 的 P1、A′ 的版本绑定、C 的门禁红绿都不能由本庭认定；只能作为待实现/待复现项 |
| `ABI_VERSION` 随允许集合变化 | V15 只复现了 std `pub` 增加使 defined global 9→10；HEAD 无任何 `.abi.h`/`ABI_VERSION` 产物 | 「版本不动」只复现了符号面一半；整体不可判定 |
| Linux 的 GNU nm/objcopy/`--localize-hidden`、前缀与排序 | `verify.json` 的 unreproduced 第 3 条 | J-2/J-5 的 Linux 半边全部 `skip`；不得由 macOS 证据外推 |
| 成本（文件/行数） | V12；`verify.json` 的 J-4 fact「改动量不可由现有证据判定」 | A 的 2 文件/40–45 行与 B 的 35–45 行都只是估算；J-4 判 A 无法判定 |
| B 的 `C` 符号边界（V9） | V9：`nm -g` 仍列 `C _ps` | 不判 B 的 J-1 失败，但作为 B 的生效条件；C 必须用集合相等断言堵住 |
| `build --emit-c` 不发射 `__ct_init`，单文件发射（V13） | V13：单文件 2 处、build 0 处 | 不裁归属；记为 PH-39 的 R6 风险；C 不掩盖 |
| V1 的 `7→1` 成员数 | V1 归档含 `main.o`，不合 L39-3；合法形态是 V6/V7/V8 的 3→1 | 不采用「7→1」作为归档形态证据 |

**特别说明**：A 的 `expected.nm` **只锁门禁、不锁消费者契约**——V5 证明归档不变时消费者的同名符号仍可替换库内部调用，快照必绿。这一点不因 A′ 的「发布 `<base>.nm`」而自动成立（A′ 未实现、未复现，V12）；即使成立，也不满足 J-1 字面。

## 4 §7.10 出口

**选择出口 1：产出 C 方案**，写入 `battle/p39-2/C-proposal.md`。

C 的核心（详见 C-proposal.md）：`--lib` 仍逐单元 `cc -c` 出 `<unit>.o`（保留为构建产物，满足 A 的「逐单元 `.o`」），再用 **同一个 `cc` 驱动**的 `cc -r` 合并全部单元，并按平台只差一个 `-Wl` 参数做本地化（macOS `-exported_symbols_list`，Linux 候选 `--localize-hidden` 或 `--retain-symbols-file`）；`ar` 只归档 `<base>.sealed.o`；`nm -g --defined-only` 集合必须等于导出集合。工具集只有 `cc` + `ar` + `nm`，满足 A 的「同一套 cc/ar」；密封后 `nm` 只剩导出，满足 B 的 J-1；vtable 在合并前保持 external（跨单元装箱可解析），`Str_*` 在密封对象内被本地化。

**C 的生效前提（缺一不得实施）**：

1. 走一次单方案评审：主张席=ARCH（原主张人）、反对席=REVIEW、证据席=VERIFY（§7.10 出口 1）。
2. Linux 分支必须实测通过；未实测前 Linux 不得发布 `--lib` 密封形态。
3. C 改变了冻结卡的 O1/§3.2/D39-5/O3 边界/E39-2/E39-5，属 6.2/6.6 T-6 的判据变更，须用户批准；本判决不代替该批准。
4. `cc -r` 的确定性、`__ct_init` 保留、`nm` 集合断言的红/绿负例必须由证据席复现。

**若 C 未过审**：按 §7.10 出口 2 登记 open-question（owner: REQ；截止：PH-39 开工前或 2026-12-01，取先到者；默认裁决规则：采用 B 的合并形态并把 O1 改为「归档 1 成员」，Linux 未验证前只发 `--no-seal` 并标注非 ABI 洁净）。不得在 C 未过审时直接按 B 实施。

## 5 生效范围

本判决**只**约束 PH-39 的归档内部符号处理：

- 受影响：O1（`docs/design/phase39-draft.md:36`）、§3.2 产物形态、§3.3 符号与可见性、D39-5（`:59`）、O3 边界（`:40`）、E39-2（`:177`）、E39-5（`:180`），以及 `test/modules/p39_lib/**` 与 `selfhost/check-ast.sh` 的 p39 段。
- 不受影响：导出集合本身（B39-1、D39-2）、`--lib` 命名与确定性（D39-3、D39-4）、`--lib` 的 L39-* 负例语义、主规范、其他 phase、其他门禁编号。
- 本判决**不授权**修改任何源码、PH-39 卡或主规范；C 的落地须另走单方案评审与用户批准。
- 范围外引用本判决（例如拿它去裁 `--lib` 导出集合或别的仓库）无效。

## 6 证据索引

| V-id | 一句话 | 本庭用途 |
| --- | --- | --- |
| V1 | HEAD 产物 12 个 defined global，含 vtable + 9 个 `Str_*` | A 的 J-1 不成立 |
| V2 | `-fvisibility=hidden` 后 `nm -g` 逐字节相同 | visibility 不构成静态归档隔离 |
| V3 | 消费者 extern 内部 vtable，链接运行成功；hidden 归档同样成功 | F-1/F-2 证实 |
| V4 | 消费者 extern `str_len`，链接运行成功 | A3 风险证实 |
| V5 | 消费者同名 `helper` 替换库内部调用（api=999），归档 `nm` 不变 | A 的快照不覆盖抢占 |
| V6 | `ld -r` 合并后 `nm -g` 只剩 `_dog_get`，3→1 成员，消费者运行 | B 的 J-1/J-3 |
| V7 | 三单元合并后只剩两个导出，`woof 7` | B 的 J-1（含装箱单元） |
| V8 | 真实 `__ct_init` 经 `ld -r` 保留，运行 `hi A`/`hi B` | B 的 J-3；constructor 不被丢弃 |
| V9 | 非 static tentative 全局 `C _ps` 在本地化后仍在 `nm -g` | B 的 J-1 边界/生效条件 |
| V10 | 逐单元 `nmedit` 后链接报 `Undefined _Dog_Speak_vtable` | B 只能整档合并；O1 冲突 |
| V11 | macOS 无 objcopy；`nmedit`/`ld` 存在；`ld -r` 对缺失符号静默成功 | J-2/J-5 失败模式 |
| V12 | HEAD 无 `--lib`，无 p39 门禁/夹具 | A′/C 的门禁与成本不可判定 |
| V13 | 单文件发射 `__ct_init`，build 模式不发射 | PH-39 R6 风险，不裁归属 |
| V14 | 手写 constructor 经 `ld -r` 保留 | B 的 J-3 补强 |
| V15 | std 加 `pub` 函数，defined global 9→10，无 ABI 产物 | F-3 的符号面一半 |
