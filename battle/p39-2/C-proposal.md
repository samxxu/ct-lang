# battle/p39-2 C 方案 — 逐单元对象保留 + 单成员密封归档（`cc` / `ar` / `nm`）

| 字段 | 值 |
| --- | --- |
| 来源 | §7.10 出口 1（A 被否，B 不满足 J-2/J-4） |
| 状态 | **提案**，待单方案评审（主张=ARCH、反对=REVIEW、证据=VERIFY） |
| 适用 | 只约束 PH-39 的归档内部符号处理；不改导出集合（B39-1/D39-2）、不改 `--lib` 命名与确定性（D39-3/D39-4） |
| 依据 | `battle/p39-2/verdict.md`、`battle/p39-2/verify.json`、`docs/design/phase39-draft.md` |

## 0 一句话

`--lib` 仍逐单元 `cc -c` 产出 `<unit>.o`（保留为构建产物，满足 O1 的「逐单元 `.o`」），再用 **同一个 `cc` 驱动**的 `cc -r` 把全部单元合并成一个可重定位对象，并在同一个 `cc` 调用里用平台链接器选项把非导出符号本地化；`ar` 只归档这一个密封对象，`nm` 断言 `nm -g --defined-only` 的集合等于导出集合。工具集仍只有 `cc` + `ar` + `nm`，平台分叉收敛为 `cc -r` 的**一个** `-Wl` 参数。

## 1 与 A / B 最强约束的对照

| 约束 | 来源 | C 如何满足 |
| --- | --- | --- |
| A：逐单元 `.o` | `docs/design/phase39-draft.md:36`（O1）、`claim.md:78` | 每个单元仍产出 `<outdir>/<unit>.o`，保留、可调试、可单独复用；不删除、不改名 |
| A：macOS/Linux 同一套 `cc`/`ar` | `question.md:19`（J-2）、`claim.md:68` | 工具只有 `cc`、`ar`、`nm`；合并与本地化都走 `cc -r`，两平台只差一个 `-Wl` 参数（见 §3） |
| B：`nm -g` 只剩导出 | `question.md:18`（J-1）、V6/V7/V8 | 归档只含 `<base>.sealed.o`；`nm -g --defined-only` 集合 = `.abi.h` 原型集合；门禁断言集合相等 |
| B：抗抢占（B 的真实收益） | `counter-r2.md:31-81`（E1-r2）、V5 | 密封对象内 `Str_*`、内部 `helper`、vtable 均为 local；消费者同名定义不再替换库内部调用 |
| 不动导出集合 | `question.md:30` | 密封化不新增/删除导出名；导出名仍由 D39-2/§3.1 决定 |
| 不引入第三方/构建系统 | `AGENTS.md:391` | 只用系统 `cc` / `ar` / `nm`；不引入 `objcopy`/`nmedit`/`ld` 作为独立工具，不新增构建系统 |

**C 的让步（必须写明）**：**归档成员从「N 个逐单元 `.o`」变为「1 个密封对象」**。逐单元 `.o` 仍是构建产物，但不再是归档成员。这不是风格选择，而是 V10 的直接后果：逐单元本地化会切断 `box.o` 的 `U _Dog_Speak_vtable`，消费者链接报 `Undefined symbols`（V10）。所以在现有发射器下，「归档成员逐单元 + `nm` 只剩导出」**不可能同时成立**。若评审把 O1 的「逐单元 `.o`」读成「归档成员必须逐单元」，C 不成立，回到 §7.10 出口 2（见 §10）。

**C 对 J-2 的诚实边界**：`cc -r` 内部必然调用平台链接器（macOS 的 `ld`、Linux 的 GNU ld）。C 的 J-2 主张是「用户与门禁只调 `cc`/`ar`/`nm`，平台分叉只有 1 个 `-Wl` 参数」，**不是**「不运行链接器」。若评审把 J-2 读成「编译/归档过程不得调用链接器」，C 与 B 同样不成立，应直接走 §7.10 出口 2——本席不把 `cc -r` 包装成「纯编译器」。

## 2 产物

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| 归档 | `<outdir>/lib<base>.a` | **1 个成员** `<base>.sealed.o`；确定性按 D39-4（`ar rcsD`，否则 `ZERO_AR_DATE=1 ar rcs`） |
| 密封对象 | `<outdir>/<base>.sealed.o` | `cc -r` 合并 + 本地化；中间产物，不安装、不属于 ABI |
| 逐单元对象 | `<outdir>/<unit>.o` | O1 保留；**不入归档**；文档注明「构建产物，非 ABI，消费者应链接 `.a`」 |
| ABI 头 | `<outdir>/<base>.abi.h` | 同冻结卡 §3.2 |
| 允许集合 | `<outdir>/<base>.nm` | 归一化、去前导 `_`、排序后的 `nm -g --defined-only`（密封模式 = 导出集合；`--no-seal` 模式 = 导出 + 已声明内部符号） |

