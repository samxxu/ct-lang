# battle/p39-2 主张书（第 2 轮交叉质证）— A 的修订与止损

> 立场：仍代表 A（不做链接期本地化），但**本轮先认账再修**：J-1 按字面归 B，不再争；A 的唯一生路是把「快照」从测试夹具升级为**随库发布的、消费者可见的允许集合**，并绑 `ABI_VERSION`。若裁判拒绝该修订或坚持字面 J-1，则 A 应 `rejected`，请按 §7.10 出 C，而不是直接宣布 B 成立。

## 0 本轮结论（先看这段）

| 判据 | 本轮判定 | 说明 |
| --- | --- | --- |
| J-1 | **B 成立（字面）**；A 仅在「目标读 + 发布允许集合」修订下成立 | T1 的 A3 与 counter F-1 同向，我不再回避 |
| J-2 | 宽松读**双方都过**；严格「同一套命令」读 A 过、B 不过 | counter 的宽松解读我接受；J-2 不再是 A 的独占优势 |
| J-3 | **B 成立**（合并形态），A 也成立 | 本轮新测：`ld -r` 保留 constructor，B 的合并形态不破坏 `__ct_init`；J-3 不再是 A 的独占优势 |
| J-4 | **双方都在预算内**（B 估算 35–45 行 ≤120） | J-4 不能支撑 A 单独胜出；B 的隐性成本是改 O1 冻结条款与重写夹具，非行数 |
| J-5 | A 略优（同一命令、归一化后单快照；B 的 Linux 分支只能 `skip`） | 不足以单独支撑 A |

**一句话**：J-2/J-3/J-4 已不足以支撑 A 单独胜出；A 的剩余支撑只有 J-5 的边际优势与「B 需改冻结卡 O1/D39-5」这一变更控制理由，后者不是 J-1…J-5 里的判据。**若裁判按字面 J-1 + 宽松 J-2，结论应是 B 成立**；若裁判按字面 J-1 + 严格 J-2，则两案都不满足全部判据，应 `undecidable` → §7.10 出 C。

---

## 1 逐条引用反对席原文并回应（§7.7 E5）

### 1.1 「消费者可链接内部 vtable」——**成立，我接受，并据此改 A**

> counter.md:78：「消费者不仅链接成功，还**复刻了内部 vtable 布局并成功派发**。这是「承诺 ABI 面只有 `.abi.h`」的直接反例：真实的符号面 ⊋ `.abi.h`。」（E1-2，counter.md:58-78；另见 F-1，counter.md:25、:208、:243）

**回应（认账）**：成立，与我在 T2 的 A3（`nm` 暴露非 ABI 符号、消费者可自行声明后链接）完全同向。我不再主张「A 天然不可误用」。

**但 counter 的推论「A 的 J-1 直接不成立」只对字面 J-1 成立。** counter 在 :208 批评 A「两头都占：宣称锁定，实际只锁门禁」——这条批评也成立，且正是 A 必须修的：
- A 的修订（A′）：把 `expected.nm` 从 `test/modules/p39_lib/` 的夹具升级为**随库发布的 `<base>.nm`**（或写进 `<base>.abi.h` 的注释性允许集合），并让 `<BASE>_ABI_VERSION` 的取值覆盖「允许集合」的哈希/条目数；
- 这样「符号面 ⊋ `.abi.h`」变成「符号面 = `.abi.h`（导出）+ `<base>.nm`（已声明的允许集合）」，消费者**可读**，符号面扩大必须动 `ABI_VERSION` → 不再「只锁门禁」。
- 修订后 A 满足 J-1 的**目标**（ABI 面被定义、被发布、被版本化），仍不满足 J-1 的**字面**（`nm -g` 仍多出符号）。**字面读下我承认 A 失败。**

### 1.2 「`ld -r` 单对象方案」——**J-3 归 B，我接受；但它拿走了 O1**

> counter.md:149-172（E1-6）：「归档只含 1 个成员……」；counter.md:172：「vtable 变 `d`（本地），导出面只剩两个 `T`……**J-1 与 J-3 同时满足**」；counter.md:229（E4）：「归档只含 1 个合并 `.o`，**与 O1 的「逐单元 `.o`」（`docs/design/phase39-draft.md:36`）冲突**；要么改 O1，要么每单元再存一份未合并副本（成本翻倍且符号面回到 A）」

