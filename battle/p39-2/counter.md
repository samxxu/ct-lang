# battle/p39-2 反证清单（反对席 REQ）

> 反对 **A**：接受 vtable / std 内建符号留在 `nm -g`，用 `expected.nm` 快照锁定并文档注明「非 ABI」。
> 本席只证伪，不替 B 背书完整方案；B 的可行性探针用于否定「B 平台成本不可接受」这一前提。

## 证据环境（可复跑）

| 项 | 值 |
| --- | --- |
| HEAD | `ac040d1`（2026-11-13），干净源码 `/tmp/p39head/src`，编译器 `/tmp/p39head/ct` |
| OS / 工具链 | macOS arm64，Apple clang 21.0.0，`ld` ld-27106.1，`nm` = llvm-nm，`ar` = /usr/bin/ar |
| 工作目录 | 全部证据在 `/tmp/p39x`（`greet.h.ct` = 单单元库；`sp2/` = 跨单元装箱，源自我仓库 `test/modules/split` 的 shapes/impl_dog + 新增 `box.h.ct`） |
| 未触碰 | 仓库源码/文档零改动；仅本文件 |

复跑骨架（HEAD 干净可重跑）：

```bash
mkdir -p /tmp/p39x && cd /tmp/p39x        # 用下文各段给出的 .ct 与命令，逐段重跑
```

## 1. 反证清单：A 的失效条件（逐条可观测）

| # | A 的失效条件（一旦成立，A 即不成立） | 观测方式 | 本席状态 |
| --- | --- | --- | --- |
| F-1 | 存在**不在 `.abi.h`** 里的全局符号，消费者能直接链接并运行——即「ABI 面 = `.abi.h`」不成立 | 消费者 C 显式 `extern` 该 vtable 并调用 | **已观测成立**（E1-2） |
| F-2 | `visibility(hidden)` 能把这些符号移出 `nm -g`，使 A 的「其余标 hidden」变成实际隔离 | `cc -fvisibility=hidden` 后重跑 `nm -g` 与消费者链接 | **已观测为否**（E1-3）：符号仍为 `D`/`T`，消费者仍链接成功 |
| F-3 | std 升级（给 `lib/std/Str.h.ct` 增加一个 `pub` 函数）**不改变**归档符号面，或必被 `.abi.h`/`ABI_VERSION` 变化捕获 | 对比两次 `.o` 的 `nm -g`；`expected.nm` 是否只是测试夹具 | **已观测为否**（E1-4）：符号面随 std `pub` 函数线性增长，且只落在 `test/` 的夹具里；改夹具即绿 |
| F-4 | `expected.nm` 能作为跨平台单一契约：macOS（llvm-nm，符号带 `_` 前缀）与 Linux（GNU nm，无前缀）输出一致 | 同一 `.o` 在两平台 `nm -g` 的输出 | **本席判定为否，但仅 macOS 实证**（E2-3）；Linux 侧为 `skip`，不作胜证 |
| F-5 | 当「逐单元 `.o`」保留时，vtable 不进入任何**跨单元**引用，所以它确实只算内部细节 | `nm -u` 逐个 `.o` 查未定义符号 | **已观测为否**（E1-5）：`box.o` 有 `U _Dog_Speak_vtable`，跨单元装箱真实依赖它 |
| F-6 | B 的平台成本不可接受：macOS 没有可用本地化手段，只能引入第三方工具 | `command -v objcopy`、`ld -r`、`nmedit` 实测 | **已观测为否**（E1-6/7）：macOS 有 `ld -r -exported_symbols_list` 与 `nmedit -s`，均为系统自带 |

**结论式**：F-1、F-2、F-3、F-5 已由原始输出证实 → 按 §7.9，A 的主张不成立（`rejected`），除非证据席能推翻其中任一条。

## 2. E1：命令 + 原始输出

### E1-1 库单元（trait + vtable + 一个 `pub` 函数）

`/tmp/p39x/greet2.h.ct`：