`<base>.nm` 的归一化规则与卡上 §3.3 一致：去空行、去 `*.o:` 成员头、忽略 `__.SYMDEF` / `__.SYMDEF SORTED` 索引成员、去前导 `_`、取符号名、排序。密封模式下它与 `.abi.h` 的原型集合互为校验（E39-6 的原型集合 = 导出集合）。

## 3 命令序列（可脚本化）

### 3.1 公共步骤（两平台相同）

```bash
# 1) --lib 内部逐单元发射并编译（--lib 与 --emit-c 互斥，故不并写）
ct build --lib --outdir <outdir> <root.h.ct>
#    内部：逐单元 .c -> cc -std=c99 -fvisibility=hidden -I <outdir> -c <unit>.c -o <unit>.o
# 2) 合并 + 本地化（输入是本次构建的 .o 列表，不用 outdir/*.o，
#    以免混入旧产物或上一次的 <base>.sealed.o）
cc -r <平台 -Wl 参数> -o <outdir>/<base>.sealed.o <unit>.o...
# 3) 归档（D39-4 确定性）
ZERO_AR_DATE=1 ar rcs <outdir>/lib<base>.a <outdir>/<base>.sealed.o
# 4) 允许集合 + 断言
nm -g --defined-only <outdir>/lib<base>.a | <归一化> > <outdir>/<base>.nm
# 断言：<base>.nm 的集合 == 导出集合（集合相等，不是「包含」）
```

`<base>.exports` 是给链接器的导出清单：一行一个 C 符号名；Mach-O 带前导 `_`，ELF 不带。它与 `.abi.h` 的原型集合由同一份导出扫描生成，避免两处漂移。

### 3.2 macOS

```bash
cc -r -Wl,-exported_symbols_list,<outdir>/<base>.exports \
   -o <outdir>/<base>.sealed.o <unit>.o...
```

- 与 V6/V7/V8 的 `ld -r -exported_symbols_list` 是**同一个链接器调用**，只是经 `cc` 驱动。
- 本席在 `/tmp` 做过一次最小探针（未入 `verify.json`，不得当庭内胜证）：`cc -r -Wl,-exported_symbols_list,exp.txt -o merged.o lib.o` → `rc=0`，`nm -g --defined-only` 恰为 `_dog_get`，`nm -m` 显示 `non-external (was a private external)`。C 评审须由证据席用真实 `--lib` 夹具复现，并处理 `ld: warning: ignoring unexpected dylib .../libSystem.B.tbd` 是否进零警告门禁。

### 3.3 Linux（未实测，C 的阻断项）

候选按优先级：

1. `cc -r -Wl,--localize-hidden -o <outdir>/<base>.sealed.o <unit>.o...`
   —— 若 GNU ld 接受 `-r` 下的 `--localize-hidden`（本机无法测，`verify.json` 的 unreproduced 第 3 条）；
2. `cc -r -Wl,--retain-symbols-file,<outdir>/<base>.exports ...`
   —— 只保留导出符号；须验证不会破坏已解析的内部重定位；
3. 若 1/2 都不可行，才考虑 `objcopy --localize-hidden`；**但这违反 C 的「cc/ar-only」约束**，只能作为登记偏离，不能默认。

- 任一候选在 Linux 实测通过前，Linux 的 `--lib` **不得发布密封形态**；只能显式 `--no-seal`（非 ABI 洁净，见 §5）。
- 工具探测：`command -v cc ar nm`；缺一即硬错（J-5 不得默绿）。

## 4 两个关键对象怎么处置

### 4.1 trait vtable

- **逐单元 `.o` 阶段**：保持 external，与今天一致（V1、V10 的 `U _Dog_Speak_vtable`）；这是跨单元装箱的解析基础。
- **`cc -r` 之后**：跨单元引用就地解析；本地化后 vtable 变 `d`、impl 方法变 `t`（V7 的 `nm -g` 与 `nm` 形态）。`nm -g` 只剩导出。
- **不修改 Emitter**：不新增 vtable getter、不复制 vtable、不改命名规则（`<Trait>_vtbl`、`<Struct>_<Trait>_vtable` 等保持冻结）。`Emitter.h.ct:3304` 的 `extern` 声明照旧；它只在逐单元阶段使用，密封对象里已不存在 external vtable。
- **断言**：密封对象里若 vtable 仍为 `D`/`T`（本地化失败），`nm` 集合断言必红；不发布。

### 4.2 std `Str_*`