**回应**：
1. **J-3 归 B，我接受。** 而且我本轮新测了 counter 没测的一项：`ld -r -exported_symbols_list` 会不会把 constructor 一起藏掉。结果是**不会**（见 §2 E1-r2-b，`__mod_init_func` 两条都在，运行输出 `A-init`/`B-init`）。所以 B 的合并形态不破坏 `__ct_init`，J-3 不再是我的论据。
2. **但 counter 自己写明 B 与 O1 冲突。** 这不是「B 的实现细节」，而是**改冻结卡的交付物形态**（`docs/design/phase39-draft.md:36` 的 O1 明文「逐单元 `.o`」）。按 6.2/6.6 T-6，这属于冻结判据变更，需要重开卡或本庭明确裁决生效范围；J-4 的「35–45 行」估算没有把「改 O1 + 重写 p39 夹具 + counter 自述的每成员清单（E1-7，counter.md:194）」计入。
3. **B 的「硬保证」仍然依赖 `nm` 断言。** counter 自认 `ld -r` 对清单里不存在的符号**静默成功**（counter.md:194），所以 B 末尾必须再跑一次 `nm -g --defined-only` 自校验（counter.md:231）。也就是说，B 的最终验收与 A 用的是**同一个 `nm` 面**，区别只在「本地化后再断言」还是「不本地化直接断言」。这削弱了 B「物理上不可能误链」的收益叙事：它对**归档成员**成立，对**归档外的消费者声明**不成立（消费者仍可自己 `extern` 一个已被本地化的名字吗？不能——但 counter 的 F-1 反例正是 A 不本地化才成立；B 靠本地化消除它，这点我承认）。
4. **结论**：J-3 是 B 的胜项，不是 A 的；A 不再用 J-3 抗辩。

### 1.3 J-2 ——**接受 counter 的宽松解读，J-2 不再是 A 的独占优势**

> counter.md:244：「**J-2 的严格形态 B 确实不满足**（同一套命令），但 J-2 的通过方式写的是「`command -v` + 两平台命令」，即允许两平台命令名不同只要默认工具链可用；这一点应由裁判解释，不由本席裁。」

**回应**：这个解释合理，我接受宽松读。于是：
- 宽松读：B 过（macOS `nmedit` 实测存在，本轮 E1-r2-a 确认 `/usr/bin/nmedit`；Linux `objcopy` 未实测、只能 `skip`）。
- 严格读（同一套命令）：B 不过、A 过。
- 两种读法下 J-2 都**不构成 A 的独占优势**（宽松读两边都过）。T2 我拿 J-2 当主论据之一，本轮降级为「仅在严格读下有效」。

### 1.4 F-3（快照只是夹具）——**成立，A′ 的修订就是为它写的**

> counter.md:110：「`expected.nm` 只会让下一次 `nm` 差异变红→改夹具即绿，**没有任何消费者可见的契约阻止符号面扩大**，也不触发 `ABI_VERSION`。」

**回应**：成立。A′ 用「发布 `<base>.nm` + `ABI_VERSION` 绑定」来补；若裁判认为「发布允许集合」仍不算 ABI 承诺（消费者仍可误链 `.nm` 之外的符号？不，`.nm` 是全集声明），则退到 ABI_VERSION 绑定。**我不再声称 T2 原样的 A 已锁住消费者契约**——那一点 counter 说对了。

### 1.5 F-4 / P-5（跨平台快照）——**counter 打的是稻草人：卡上已规定归一化**

> counter.md:218（P-5）：「`expected.nm` 在 macOS 与 Linux 不能是同一份字节：Mach-O 带 `_` 前缀、排序与 `llvm-nm`/GNU nm 不同。」

**回应（新 E2 锚点，见 §3）**：`docs/design/phase39-draft.md:127` 已经写死「`nm -g --defined-only` **归一化（去前导 `_`）**后的集合必须逐行等于 `test/modules/p39_lib/expected.nm`」。P-5 比的是「同一份字节」，而卡要求的是「归一化后的集合」——两者不是同一命题。本条应撤回或降级为「归一化脚本需覆盖排序差异」，那是 2–3 行 `sort`，不是 J-5 的失败。

### 1.6 counter 的 F-6 与我 T2 的「macOS 无 objcopy」

> counter.md:30（F-6）：「macOS 有 `ld -r -exported_symbols_list` 与 `nmedit -s`，均为系统自带」；counter.md:177-183：`objcopy`/`llvm-objcopy`/`gobjcopy` 均 `(absent)`，`nmedit` = `/usr/bin/nmedit`。

**回应**：**成立，我撤回 T2 中「macOS 默认没有本地化工具」的表述**（准确说法是「没有 `objcopy`/`llvm-objcopy`，但有 `nmedit` 与 `ld -r`」）。T2 的 E1.0 只证明了前者，我把它外推成后者，是过度解读。

---

## 2 新增 E1（本轮，不重复 T2）

### E1-r2-a：`nmedit` 存在（修正 T2 的过度解读）

```console
$ command -v nmedit
/usr/bin/nmedit
```

结论：macOS 的系统自带本地化工具是 `nmedit`（不是 `objcopy`）。counter 的 F-6 成立。

### E1-r2-b：`ld -r -exported_symbols_list` 保留 constructor（新测，B 的 J-3 证据）