```c
#include <stdio.h>
pub trait Greeter { void greet(); }
pub struct Person { char *name; } use Greeter;
impl Greeter for Person { void greet() { puts(self->name); } }
pub void run_it(void) { Person p; p.name = "ok-from-lib"; Greeter g = p; g.greet(); }
```

```console
$ /tmp/p39head/ct build --emit-c greet2.h.ct --outdir out3 --cc true
$ cc -std=c99 -I out3 -c out3/greet2.c -o greet2.o
$ nm -g --defined-only greet2.o
0000000000000088 D _Person_Greeter_vtable
0000000000000030 T _run_it
```

`_Person_Greeter_vtable` 是 **D（已定义、全局）**，不是 `t`/`d`；它不在 `<base>.abi.h` 的发射集合里（`docs/design/phase39-draft.md:118` 明文「不出现 `_iface` / `_vtbl`」）。

### E1-2 消费者直接链接「非 ABI」vtable 并运行（F-1）

```console
$ cat consumer.c
#include <stdio.h>
struct Person { char *name; };
struct Greeter_vtbl { void (*greet)(void *); };
extern struct Greeter_vtbl Person_Greeter_vtable;   /* NOT in .abi.h */
int main(void) {
    struct Person p = { "linked-against-internal-vtable" };
    Person_Greeter_vtable.greet(&p);
    return 0;
}
$ ar rcs libgreet.a greet.o && cc -std=c99 consumer.c libgreet.a -o misuse
link rc=0
$ ./misuse
linked-against-internal-vtable
run rc=0
```

消费者不仅链接成功，还**复刻了内部 vtable 布局并成功派发**。这是「承诺 ABI 面只有 `.abi.h`」的直接反例：真实的符号面 ⊋ `.abi.h`。

### E1-3 hidden 不是隔离（F-2）

```console
$ cc -std=c99 -fvisibility=hidden -I out3 -c out3/greet2.c -o greet2.hid.o
$ nm -g --defined-only greet2.hid.o
0000000000000088 D _Person_Greeter_vtable
0000000000000030 T _run_it
$ ar rcs libhid.a greet2.hid.o && cc -std=c99 misuse2.c libhid.a -o hid_misuse
hidden-misuse link rc=0
```

`hidden` 只影响动态导出，对静态归档的全局符号表与解析**没有任何作用**；A 在 `docs/design/phase39-draft.md:126` 记的「不加 attribute → hidden」不构成隔离，不能拿它当 A 的补偿。

### E1-4 std 的 `pub` 函数是同一类全局（F-3）

```console
$ /tmp/p39head/ct build --emit-c -I /Users/samxx/dsh-ws/ct-lang/lib lib/std/Str.h.ct --outdir out2 --cc true
$ cc -std=c99 -I out2 -c out2/Str.c -o Str.o
$ nm -g --defined-only Str.o | awk '{print $2, $3}' | sort
T _Str_release
T _Str_retain
T _str_c_str
T _str_compare
T _str_concat
T _str_from
T _str_from_len
T _str_len
T _str_slice
```

（`str_from_len`/`str_from` 的 `pub` 声明见 `lib/std/Str.h.ct:33` 与 `:51`。）任何 `--lib` 构建只要把 std 的 `Str` 拉进来，这 9 个全局就进归档，而 `.abi.h` 一个都不会写。`expected.nm` 只会让下一次 `nm` 差异变红→改夹具即绿，**没有任何消费者可见的契约阻止符号面扩大**，也不触发 `ABI_VERSION`。

### E1-5 跨单元装箱真的引用 vtable（F-5）：逐单元本地化会破坏静态链接

用例源自我仓库 `test/modules/split`（`shapes.h.ct` / `impl_dog.h.ct`）加一个装箱单元：

```console
$ cat box.h.ct
import shapes;
import impl_dog;
pub void via_vtable(void) { Dog d = *dog_get(); Speak s = d; s.hi(); }
$ nm -g --defined-only o/*.o
o/box.o:        0000000000000000 T _via_vtable
o/impl_dog.o:   0000000000000050 D _Dog_Speak_vtable
                0000000000000040 T _dog_get
o/shapes.o:
$ nm -u o/box.o
_Dog_Speak_vtable
_dog_get
```

