# battle/p39-2 单方案评审 — 主张席（ARCH，原提案人）对 C 的评审

> 评审对象：`battle/p39-2/C-proposal.md`；依据：`verdict.md`（`rejected` A，出口 1）、`verify.json`。
> 我的立场：A 已被判死，我评审 C 是否**可采纳**，不借评审复活 A。

## 0 结论摘要

| 判据 | C 的成立情况 | 说明 |
| --- | --- | --- |
| J-1 | **成立**（字面） | 实测 `nm -g --defined-only` 只剩 `_dog_get`；V9 的 `C` 符号由集合相等断言 + D39-8 堵 |
| J-2 | **条件成立** | 命令仍是 `cc`/`ar`/`nm`，平台只差 1 个 `-Wl` 参数；Linux 选项未实测 → Linux 半边仍 `skip`，不得外推 |
| J-3 | **成立** | 实测消费者链接密封对象并运行 `woof 7` |
| J-4 | **取决于口径**：实现口径成立（2 文件 60–90 行），判决对 B 用过的「范围口径」下**不成立** | C 自认夹具/卡面另计；判决以 O1 冲突判 B 的 J-4 不成立，C 同样改 O1/§3.2 → 同罪。**请裁判统一口径** |
| J-5 | **成立** | 本轮新测：两次 `cc -r` 的 sha256 相同；`ld` 警告可被一个 `-Wl` 参数消除 |

**建议：有条件采纳 C**（条件见 §5），Linux 未测是**发布阻断**而非设计阻断。

## 1 问题 1：J-2 / J-3 是否真的满足

### J-2「同一套 cc/ar/nm」——成立，但只在命令名层面

- C 的用户/门禁命令：`ct build --lib`、`cc -c`、`cc -r`、`ar rcs`、`nm -g --defined-only`。`cc -r` 内部必然调平台链接器（C 已自认，C-proposal.md:27），但 **J-2 的原文是「同一套命令在 macOS + Linux 的默认工具链可用，不新增第三方依赖」**（`question.md:19`），不是「不得运行链接器」。`cc -r` 是同一个 `cc` 驱动、零新依赖 → **满足**。
- 与 B 的差别是实质的：B 需要 `nmedit`/`objcopy` 两个不同工具名（macOS 与 Linux 不同），C 只有 `-Wl` 参数不同。C 在 J-2 上确实比 B 强。
- **但** Linux 的 `-Wl,--localize-hidden`/`--retain-symbols-file` 本机无法实测（`verify.json` unreproduced 第 3 条）。所以 J-2 的结论应写成「**macOS 成立；Linux 条件成立，未测前不得声称成立**」，不能把 macOS 结果外推。

### J-3「跨单元 vtable 仍解析」——成立

- 合并发生在本地化之前：逐单元阶段 vtable 仍 external（V10 的 `U _Dog_Speak_vtable`），`cc -r` 先就地解析再本地化；密封对象里 vtable 变 `d`（见 §3 E1-C2 的 `nm -m`），消费者链接运行成功。**成立。**
- 附带观察：密封对象的 `nm -m` 出现 `non-external (was a private external) LC1`（`__cstring`），不影响链接语义，属正常 Mach-O 重定位结果。

## 2 问题 2：O1「逐单元 `.o`」的新读法可不可接受

**分两层，答案不同：**

1. **只看 O1（`docs/design/phase39-draft.md:36`）**：「`--lib` 产出 `lib<base>.a` + `<base>.abi.h` + 逐单元 `.o`」——只要求**产出**逐单元 `.o`，没说归档成员是谁。C 的读法在此层**可接受**。
2. **看 §3.2（`docs/design/phase39-draft.md:116`）**：「中间对象 `<outdir>/<unit>.o`｜**只归档本构建生成的 `.o`**，不混入用户手写对象」——「归档」与「本构建生成的 `.o`」在同一行，且 R5（`:162`）写「逐单元 `.o` + `ar` 归档 + 符号面」。这两处把归档成员定为逐单元 `.o`。**C 的读法与 §3.2 冲突**，只能按 C §7 的卡面改动（§3.2 行改为「归档由 `<base>.sealed.o` 组成」）生效，且须用户批准（6.2/6.6 T-6）。
3. **因此**：C 的「满足 O1」表述（C-proposal.md:18、:12）应改为「**O1 不变，§3.2/R5 随卡面改动**」；否则读者会以为改卡不是必需。C 不能既说「O1 新读法即可」又说「§3.2 要改」——两句话只能留一句。
4. **是否应改回 B 的合并形态？不必。** C 的归档形态与 B 相同（1 个成员），差别只在用 `cc -r` 还是 `ld -r`；改回 B 只会多引入 `nmedit`/`objcopy` 两个工具名，J-2 反而变差。C 的正确修法是**把卡面改动写全**，不是退回 B。