```console
$ cd /tmp/p39r2
$ cat a2.c   # __attribute__((constructor)) void a_init(void){puts("A-init");}  + int a_fn(void){return 1;}
$ cat b2.c   # __attribute__((constructor)) void b_init(void){puts("B-init");}  + int b_fn(void){return 2;}
$ cc -c a2.c b2.c
$ printf '_a_fn\n_b_fn\n' > exp2.txt
$ ld -r -exported_symbols_list exp2.txt -o merged2.o a2.o b2.o
$ nm -m merged2.o | grep -i init
0000000000000000 (__TEXT,__text) non-external (was a private external) _a_init
0000000000000024 (__TEXT,__text) non-external (was a private external) _b_init
0000000000000058 (__DATA,__mod_init_func) non-external [no dead strip] ltmp2
0000000000000060 (__DATA,__mod_init_func) non-external [no dead strip] ltmp2
$ cc m.c merged2.o -o m2 && ./m2
A-init
B-init
run rc=0
$ nm -g --defined-only merged2.o
000000000000001c T _a_fn
0000000000000040 T _b_fn
```

结论：被 `-exported_symbols_list` 本地化的 constructor 仍在 `__mod_init_func` 里、仍运行。**B 的合并形态不破坏初始化**，J-3 归 B，我不再质疑。这条证据**不利于 A**，我照样贴出来。

---

## 3 新增 E2（本轮，不重复 T2）

| # | 锚点 | 内容 | 方向 |
| --- | --- | --- | --- |
| E2-r2-1 | `docs/design/phase39-draft.md:127` | 「`nm -g --defined-only` **归一化（去前导 `_`）**后的集合必须逐行等于 `test/modules/p39_lib/expected.nm`」 | 利于 A：卡已规定归一化，counter 的 P-5「同一份字节」是稻草人；跨平台单快照可行 |
| E2-r2-2 | `docs/design/phase39-draft.md:126` | 「trait vtable 仍 external（跨单元装箱要用），不加 attribute → hidden；它**不是** ABI，由 `expected.nm` 快照锁定」 | 利于 A：A 是冻结卡上的既定方案；B 必须改这一行与 O1（:36），属冻结条款变更，不是实现细节 |
| E2-r2-3 | `docs/design/phase39-draft.md:184` | E39-9 / E39-6 只查 `.abi.h` 与 `_iface`/`_vtbl` 命中 0，**不查 `nm` 面** | 不利于 A：J-1 的字面要求没有任何既有门禁承担，A′ 必须新增 nm 门禁（我接受） |

（T2 的 A1/A2/A3/A4 仍有效；本轮不重复。）

---

## 4 承认与止损（明确回答「J-2/J-3/J-4 是否仍足以支撑 A」）

- **J-1**：字面归 B，**A 不再抗辩**。A 只在「目标读 + A′ 发布允许集合 + ABI_VERSION 绑定」下成立。
- **J-2**：宽松读双方都过（B 用 `nmedit`/`ld -r`、A 用 `nm`）；严格读 A 过。**不足以支撑 A 单独胜出。**
- **J-3**：B 的合并形态成立（本轮 E1-r2-b 补强），A 也成立。**不足以支撑 A 单独胜出。**
- **J-4**：B 估算 35–45 行 ≤120，**也在预算内**；A 2 文件 40–45 行。**不足以支撑 A 单独胜出。**（B 的隐性成本是 O1 冻结条款与夹具重写，属变更控制，不属 J-4 的行数口径。）
- **J-5**：A 略优（同一命令、归一化后单快照；B 的 Linux 分支只能 `skip`），**仅此一项不够。**

**因此按 §7.9 的严格字面：A 不满足 J-1 → A 不能 `upheld`。** 若裁判采严格 J-2，B 也不满足全部判据（Linux 未实测、跨平台命令不同）→ `undecidable`。

## 5 请求裁判（§7.10）

1. **先裁定 J-1 的读法**（字面 / 目标），并写入 `verdict.md`；这决定本庭是「B 成立」还是「出 C」。
2. 若 A 被判 `rejected`，请按 §7.9 原文「`rejected` 不等于反对席方案成立」写明 **B 的生效范围**：B 需改 `docs/design/phase39-draft.md:36` 的 O1（逐单元 `.o`）、:126 的 vtable 锁定条款，并把 Linux 分支标 `skip`（counter 自认，counter.md:234）。
3. 若裁判认为 A′（发布 `<base>.nm` + `ABI_VERSION` 绑定 + 归一化 nm 门禁）成立，则 A 可在**目标读**下 `upheld`；请把 A′ 的三项作为 A 的生效条件写进判决，而不是按 T1 原样记录。
4. 若两案都不满足全部判据，请按 §7.10 出 C：**A′ 的已声明允许集合 + B 的条件化本地化**（mac `nmedit`/`ld -r`，Linux `objcopy`；保留逐单元副本或改 O1），并写明「ABI 洁净」在 `.abi.h`、`<base>.nm`、`nm` 三处的定义。

> 自评（本轮最弱处）：我承认了 T2 的 J-1、J-2（宽松读）、J-3、J-4 四项中的三项半；A 现在只剩 J-5 与「B 改冻结卡」的变更控制。若裁判不采目标读，A 应死，我请求的是出 C 而不是硬保 A。
