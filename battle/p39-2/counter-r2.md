# battle/p39-2 反证清单 r2（REQ，第 2 轮交叉质证）

> 已读 `battle/p39-2/claim.md`（362 行）。本轮只做三件事：①逐条回应其原文；②补 1 条新 E1 + 1 条新 E2（不重复 T2）；③明确认输/不认输，并回答「B 要整档合并且 Linux 未实测，是否仍主张 B 优于 A」。
> 证据环境同 T2：HEAD `ac040d1`，macOS arm64 / Apple clang 21 / llvm-nm / `ld` ld-27106.1；仓内零改动，本文件是唯一写盘产物。

## 1 逐条引用与回应

### 1.1 引 `claim.md:20`（§1.1 第 1 条）

> 「导出定义注入 `visibility("default")`，中间对象以 `-fvisibility=hidden` 编译（O3）；」

**回应：这一步对静态归档是**零效果**，主张席自己的 E1.2（`claim.md:212-228`）与本席 T2 E1-3 都实测过。** 我 T2 还多测了一步：`-fvisibility=hidden` 编译出的 `libhid.a`，消费者照样链接 `_Person_Greeter_vtable` 成功（`hidden-misuse link rc=0`）。

所以 A 的真实机制只有 `expected.nm` 一件，第 1 条不构成机制。**这一点我认（visibility 锁不住），但它对 A 不利**：A 的立论被削成「靠 test/ 夹具看着」，而夹具不是消费者契约。主张席在 `claim.md:29` 引 D39-5 的原文恰好自证：「静态归档无法靠 visibility 藏符号，**只能**锁快照」——「只能」是待证前提，不是理由；E1-r2 与 T2 E1-6/7 表明 `ld -r`+`nmedit` 在 macOS 默认工具链里可用。

### 1.2 引 `claim.md:78`（§2 J-3 细化）

> 「B 唯一可行做法是先 `ld -r` 把全档合成一个可重定位对象再本地化——这会：1. 让 `ar t` 从 7 个成员变成 1 个（实测 3→1），与 O1「逐单元 `.o`」和 D39-3 的产物形态冲突；」

**回应：前半句成立，我认；后半句把它算作「B 不成立」不成立。**

- **成立**：逐单元本地化会断链（我方 T2 E1-5 也有 `Undefined symbols: _Dog_Speak_vtable`），要 J-1 字面干净就必须整档合并，`ar t` 从 N→1，与 O1/D39-3 的产物形态冲突。这是 B 的真实成本，我不粉饰。
- **不成立**：①O1 的「逐单元 `.o`」是构建产物/调试粒度，不是消费者契约；改它是一次明确的**产品决策**（O1 与 D39-3 各一行），不是 ABI 不可能；②若 O1 不可动，§7.10 的出口是 C（保留逐单元 `.o` + 在 `.abi.h` 声明「允许的 `nm` 面」+ `ABI_VERSION` 随该面变化），**不是**判 A 成立；③数字有水分：`claim.md:146-154` 的 `/tmp/libbox.a` 含 `main.o`，而 L39-3（`docs/design/phase39-draft.md:136`）明令 `--lib` 不得含 `main`——那份归档不是合法的 `--lib` 产物，「7→1」应改按合法库复测（同源 split 形状是 3→1，我 T2 E1-6 复现的也是 3 单元）。

### 1.3 引 `claim.md:342-343`（§7 回应 1、2）

> 「`nm -m` 里被本地化的符号仍以 `non-external (was a private external)` 留在归档里，调试者/`nm` 仍看得见；真正的 ABI 面是 `<base>.abi.h`……B 多买的只有「误链」这一种情况。」

**回应：「看得见」是工具输出，「链得上」才是 ABI（J-1 原文）；而 B 多买的**不止**误链——它买的是「消费者不能静默替换库内部实现」。见 E1-r2。**

## 2 E1-r2（新增，不重复 T2）：符号抢占 / 静默替换

A 只把风险描述成「消费者主动声明内部符号去误用」（`claim.md:283` A3）。真实风险更低门槛：**消费者只要碰巧定义了同名全局函数（不必 include 任何头、不必知道库的存在），库内部调用就被替换，输出改变，而归档字节与 `nm -g` 完全不变——`expected.nm` 零告警。** `expected.nm` 断言的是归档自己的符号表，抢占发生在消费者链接期，门禁看不见。

夹具（`/tmp/p39r2/lib2/`，均来自 HEAD `ct` 的 `--emit-c` 产物）：