- `.abi.h` 不出现 std 类型（D39-6），所以 std 单元符号**全部是内部符号**，不属 ABI。
- **密封模式**：`Str_*`/`str_*` 在合并对象内被本地化（`t`）。消费者不能链接它们（V4 的误链在密封形态下消失），也不能同名抢占（V5 的 `api=999` 在密封形态下不成立）。
- **`--no-seal` 模式**：`Str_*` 仍 external，必须逐条写入 `<base>.nm` 允许集合，并把该集合的哈希并入 `<BASE>_ABI_VERSION`。这样新增 std `pub` 函数（V15 的 9→10）会改变版本宏，不再「只需改夹具即绿」。
- **可选优化（不影响 ABI）**：若本次 `--lib` 的导出面与内部单元都没有引用某个 std 单元，可不发射该单元；不引入新语义、不改导出集合。

### 4.3 V9 的 common 符号

- 密封模式的断言是**集合相等**：不允许 `C`/`D`/`T` 的非导出符号留在 `nm -g`。若 D39-8 尚未把非 `pub` 全局 `static` 化，V9 的 `C _ps` 会让门禁红——这是**预期红**，由 D39-8 修复，不用 allowlist 掩盖。
- `--no-seal` 模式允许 `C` 进允许集合，但必须显式列出并计入 `ABI_VERSION`。

## 5 可选 flag

新增 **`--no-seal`**（仅 `--lib` 可用；默认关闭 = 密封）：

| 项 | 内容 |
| --- | --- |
| 用途 | 平台链接器不支持本地化时的显式逃生门；调试/教学需要逐成员归档时 |
| 行为 | 归档 = 逐单元 `.o`（回到今天的 O1 形态）；`nm -g` 含内部符号；`<base>.nm` = 导出 + 已声明内部；`<BASE>_ABI_VERSION` 绑定允许集合哈希 |
| 标注 | `.abi.h` banner、文档、`<base>.nm` 三处标注「unsealed，非 ABI 洁净」 |
| 不加 `--seal` | 默认即密封，避免两个 flag 组合与默认值歧义 |

命名可在评审中调整；判据不变：**默认密封；未密封必须显式、可审计、标注非 ABI**。

## 6 失败 / 回退路径

| 失败 | 行为 |
| --- | --- |
| `cc -r` 非零 | 硬错（新 L39-6：`cannot seal archive: <reason>`），删除 `.a` / `.sealed.o` / `.abi.h`，不写半成品 |
| 平台本地化选项不支持 | 硬错，打印平台与「可用 `--no-seal` 显式换取非洁净归档」；**不自动回退**（J-5 不得默绿） |
| `nm` 集合 ≠ 导出集合 | 硬错（覆盖 V11 的 `ld -r` 对缺失符号 `rc=0` 静默成功） |
| 两次构建 `.a` 的 sha256 不同 | 硬错（E39-5 保持）；密封对象必须确定性 |
| 用户显式 `--no-seal` | 允许；`.nm`、`ABI_VERSION`、文档三处记录；门禁仍断言集合相等 |
| 回退实现 | 删除密封步骤、恢复逐成员归档；单提交 `git revert`；导出集合与 `.abi.h` 不变 |

## 7 卡面改动（随 C 一起审，不自动生效）

| 位置 | 现状 | C 后 |
| --- | --- | --- |
| O1（`phase39-draft.md:36`） | `--lib` 产出 `.a` + `.abi.h` + 逐单元 `.o` | `.a`（1 个密封成员）+ `.abi.h` + 逐单元 `.o`（构建产物，不入归档） |
| §3.2 产物表 | 归档由逐单元 `.o` 组成 | 归档由 `<base>.sealed.o` 组成；逐单元 `.o` 保留在 `--outdir` |
| §3.3 符号 | vtable 仍 external；`expected.nm` 快照 | 密封后 vtable/`Str_*` local；`nm -g` = 导出集合；`<base>.nm` 断言集合相等；`--no-seal` 走旧快照 |
| D39-5（`:59`） | 符号面用 `nm` 快照锁定 | 默认 `cc -r` 密封；快照只用于 `--no-seal` |
| O3 边界（`:40`、`:49`） | 「不承诺把内部符号藏掉」 | 改为「默认密封；`--no-seal` 不承诺」 |
| E39-2（`:177`） | 符号面 = 导出 + 快照（含 vtable） | 符号面 = 导出集合；`nm -g` diff 为空 |
| E39-5（`:180`） | 两次 `.a` 字节相同 | 追加密封对象确定性（同一 `.o` 输入） |
| 负例 | L39-1…L39-5 | 新增 L39-6（密封失败）+ 一条「本地化未生效」的可失败夹具 |
| 夹具 | `expected.nm` 含 vtable/`Str_*` | `expected.nm` = 导出集合；逐单元 `.o` 另作独立检查（可选） |

冻结卡变更属 6.2/6.6 T-6 的判据变更，须用户批准；C 评审通过不等于卡变更自动生效。

## 8 C 的未验证项（评审必须做，缺一不得采纳）