按单元本地化（导出表只留 `_dog_get`）后：

```console
$ nmedit -s exp_only.txt o/impl_dog.o -o o/impl_dog.loc.o   # macOS 等价 objcopy --localize
nmedit impl rc=0
$ nm -g --defined-only o/impl_dog.loc.o
0000000000000040 T _dog_get
$ ar rcs libperunit.a o/shapes.o o/impl_dog.loc.o o/box.o
$ cc -std=c99 cons.c libperunit.a -o perunit
Undefined symbols for architecture arm64:
  "_Dog_Speak_vtable", referenced from:
      _via_vtable in libperunit.a[4](box.o)
ld: symbol(s) not found for architecture arm64
clang: error: linker command failed with exit code 1 (use -v to see invocation)
```

**这条不利于 B 的朴素形态**：逐单元本地化与跨单元装箱不相容（J-3 会红）。也正因为它是真的，A 的「只是内部细节」站不住：归档里必须有它的全局定义，别的单元才链接得到。

### E1-6 macOS 上 B 可行：先 `ld -r` 合并（内部引用就地解析），再本地化

```console
$ ld -r -exported_symbols_list exp_box.txt o/shapes.o o/impl_dog.o o/box.o -o o/merged.o
merge rc=0
$ nm -g --defined-only o/merged.o
0000000000000040 T _dog_get
000000000000004c T _via_vtable
$ nm o/merged.o | grep -i dog
0000000000000000 t _Dog_Speak_hi
00000000000000a0 d _Dog_Speak_vtable
0000000000000040 T _dog_get
00000000000000a8 d _g_dog
$ nm -u o/merged.o
_printf
$ ar rcs libmerged.a o/merged.o
$ cc -std=c99 cons.c libmerged.a -o mergedbin     # cons.c: void via_vtable(void); main 调用它
merged link rc=0
$ ./mergedbin
woof 7
run rc=0
```

vtable 变 `d`（本地），导出面只剩两个 `T`，消费者照常链接、运行、跨单元派发（`woof 7`）。**J-1 与 J-3 同时满足**——这直接否证「B 在 macOS 上做不到」。

### E1-7 工具存在性与失败输出（诚实计分）

```console
$ for t in llvm-objcopy gobjcopy objcopy nmedit; do printf '%-14s ' "$t"; command -v "$t" || echo "(absent)"; done
llvm-objcopy   (absent)
gobjcopy       (absent)
objcopy        (absent)
nmedit         /usr/bin/nmedit
$ xcrun -f objcopy
xcrun: error: unable to find utility "objcopy", not a developer tool or in PATH
$ printf '_no_such_symbol\n' > bad.txt && nmedit -s bad.txt greet.o -o bad.o
/…/nmedit: error: symbols names listed in: bad.txt not in: /private/tmp/p39x/greet.o
_no_such_symbol
rc=1
$ printf '_via_vtable\n_dog_get\n' > exp_box.txt && nmedit -s exp_box.txt o/impl_dog.o -o o/impl_dog.loc.o
/…/nmedit: error: symbols names listed in: exp_box.txt not in: /private/tmp/p39x/sp2/o/impl_dog.o
_via_vtable
rc=1
```

两点如实记录：①macOS **没有** `objcopy`（F-6 的代价面）；②`nmedit` 的清单**必须按对象过滤**，把别的对象的导出名混进去就 rc=1——B 的 macOS 分支需要「每成员一份清单」或对合并后单对象用一份清单。另测：`ld -r -exported_symbols_list` 对清单里**不存在**的符号**静默成功**（rc=0），故校验必须由 `nm` 断言兜底，不能信 `ld` 的退出码。

## 3. E2：`file:line` 锚点（含不利于己方）