```console
$ cat helper.h.ct            # 库内部单元：pub 以便兄弟单元 import，但不是根单元，故不进 .abi.h（D39-2）
pub int helper(const char *s) { int n = 0; while (s[n]) n++; return n; }
$ cat api.h.ct               # 根单元，唯一导出面
import helper;
pub int api(void) { return helper("abc"); }
$ /tmp/p39head/ct build --emit-c -I . api.h.ct --outdir out --cc true
$ for c in out/*.c; do cc -std=c99 -I out -c "$c" -o "${c%.c}.o"; done
$ nm -g --defined-only out/*.o
out/api.o:    0000000000000000 T _api
out/helper.o: 0000000000000000 T _helper
```

A 形态（原样 `ar`，消费者「无辜」地定义了同名 `helper`）：

```console
$ cat cons_i.c
#include <stdio.h>
int helper(const char *s) { (void)s; return 999; }   /* innocent-looking name */
int api(void);
int main(void) { printf("api=%d\n", api()); return 0; }
$ ar rcs libapi2.a out/api.o out/helper.o
$ cc -std=c99 cons_i.c libapi2.a -o interposed      # link rc=0
$ ./interposed
api=999
```

不抢占时 `api=3`。抢占时 `api=999`：**库的行为由消费者的命名空间决定**，链接不报错、`expected.nm` 不变、文档写「非 ABI」也救不了。

B 形态（合并 + 本地化）下同一消费者：

```console
$ ld -r -exported_symbols_list exp.txt out/api.o out/helper.o -o merged.o   # exp.txt = _api
$ nm -g --defined-only merged.o
0000000000000000 T _api
$ nm merged.o | grep helper
000000000000001c t _helper          # 已本地化，消费者不可定义同名符号来替换
$ ar rcs libmerged2.a merged.o
$ cc -std=c99 cons_i.c libmerged2.a -o fixed && ./fixed
api=3
$ cc -std=c99 cons_ok2.c libmerged2.a -o ok2 && ./ok2
api=3
```

**这条同时打两面**：①A 的「快照 + 文档」对抢占零覆盖（归档没变，门禁不可能红）；②它证明 B 的价值不是「误链可发现」的等价物，而是**不可被抢占**——这是 A 用任何快照都买不到的性质。

## 3 E2-r2（新增锚点，未在 T2 使用）

| # | 锚点 | 内容 | 方向 |
| --- | --- | --- | --- |
| E2-r2-1 | `docs/design/phase39-draft.md:62`（D39-8） | 「`--lib` 下非 `pub` 顶层函数与全局一律发射 `static`……`static` 后才不会混进 `nm -g`」 | 利于己方：卡片**自己**把「不混进 `nm -g`」当目标，A 的「接受符号面」与 D39-8 的同一目标自相矛盾；且 D39-8 只覆盖非 `pub`，覆盖不了 std 的 `pub` 内建（`str_len`）与 vtable——正是 E1-r2 的抢占面 |
| E2-r2-2 | `docs/design/phase39-draft.md:44`（D39-6） | 「不导出按值 struct / union：`.abi.h` 只放不透明前置声明」 | 利于己方：`claim.md:342` 说「真正的 ABI 面是 `.abi.h`」，但 `.abi.h` 的不透明前置并没有界定可链接面——E1-r2 的 `helper(const char*)` 与 `Str` 都是按值/指针可直接伪造的；不透明只挡「无法编译」，不挡「同名替换」 |
| E2-r2-3 | `battle/p39-2/question.md:7` | 「PH-39 D39-5 选 A……**未过庭**」 | 利于己方：`claim.md:34` 称「A 不是新方案，是卡上已有的裁决」——被审对象不能当理由；D39-5 恰恰是本庭要审的未决项（循环论证） |

## 4 明确认输 / 不认输

**我承认对方成立（不再争）：**

| # | 对方主张 | 我方立场 |
| --- | --- | --- |
| C-1 | J-1 按**字面**归 B、A 过不了（`claim.md:269` 自认，我方 T2 E1-2 已证） | 成立。A 的 J-1 不成立，这是本庭的硬事实 |
| C-2 | macOS 默认无 `objcopy`/`llvm-objcopy`（`claim.md:100-101`） | 成立，与我 T2 E1-7 一致 |
| C-3 | **Linux 分支是两套命令、非「同一套命令」**（`claim.md:69`） | 成立。我本机不能实测 Linux，只能按 J-5 写 `skip`；按严格读，B 的 J-2 不过 |
| C-4 | 逐单元本地化断链，J-1 干净必须整档合并，`ar t` N→1，与 O1/D39-3 冲突 | 成立（我方 T2 E1-5 独立复现同一断链） |
| C-5 | A 的 `expected.nm` 能让「内部符号改名」在 CI 先红 | 成立，但只对「改名」这一类 |