## 3 问题 3：新增 E1（本轮实测，不重复 T1–T3）

### E1-C1：两次 `cc -r` 的确定性（支持 C 的 E39-5）

```console
$ printf '_dog_get\n' > /tmp/expC.txt
$ cc -r -Wl,-exported_symbols_list,/tmp/expC.txt -o /tmp/sealed1.o impl_dog.o shapes.o; echo rc=$?
rc=0
$ sleep 1
$ cc -r -Wl,-exported_symbols_list,/tmp/expC.txt -o /tmp/sealed2.o impl_dog.o shapes.o; echo rc=$?
rc=0
$ shasum -a 256 /tmp/sealed1.o /tmp/sealed2.o
06ab32fddd7fd1007ae42e29a0cef7fbb7fba7af3c8c099513a5332b49a49f01  /tmp/sealed1.o
06ab32fddd7fd1007ae42e29a0cef7fbb7fba7af3c8c099513a5332b49a49f01  /tmp/sealed2.o
$ cmp /tmp/sealed1.o /tmp/sealed2.o && echo deterministic
deterministic
```

结论：至少在本夹具上 `cc -r` **字节确定**，C 的 E39-5 追加项可满足；但仍须在真实 `--lib` 夹具复跑（V12 无实现）。

### E1-C2：`cc -r` 的默认警告与抑制（C 的 §8.6 需要裁决）

```console
$ cc -r -Wl,-exported_symbols_list,/tmp/expC.txt -o /tmp/sealed1.o impl_dog.o shapes.o
ld: warning: ignoring unexpected dylib '/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk/usr/lib/libSystem.B.tbd'
$ nm -g --defined-only /tmp/sealed1.o
0000000000000040 T _dog_get
$ nm -m /tmp/sealed1.o | head -5
000000000000004c (__TEXT,__cstring) non-external (was a private external) LC1
0000000000000000 (__TEXT,__text) non-external _Dog_Speak_hi
0000000000000058 (__DATA,__data) non-external (was a private external) _Dog_Speak_vtable
0000000000000040 (__TEXT,__text) external _dog_get
$ cc -r -nostdlib -Wl,-exported_symbols_list,/tmp/expC.txt -o /tmp/s_n.o impl_dog.o shapes.o   # 无警告
$ nm -g --defined-only /tmp/s_n.o
0000000000000040 T _dog_get
$ cc /tmp/p39split/main.o /tmp/s_n.o -o /tmp/bin_n && /tmp/bin_n
woof 7
$ cc -r -Wl,-w -Wl,-exported_symbols_list,/tmp/expC.txt -o /tmp/s_w.o impl_dog.o shapes.o      # 也无警告
```

- **警告真实存在**（每次 `cc -r` 一条，stderr），且它不是 `-Wall -Wextra` 的编译告警。`selfhost/check-warnings.sh:86` 的扫描是 `-Wall -Wextra -std=c99 -c`，**不覆盖 `cc -r`**，所以零警告门禁不会红；但它会出现在 `ct build --lib` 的 stderr 与 E2E 日志里，C §8.6 的「消除或证明」必须落成**明确选择**。
- **建议**：用 `-nostdlib`（本测已证：无警告、`nm -g` 仍只剩导出、消费者运行 `woof 7`）；**不要**用 `-Wl,-w`（它会连真实链接警告一起吞掉，违背「不吞错误」与 J-5 的诚实性）。C 应把 `-nostdlib` 写进 §3.2 并在 p39 夹具断言 stderr 为空。