| # | 锚点 | 内容 | 方向 |
| --- | --- | --- | --- |
| E2-1 | `docs/design/phase39-draft.md:118` | `.abi.h`「**不出现** `_iface` / `_vtbl` / `Vec_` / `Map_`」 | 利于己方：ABI 头承诺与归档符号面不一致 |
| E2-2 | `docs/design/phase39-draft.md:40` | 「visibility 不改变静态归档的全局符号表……`nm -g` 里仍会看到 trait vtable，它不属于 ABI 承诺」 | 利于己方：卡自己承认符号面 ≠ 导出面，却把「ABI 洁净」留作目标 |
| E2-3 | `docs/design/phase39-draft.md:126` | 「trait vtable 仍 external……由 `expected.nm` 快照锁定」 | 利于己方：锁的是 `test/` 夹具，不是消费者契约 |
| E2-4 | `docs/design/phase39-draft.md:181` | E39-6 判据「原型集合 = 导出集合；`_iface`/`_vtbl` 命中 0」 | 利于己方：门禁只查头，不查 `nm`；J-1 的「ABI 洁净」无门禁承担 |
| E2-5 | `lib/std/Str.h.ct:33`、`:51` | `pub Str str_from_len(...)`、`pub Str str_from(...)` | 利于己方：std 增函数 = 归档符号面扩张源（E1-4） |
| E2-6 | `docs/design/phase39-draft.md:46` | 「v1 只覆盖 macOS/Linux 的 `cc` + `ar`」 | **不利于己方**：B 要多用 `ld`/`nmedit`/`objcopy`，超出 cc+ar 的承诺 |
| E2-7 | `AGENTS.md:391` | 「不引入任何第三方库、构建系统、代码生成脚本」 | **不利于己方**：主张席会据此判 B 越界 |

**为什么仍反对 A**：E2-6/E2-7 约束的是「依赖类别」，不是「符号面欺骗」。`ld`/`nmedit`/`objcopy` 都是 OS 自带工具，既不是第三方库也不是构建系统；而 A 的代价是把「ABI 面 = `.abi.h`」改成「ABI 面 = `.abi.h` + 一串靠测试夹具看着的 vtable/std 符号」，承诺降级发生在**消费者契约**上，不能靠 `expected.nm` 抵。若裁判认为 `.abi.h` 之外的符号完全不算承诺，那 A 就应当**把这句话写进 `.abi.h` 与文档**，而不是用快照暗示「已锁定」——A 现在两头都占：宣称锁定，实际只锁门禁。

## 4. E3：可证伪预测

| # | 预测（若本席成立） | 一次性验证 | 若否证 |
| --- | --- | --- | --- |
| P-1 | 干净 HEAD 上按 §2 复跑 E1-2，链接与运行仍成功（`linked-against-internal-vtable`） | 重跑 E1-1/E1-2 | A 的「不可误用」成立，本席主论点倒 |
| P-2 | 给 `lib/std/Str.h.ct` 加任一 `pub` 函数并重建归档，`nm -g --defined-only` 多出该全局，而 `.abi.h` 与 `<BASE>_ABI_VERSION` **不动**；只需改 `expected.nm` 即可全绿 | 加 `pub Str str_split(...)` 后 diff 两处 | 若 `.abi.h`/版本号随之变化，则 A 的锁不静默，F-3 撤回 |
| P-3 | 按「逐单元 `.o` + 逐单元 `nmedit`/`objcopy` 本地化」实现 B，`test/modules/split` 形状的用例会在**构建期或消费者链接期**报 `_Dog_Speak_vtable` 未定义 | 按 E1-5 复跑 | 若逐单元仍链接成功，说明跨单元引用不存在，F-5 撤回 |
| P-4 | B 若采用「`ld -r` 合并 + 单对象本地化」，归档只含 1 个成员，`nm -g` 恰为导出集合，消费者链接并运行成功 | 重跑 E1-6 | 若失败/运行异常，B 的 J-3 不成立 |
| P-5 | `expected.nm` 在 macOS 与 Linux 不能是同一份字节：Mach-O 带 `_` 前缀、排序与 `llvm-nm`/GNU nm 不同 | 两平台对同一源构建后 `nm -g \| sort` 比对 | 若一致，F-4 撤回（本席已自认只有 macOS 实证） |

## 5. E4：若 A 被判死，B 的最小代价

以 E1-6 实证形态为准：**先合并再本地化**，不是逐单元本地化。