1. **Linux**：GNU ld `-r --localize-hidden`（或 `--retain-symbols-file`）是否真的本地化且不破坏重定位；本机无法测（`verify.json` unreproduced 第 3 条）。
2. **`cc -r` 的确定性**：两次构建 `.a` 的 sha256 是否相同；Mach-O 是否带 UUID/时间戳；若不确定，是否可用 `ZERO_AR_DATE` / `-Wl,-no_uuid` 等固定（不得引入新依赖）。
3. **constructor 保留**：V8/V14 已证 `ld -r` 保留 `__ct_init`；C 走同一链接器，仍须在 p39 夹具复跑（含 `--lib` 的 constructor 顺序）。
4. **`--no-seal` 的门禁红绿**：V12 说明 HEAD 无 `--lib`，须实现后测；新增 std `pub` 函数必须让 `ABI_VERSION` 变。
5. **V13**：`build --emit-c` 不发射 `__ct_init`（单文件才发射）；若 `--lib` 复用 build 路径，file-scope 数组的 vptr 初始化缺失。这是 PH-39 的 R6 风险，C 不掩盖、不裁归属；若 R6 不修，C 的密封形态也不能声称「运行正确」。
6. **`cc -r` 的 warning**：本席探针见 `ld: warning: ignoring unexpected dylib .../libSystem.B.tbd`；须消除或证明不进零警告门禁。
7. **O1 新读法**：用户/评审是否接受「归档 1 成员、逐单元 `.o` 仅作构建产物」。

## 9 成本

| 项 | 估算 |
| --- | --- |
| 实现 | `selfhost/ct-ast/frontend/module/Module.h.ct`（`cc -r` 调用、临时文件、平台参数、清理、`nm` 自校验）+ `selfhost/ct-ast/tool/driver/Driver.h.ct`（`--no-seal` 解析、导出清单落盘）：**2 文件，约 60–90 行** |
| 夹具/门禁 | `selfhost/check-ast.sh` p39 段改集合断言 + `test/modules/p39_lib/expected.nm` 改为导出集合 + 1 条密封失败负例：**2 文件，约 40–60 行** |
| 文档/卡面 | `docs/design/phase39-draft.md`、`docs/package-guide.md`、`docs/language-spec.md`、`README.md` 若干行 |
| 平台分支 | 1 处（`-Wl` 参数） |
| 失败模式 | 4 条（§6） |
| 回退 | 删除密封步骤，单提交 revert |

对比 J-4（≤2 文件、≤120 行）：实现侧 2 文件在预算内；若把夹具/门禁/卡面计入则超过 2 文件——**这一点不隐藏**，由单方案评审按 J-4 原口径裁定。C 不声称自己「比 A 便宜」；C 的卖点是同时消除 A 的 J-1 失败与 B 的 J-2 失败。

## 10 若 C 不成立

按 §7.10 出口 2 登记 open-question：

- **owner**：REQ。
- **截止**：PH-39 开工前，或 2026-12-01，取先到者。
- **默认裁决规则**：采用 B 的合并形态，并把 O1 改为「归档 1 成员」；Linux 分支未实测前，`--lib` 只发 `--no-seal` 并在 `.abi.h`/文档标注「非 ABI 洁净」。若用户不接受 O1 改动，则默认回到 A 的「发布 `<base>.nm` + `ABI_VERSION` 绑定」形态，并在文档明写「`nm -g` 面 ⊋ 导出面」。
- **禁止**：C 未过审时按 B 直接实施——§7.9 的 `rejected` 不等于 B 成立。

## 11 与 A / B 的差异一览

| 项 | A | B | C |
| --- | --- | --- | --- |
| 归档成员 | N 个逐单元 `.o` | 1 个合并对象 | 1 个密封对象 |
| 逐单元 `.o` | 归档成员 | 丢弃或另存（成本翻倍） | **保留为构建产物** |
| 工具集 | `cc`/`ar`/`nm` | `ld`/`nmedit`/`objcopy` | `cc`/`ar`/`nm`（`-Wl` 参数分叉 1 处） |
| `nm -g` | 含 vtable/`Str_*` | 只剩导出（V9 边界） | 只剩导出（集合断言） |
| vtable | external | 合并后 local | 逐单元 external → 密封后 local |
| std `Str_*` | external，靠快照 | 合并后 local | 密封后 local；`--no-seal` 时进允许集合 + 版本 |
| 跨单元装箱 | 依赖 external vtable | 依赖整档合并 | 依赖 `cc -r` 合并 |
| 平台分支 | 0 | 2 套工具 | 1 个 `-Wl` 参数 |
| 可选 flag | 无 | 无 | `--no-seal`（默认密封） |
| 主要风险 | J-1 不成立 | 改 O1、Linux 未测、工具两套 | Linux 链接器选项未测、`cc -r` 确定性与 warning、O1 新读法 |