### 新增 E2 锚点（不利于 C）

| # | 锚点 | 内容 | 方向 |
| --- | --- | --- | --- |
| E2-C1 | `docs/design/phase39-draft.md:116` | 「中间对象 `<outdir>/<unit>.o`｜**只归档本构建生成的 `.o`**」 | 不利于 C：与「逐单元 `.o` 不入归档」直接冲突，必须改卡 |
| E2-C2 | `docs/design/phase39-draft.md:162` | R5「逐单元 `.o` + `ar` 归档 + 符号面」 | 不利于 C：任务行同样把归档成员写成逐单元 `.o` |
| E2-C3 | `docs/design/phase39-draft.md:36` | O1「产出 `.a` + `.abi.h` + 逐单元 `.o`」 | 利于 C：O1 本身只要求产出，未规定归档成员 |

## 4 问题 4：J-1…J-5 与 Linux 阻断

| 判据 | 成立？ | 生效条件 / 残余风险 |
| --- | --- | --- |
| J-1 | **是**（字面，macOS 实测） | V9 的 `C` 符号：集合相等断言会让它红，须 D39-8 把非 `pub` 全局 `static` 化；不得 allowlist |
| J-2 | **条件成立** | macOS 成立；Linux 的 `-Wl,--localize-hidden` 未实测 → Linux 标 `skip`，未测前不得发密封形态 |
| J-3 | **是** | 合并前 external、合并后 local；`__ct_init` 保留（V8/V14，C §8.3 待复跑） |
| J-4 | **口径依赖** | 实现侧 2 文件 60–90 行 ≤120；若按判决判 B 的「范围口径」（是否改冻结卡/夹具重写），C 同样改 O1/§3.2/R5 → **与 B 同罪**。请裁判统一口径，不能对 B 用宽口径、对 C 用窄口径 |
| J-5 | **是** | 本轮补了确定性（E1-C1）与警告处置（E1-C2）；Linux 仍 `skip` |

**Linux 未测是否致命？——不是设计阻断，是发布阻断。** 理由：
1. C 已有 `--no-seal` 逃生门 + 硬错不默绿（C §3.3、§6），Linux 未测时只能发 `--no-seal`，不会把「非 ABI 洁净」伪装成洁净；
2. `--localize-hidden`/`--retain-symbols-file` 是 GNU ld 的既有选项，未验证不等于不可行；按 C §8.1 的候选顺序 + `nm` 集合断言兜底，失败模式可观测；
3. 判决前置条件 2 已要求「Linux 分支必须实测通过；未实测前 Linux 不得发布密封形态」——C 的评审结论应与此一致：**macOS 可采纳，Linux 待实测**。
4. 若用户要求「两平台同时默认密封」，则 Linux 实测成为开工前置，不是 C 的设计缺陷。

## 5 建议的采纳条件（4 条，缺一不可）

1. **卡面改动写全**：O1 不变，但 §3.2（`:116`）、R5（`:162`）、D39-5、O3 边界、E39-2/E39-5 按 C §7 一并改，**经用户批准**；C §1 的「满足 O1」措辞改成「O1 不变、§3.2 随卡改」。
2. **警告处置定案**：`-nostdlib` 进 §3.2，p39 夹具断言 `cc -r` 的 stderr 为空；禁止用 `-Wl,-w` 吞警告。
3. **Linux 实测 + `skip` 语义**：Linux 未测前只发 `--no-seal` 并在 `.abi.h`/文档标注「非 ABI 洁净」；`--no-seal` 的允许集合必须绑 `ABI_VERSION`（C §4.2 已是此意）。
4. **J-4 口径裁定**：裁判在 `verdict.md` 或评审结论里写明 J-4 计不计卡面/夹具；否则 C 与 B 的 J-4 结论不可比。

> 自评：C 在 J-1/J-3/J-5 上已用实测站住，J-2 的真实增量（同一 `cc`）值得保留；我唯一的实质异议是 **J-4 口径不一致**与 **O1/§3.2 表述**，都不是否决项。若裁判接受上述 4 条，我作为原提案人**支持采纳 C**。