| 项 | 估算 |
| --- | --- |
| 文件 | 2 个：`selfhost/ct-ast/tool/driver/Driver.h.ct`（`--lib` 分支末尾加一步后处理）+ `selfhost/ct-ast/backend/emit/Emitter.h.ct`（导出表/等价的符号清单输出）；落点按 PH-39 实际单元名可 ±1 |
| 行数 | 约 35–45 行：拼 `ld -r` 参数、生成清单、`nmedit`/`objcopy` 调用、`nm` 自校验；≤120 行预算内 |
| 平台分支 | 1 个（macOS `nmedit -s <exports>`；Linux `objcopy --keep-global-symbol=<name>` 逐项或 `--localize-hidden` 配合 hidden attribute）。合并步骤两平台同名：`ld -r`；LOCALIZE 命令不同——**J-2 的「同一套命令」不成立**，只能主张「两平台默认工具链各自可用」 |
| 产物形态变更 | 归档只含 1 个合并 `.o`，**与 O1 的「逐单元 `.o`」（`docs/design/phase39-draft.md:36`）冲突**；要么改 O1，要么每单元再存一份未合并副本（成本翻倍且符号面回到 A） |
| 工具缺失回退 | 工具缺失时**不静默**：`nm -g` 断言失败 → 该平台 `skip` 并打印原因（J-5 语义），或退回 A 并在 `deviation:` 登记「该平台不承诺 ABI 洁净」；不得默认绿 |
| 校验 | 构建末尾跑 `nm -g --defined-only` 断言集合 == 导出集合（不依赖 `ld` 退出码，见 E1-7 的静默成功） |
| 回退 | 删这一个后处理步骤即可回到 A 形态；`git revert` 单提交，不触碰 emitter 的 `.abi.h` 与 `.h` 产物 |

**本席自认的最弱处**：唯一实测可用的 macOS 形态要求合并归档（破坏「逐单元 `.o`」），而 Linux 分支（`objcopy --keep-global-symbol`）**本机无法实测**，只能 `skip`；此外 `ld -r` 对清单里缺失符号静默成功，是 B 的真实失败模式，必须靠 `nm` 自校验兜住。

## 6. E5：预判主张席最强论点（**预判**，非原文）

> **预判**主张席会说：「B 引入平台专用工具，违反 `AGENTS.md:391` 的最小依赖与 `docs/design/phase39-draft.md:46` 的 `cc`+`ar` 承诺；且 J-2 要求同一套命令跨平台，B 做不到；`expected.nm` 已足以锁住回归。」

回应（据实）：

1. **不违反 `AGENTS.md:391`**：该条禁的是「第三方库、构建系统、代码生成脚本」。`ld`（链接器）、`nmedit`（Apple 自带）、`objcopy`（binutils）都是 OS 自带二进制工具，不新增任何需下载/版本钉住的依赖，也不把编译路径改成构建系统。**但**确实超出 `docs/design/phase39-draft.md:46` 的 cc+ar 承诺，这一点我承认，应作为 B 的成本登记，而不是当作 B 的否决理由。
2. **「快照已锁住」是把门禁当契约**：E1-4 证明新增 std `pub` 函数时，只需改 `test/` 夹具即绿，`.abi.h`、`ABI_VERSION`、消费者可见契约全不动。消费者看不到 `expected.nm`——它锁的是仓库回归，不是 ABI 面。
3. **J-2 的严格形态 B 确实不满足**（同一套命令），但 J-2 的通过方式写的是「`command -v` + 两平台命令」，即允许两平台命令名不同只要默认工具链可用；这一点应由裁判解释，不由本席裁。若裁判按最严解释，B 的 J-2 不成立——但**那也不使 A 的 J-1 成立**：E1-2/E1-3 已证 A 无法满足「`nm -g` 只剩导出函数」，A 的 J-1 直接不成立。
4. **两败时按 §7.10 出 C**：可考虑「`.abi.h` 显式声明 `nm -g` 允许集合 + `ABI_VERSION` 随集合变化 + 门禁从 `expected.nm` 升级为导出集合断言」的折中；本席不越权提完整 C 方案。