**我不认（并给出反证）：**

| # | 对方主张 | 反证 |
| --- | --- | --- |
| N-1 | 「B 多买的只有误链」`claim.md:343` | E1-r2：B 买的是**抗抢占**；A 对抢占零检测（归档不变，快照必绿） |
| N-2 | 「visibility 锁不住 ⇒ 只能锁快照」`claim.md:29` | 假二选一：`ld -r -exported_symbols_list` / `nmedit -s` 在 macOS 默认工具链实测可用（T2 E1-6、E1-r2） |
| N-3 | 「J-1 应按目标读」（`claim.md:56-64`） | `question.md:18` 的通过方式明写 `nm -g --defined-only` 只剩导出函数；改读法是改判据，须走 §7.10，不是主张席自选。若裁判改读法，等于把 A 的 J-1 判据废掉后判 A 成立——这违反 §7.9「逐条判据二元判定」 |
| N-4 | 「冻结卡已裁决」`claim.md:34` | `question.md:7` 写明 D39-5「未过庭」；本庭就是审它，不能拿它当论据 |
| N-5 | 「B 把开发者可见与可链接混为一谈」`claim.md:342` | 恰好相反：**可链接**才改变行为（api=999）；`non-external` 的本地符号链不上，正是 B 的实现 |

## 5 回答：整档合并 + Linux 无法实测，是否仍主张 B 优于 A

**主张：在「内部符号怎么处理」这个争点上，B 优于 A；在代价上 A 优于 B。两者不能相加成「A 成立」。**

理由按判据拆开：

- **J-1（ABI 洁净）**：B（合并 + 本地化）实测满足；A 不满足（T2 E1-2/E1-3、claim 自认）。**B 胜。**
- **J-3（静态链接语义不变）**：B 合并后消费者链接运行正常（T2 E1-6 `woof 7`；E1-r2 `api=3`），且不再被抢占；A 的「语义不变」成立，但「语义可被消费者改写」也是事实。**B 胜（含抗抢占），A 的合规性靠运气。**
- **J-2（同一套命令）**：A 胜，B 不过。**A 胜。**
- **J-4（成本 ≤2 文件 ≤120 行）**：A 胜（2 文件 40–45 行）；B 我估 35–45 行代码 + O1/D39-3 各 1 行改 + 平台分支，但**未计**合并形态带来的夹具/文档改写，按上限取仍可能逼近 120。**A 胜，但差距是「预算内/预算边缘」，不是「可行/不可行」。**
- **J-5（可复现）**：A 的 `expected.nm` 可复现但**覆盖不了抢占**；B 的 Linux 分支本席 `skip`，按 J-5 必须标 skip 而非默绿。**各有缺口，不能判 A 单方成立。**

**条件化结论（本席立场）**：

1. 若允许把 O1/D39-3 的「逐单元 `.o`」改为「归档成员 1 个合并对象」或允许 C 变体（逐单元保留 + `.abi.h` 声明允许面 + `ABI_VERSION` 绑定），**B 优于 A**，我主张 B；
2. 若 O1/D39-3 不可动、且 Linux 分支在 CI 上无法实测，则 A 与 B **都不满足全部判据**——此时按 §7.9 应判 `undecidable` 并走 §7.10 出 C（A 的快照 + 条件化本地化），**不得判 A `upheld`**。主张席自己在 `claim.md:61` 也承认字面读「两案同时判死」，其出口是 `undecidable`，不是「A 成立」；
3. 无论走 1 还是 2，A 的 `expected.nm` 只能作为**回归夹具**保留，不能作为「ABI 洁净」的举证——E1-r2 已证它在抢占面前恒绿。

**本席自认的最弱处（本轮更新）**：B 在 macOS 的唯一实测形态需要整档合并（与 O1 冲突），而 Linux 的 `objcopy --keep-global-symbol` 我**没有实测**，只有书面推断；此外我在 T2 的 B 成本估计（35–45 行）偏乐观，主张席按 150–220 行估，差异在「是否把合并形态的夹具/文档改写计入」——这一点上他的数字比我的更接近实情。
