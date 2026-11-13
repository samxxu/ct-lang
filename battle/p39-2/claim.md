# battle/p39-2 主张书 — A：不做链接期本地化

| 字段 | 值 |
| --- | --- |
| 席位 | 主张席 ARCH（独立上下文，只代表主张方） |
| 立场 | **A**：静态归档保留 trait vtable、内建 `Str_*` 等 external 符号；用 `expected.nm` 快照锁定非 ABI 符号面；文档注明「非 ABI」 |
| 当前 HEAD | `ac040d1`（2026-11-13） |
| 复现用编译器 | `/tmp/p39head/ct`，`ct v0.37.0`，干净源码 `/tmp/p39head/src` |
| 证据环境 | macOS + Apple clang / `/usr/bin/nm` = **llvm-nm, compatible with GNU nm（Apple LLVM 21.0.0）**；`ar` 为 Apple `ar`；全部实验在 `/tmp`，仓库只读 |
| 禁止触碰 | 未修改仓库任何源码/文档；本文件是唯一写盘产物，另用 `/tmp/p39*` 临时目录 |

---

## 1 方案与 PH-39 D39-5 的对应

### 1.1 A 方案

A 就是**按冻结卡原样执行 D39-5**，不追加任何链接期步骤：

1. 导出定义注入 `visibility("default")`，中间对象以 `-fvisibility=hidden` 编译（O3）；
2. `--lib` 产出的 `lib<base>.a` 里，trait vtable（`_<Struct>_<Trait>_vtable`）与内建 std 单元的实现符号（`Str_retain`、`Str_release`、`str_from` …）**保持 external**；
3. 用 `expected.nm`（`nm -g --defined-only` 的排序快照）把**当前符号面冻住**：任何 internal 符号改名/新增/消失都让 p39 门禁变红，必须人工确认后更新快照；
4. 在 ABI 文档与 `<base>.abi.h` 顶部注明：**只有 `.abi.h` 里的声明是 ABI**，`nm` 能看到的其余符号不属于 ABI 承诺，随时可改。

### 1.2 与 D39-5 的逐字对应

`docs/design/phase39-draft.md:59`：

> `D39-5 | 导出定义注入 visibility("default")，中间对象加 -fvisibility=hidden；符号面用 nm 快照锁定 | 静态归档无法靠 visibility 藏符号，只能锁快照`

- 第 1 句（visibility 注入）→ A 的第 1 条；
- 第 2 句（**nm 快照锁定**）→ A 的第 3 条；
- 「理由」列（静态归档无法靠 visibility 藏符号）→ 这正是 A 的立论：既然 visibility 藏不住，要么接受并锁定，要么引入新的链接期工具；D39-5 明确选了前者。
- 冻结卡 `docs/design/phase39-draft.md:37`（O3 边界）已写明「visibility 不改变静态归档的全局符号表……`nm -g` 里仍会看到 trait vtable，它不属于 ABI 承诺（§3.3、E39-2）」。**A 不是新方案，是卡上已有的裁决。**

### 1.3 B 对冻结卡意味着什么

B（链接期本地化）不是 D39-5 的实现细节，而是**改写 D39-5 的理由列与 O3 边界**：它把「只能锁快照」变成「可以不锁快照，靠链接期工具抹掉」。这需要改冻结的 D39-5 与 §1.3，属卡外新增决策；按 6.2/6.6 T-6，冻结后的决策变更不是「实现选型」，应走本庭或重开卡。

### 1.4 边界（与 question.md 一致）

本庭只裁「已经产生的内部符号怎么处理」，不裁导出集合（B39-1）、不裁 `--lib` 命名与确定性。下文所有「导出面」均指 `dog_get` 这类**已由 D39-2/§3.1 定义的**导出函数，不重新定义它。

---

## 2 逐条判据的主张（J-1…J-5）

| 判据 | 主张 | 依据 |
| --- | --- | --- |
| J-1 ABI 洁净 | **按判据的「目标」读，A 成立；按「手段」字面读，J-1 归 B，我不争** | E1（`nm` 确有非 ABI 符号）、A3/A4 锚点；A 用快照把符号面变成受门禁约束的契约 |
| J-2 平台可移植 | **A 成立，B 不成立** | E1：macOS 默认工具链 **没有 `objcopy`/`llvm-objcopy`**；B 必须 mac 用 `ld -r -exported_symbols_list`、Linux 用 `objcopy --localize-hidden`，**不是同一套命令** |
| J-3 静态链接语义不变 | **A 成立；B 需额外整档重链，且与「逐单元 .o」冲突** | E1：`main.o` 有 `U _Dog_Speak_vtable`；B 若逐成员本地化则断链，只能 `ld -r` 合成单成员归档（实测 `ar t` 3→1） |
| J-4 成本 | **A 成立（2 文件、约 40–45 行、零产物改动）；B 不成立（≥3 文件、>120 行、平台分支 + 工具缺失硬错）** | §6 |
| J-5 可复现 | **A 成立（同一命令 + 一处 `sed` 平台归一）；B 不成立（两种工具、两种语义；本机缺工具时只能硬错或 skip）** | E1 的 `command -v` 与 B 探针 |

### J-1 的读法必须由裁判先定（否则本庭不可判）

J-1 的 ID 写的是「**ABI 洁净**」，通过方式却写成「`nm -g --defined-only` 是否只剩导出函数；若 B 能做到而 A 不能，J-1 归 B」。

- 若采**字面**（`nm` 最小化）：B 赢 J-1——我已在 E1 里用 `ld -r -exported_symbols_list` 复现 B 的 `nm` 只剩 `_dog_get`；
- 但字面读会使 §7.9「满足全部判据」把**两案同时判死**：B 过不了 J-2（macOS 默认工具链无 `objcopy`，且跨平台不是同一套命令），A 过不了 J-1。结论只能是 `undecidable`（7.10 出 C）；
- 若采**目标**（ABI 面被定义、被门禁钉住、非 ABI 部分有书面声明）：A 满足，B 亦满足 J-1，但 B 在 J-2/J-3/J-4/J-5 上失分。

**主张：J-1 应按目标读。** 理由：判据名是「ABI 洁净」而非「`nm` 最小」；而且 A 的 `expected.nm` 正是把「ABI 洁净」机械化——**内部符号改名会让库自己的门禁先红，而不是等消费者链接失败**。请裁判在 `verdict.md` 里明写采用哪种读法；这是本庭唯一的分歧点，也是 7.9 能否给出 `upheld` 的前提。

### J-2 细化

- A 的命令集：`ct build --emit-c`、`cc -c`、`ar rcs`、`nm -g --defined-only`。这四件在 macOS 与 Linux 默认工具链都有（macOS 的 `nm` 是 llvm-nm，Linux 是 GNU nm，`-g --defined-only` 两边都认）。
- B 的命令集：macOS `ld -r -exported_symbols_list <file>` + 重新 `ar`；Linux `objcopy --localize-hidden` + 重新 `ar`。**两种工具、两种可见性语义**（Mach-O 白名单 vs ELF hidden 本地化），macOS **根本不存在** `objcopy`/`llvm-objcopy`（E1 实测 MISSING）。
- 结论：J-2 的「同一套命令在 macOS + Linux 的默认工具链可用」A 过、B 不过。

### J-3 细化

实测 `main.o`（装箱 `Dog` 的单元）含 `U _Dog_Speak_vtable`——**跨单元引用 vtable 是真实存在的**（`Emitter.h.ct:3304` 会为导入方发射 `extern struct <Trait>_vtbl <Struct>_<Trait>_vtable;`）。

- A：vtable 保持 external，`main.o` 的未定义引用由 `impl_dog.o` 定义满足，**零改动、零回归**。
- B：若按成员逐个本地化，`_Dog_Speak_vtable` 在 `impl_dog.o` 里变 local，`main.o` 的 `U` 无人解析 → **链接失败**。B 唯一可行做法是先 `ld -r` 把全档合成一个可重定位对象再本地化——这会：
  1. 让 `ar t` 从 7 个成员变成 1 个（实测 3→1），与 O1「逐单元 `.o`」和 D39-3 的产物形态冲突；
  2. 把确定性构建问题从 `ar` 时间戳扩大到 `ld -r` 的节合并/`LC1` 标记（E1 的 `nm -m` 出现 `non-external (was a private external) LC1`）；
  3. 让 `check-ast` 的 p39 夹具从「比 7 个 `.o` 的符号」变成「比单一合成对象的符号」，回归面积更大。

### J-4 / J-5 细化见 §6、E1。

---

## 3 E1 — 完整命令 + 原始输出

> 复现前提：干净 HEAD `ac040d1`；只读仓内夹具。所有产物写 `/tmp`。以下输出为终端原样粘贴（未改写）。

### E1.0 环境与工具

```console
$ command -v objcopy llvm-objcopy ld ar nm cc strip
/usr/bin/ld
/usr/bin/ar
/usr/bin/nm
/usr/bin/cc
/usr/bin/strip
$ for t in objcopy llvm-objcopy ld ar nm cc strip; do printf '%-14s ' "$t"; command -v "$t" || echo MISSING; done
objcopy        MISSING
llvm-objcopy   MISSING
ld             /usr/bin/ld
ar             /usr/bin/ar
nm             /usr/bin/nm
cc             /usr/bin/cc
strip          /usr/bin/strip
$ nm --version 2>&1 | head -2
llvm-nm, compatible with GNU nm
Apple LLVM version 21.0.0
$ ar --version 2>&1 | head -2
usage:  ar -d [-TLsv] archive file ...
        ar -m [-TLsv] archive file ...
```

`ar --version` 不支持版本查询（打印 usage），说明这是 Apple `ar`；`nm` 是 llvm-nm。**`objcopy` 与 `llvm-objcopy` 都不存在。**

### E1.1 一个真实 `.h.ct` 工程的 external 符号（vtable + `Str_*`）

夹具来源：`test/modules/split/` 的 `shapes.h.ct`（`pub trait Speak` + `pub struct Dog`）与 `impl_dog.h.ct`（`impl Speak for Dog`），`main.ct` 为触发装箱而改写（**只在 `/tmp` 副本上改**）：

```console
$ rm -rf /tmp/p39box && mkdir -p /tmp/p39box/out
$ cp /Users/samxx/dsh-ws/ct-lang/test/modules/split/{shapes.h.ct,impl_dog.h.ct} /tmp/p39box/
$ cat > /tmp/p39box/main.ct <<'EOF'
import shapes;
import impl_dog;

int main(void)
{
    Dog d;
    d.n = 3;
    Speak s = d;
    s.hi();
    return 0;
}
EOF
$ /tmp/p39head/ct build --emit-c --outdir /tmp/p39box/out /tmp/p39box/main.ct 2>&1 | tail -2
cc -std=c99 -I /tmp/p39box/out /tmp/p39box/out/Vec.c /tmp/p39box/out/Option.c /tmp/p39box/out/Result.c /tmp/p39box/out/Str.c /tmp/p39box/out/main.c /tmp/p39box/out/shapes.c /tmp/p39box/out/impl_dog.c -o a.out
```

（该构建连同内置 std 单元 `Vec`/`Option`/`Result`/`Str` 一起发射；仓内 `test/modules/split` 的同源构建只发射 3 个单元。两者差异属导出集合/B39-1 范围，本庭不追。E1 取带内置 std 的这一份，正好同时覆盖 vtable 与 `Str_*`。）

```console
$ cd /tmp/p39box/out && for c in *.c; do cc -std=c99 -I. -c "$c" -o "${c%.c}.o" || echo FAIL "$c"; done
$ ZERO_AR_DATE=1 ar rcs /tmp/libbox.a *.o
$ ar t /tmp/libbox.a
__.SYMDEF SORTED
Option.o
Result.o
Str.o
Vec.o
impl_dog.o
main.o
shapes.o
$ nm -g --defined-only /tmp/libbox.a

Option.o:

Result.o:

Str.o:
0000000000000134 T _Str_release
0000000000000000 T _Str_retain
000000000000052c T _str_c_str
00000000000003f8 T _str_compare
00000000000002cc T _str_concat
0000000000000178 T _str_from
0000000000000048 T _str_from_len
00000000000001f0 T _str_len
0000000000000208 T _str_slice

Vec.o:

impl_dog.o:
0000000000000050 D _Dog_Speak_vtable
0000000000000040 T _dog_get

main.o:
0000000000000000 T _main

shapes.o:
```

`nm -m` 原样（前 20 行）：

```console
$ nm -m /tmp/libbox.a | head -20

Option.o:
0000000000000000 (__TEXT,__text) non-external ltmp0

Result.o:
0000000000000000 (__TEXT,__text) non-external ltmp0

Str.o:
0000000000000134 (__TEXT,__text) external _Str_release
0000000000000000 (__TEXT,__text) external _Str_retain
                 (undefined) external _free
                 (undefined) external _malloc
000000000000052c (__TEXT,__text) external _str_c_str
00000000000003f8 (__TEXT,__text) external _str_compare
00000000000002cc (__TEXT,__text) external _str_concat
0000000000000178 (__TEXT,__text) external _str_from
0000000000000048 (__TEXT,__text) external _str_from_len
00000000000001f0 (__TEXT,__text) external _str_len
0000000000000208 (__TEXT,__text) external _str_slice
0000000000000000 (__TEXT,__text) non-external ltmp0
```

要点：**12 个 defined global**（9 个 `Str_*` + `_Dog_Speak_vtable` + `_dog_get` + `_main`），其中只有 `_dog_get`/`_main` 属预期导出；`_Dog_Speak_vtable` 是数据符号（`D`），`Str_*` 全是 `T`。`shapes.o` 没有链接期全局符号（纯类型单元）。

### E1.2 `-fvisibility=hidden` 藏不住（A 的立论根据）

```console
$ cc -std=c99 -fvisibility=hidden -I. -c Str.c -o Str_hidden.o
$ nm -g --defined-only Str_hidden.o
0000000000000134 T _Str_release
0000000000000000 T _Str_retain
000000000000052c T _str_c_str
00000000000003f8 T _str_compare
00000000000002cc T _str_concat
0000000000000178 T _str_from
0000000000000048 T _str_from_len
00000000000001f0 T _str_len
0000000000000208 T _str_slice
```

即 O3 的 `-fvisibility=hidden` 在 Mach-O 上不改变 `nm -g` 的面；与 D39-5 的理由列一致。

### E1.3 B 的可行性探针（诚实记录：B 在本机**可行**）

```console
$ cd /tmp/p39split            # 同源 3 单元构建，未带内置 std
$ nm -g --defined-only /tmp/libsplit.a
...
impl_dog.o:
0000000000000050 D _Dog_Speak_vtable
0000000000000040 T _dog_get

main.o:
0000000000000000 T _main

shapes.o:
$ nm -g /tmp/p39box/out/main.o | head -3
                 U _Dog_Speak_vtable
0000000000000000 T _main
$ printf '_dog_get\n' > /tmp/exp.txt
$ ld -r -o /tmp/split_r.o -exported_symbols_list /tmp/exp.txt impl_dog.o shapes.o
$ nm -g --defined-only /tmp/split_r.o
0000000000000040 T _dog_get
$ nm -m /tmp/split_r.o | head -8
000000000000004c (__TEXT,__cstring) non-external (was a private external) LC1
0000000000000000 (__TEXT,__text) non-external _Dog_Speak_hi
0000000000000058 (__DATA,__data) non-external (was a private external) _Dog_Speak_vtable
0000000000000040 (__TEXT,__text) external _dog_get
0000000000000060 (__DATA,__data) non-external _g_dog
                 (undefined) external _printf
$ ZERO_AR_DATE=1 ar rcs /tmp/libB.a /tmp/split_r.o
$ ar t /tmp/libB.a
__.SYMDEF SORTED
split_r.o
$ nm -g --defined-only /tmp/libB.a
split_r.o:
0000000000000040 T _dog_get
$ cc /tmp/p39split/main.o /tmp/libB.a -o /tmp/consumer2 && echo 'link OK'
link OK
```

**这条证据对 A 不利的地方必须写清楚**：B 在 macOS 上**确实**能把 `nm -g` 收到只剩 `_dog_get`，消费者也照常能链接。所以 J-1 按字面归 B，我不否认。A 的立论不在「B 做不到」，而在「B 的代价与跨平台语义」（§2 J-2/J-3、§6）。

### E1.4 最小 `.a` 的 `ar` + `nm`（已含于 E1.1/E1.3）

`/tmp/libbox.a`（7 成员，`ar t` 见上）与 `/tmp/libsplit.a`（3 成员）都可用；`nm -g --defined-only` 输出如上。**A 不改变这两条命令的任何一步。**

---

## 4 E2 — `file:line` 锚点（至少 1 条不利于己方）

| # | 锚点 | 内容 | 对 A |
| --- | --- | --- | --- |
| A1 | `selfhost/ct-ast/backend/emit/Emitter.h.ct:2392-2396` | `if (self->vtable_exported(si, tname))` → 发射 `struct <Trait>_vtbl <Struct>_<Trait>_vtable;`，否则 `static ... __attribute__((unused))` | **有利**：pub trait 的 vtable 按设计就是 external，A 只是接受既有事实并用快照冻结 |
| A2 | `selfhost/ct-ast/backend/emit/Emitter.h.ct:3304` | `extern struct %s_vtbl %s_%s_vtable;`（导入方的 extern 声明） | **有利（J-3）**：跨单元引用真实存在，B 必须整档 `ld -r` 再本地化，否则断链 |
| A3 | `lib/std/Str.h.ct:131-141`（`impl Str { Str retain() … void release() … }`） | 内置 `Str` 的固有 impl 方法发射为 **external** `<Struct>_<method>`（E1 实测 `T _Str_retain`/`T _Str_release`） | **不利**：`nm -g` 确实暴露非 ABI 符号；消费者只要自己声明 `struct Str Str_retain(struct Str *);` 就能链上并误用，A 不能从链接层阻止 |
| A4 | `test/modules/split/main.ct:1` | 注释：「this unit sees only the type … so the impl's **static vtable stays invisible**」 | **不利**：仓库自己的文档已经与实测相反（`nm` 显示 `D _Dog_Speak_vtable` external）。说明「仅靠文档注明非 ABI」会漂移；A 的补救是 `expected.nm` 快照——文档写的和门禁钉的必须是同一份事实 |

**为何仍选 A（对 A3/A4 的正面回应）**：A3 的误用风险是真实的，但 B 的隔离只发生在**链接器名字解析**层，且以整档重链为代价；A 把同一个风险转成**库自己的门禁**：`expected.nm` 一旦与实测不符即红，内部符号改名不可能「静默」流出——它先弄红 p39。A4 更说明「文档」单独不可信，所以 A 的方案不是「文档注明」四个字，而是「文档 + 快照」两件套；只留文档的方案我同样反对。

---

## 5 E3 — 可证伪预测

| # | 预测（若 A 成立/若 B 成立） | 一次性验证 |
| --- | --- | --- |
| P1 | A 落地后，干净 `ac040d1` 上对 `/tmp/libbox.a` 跑 `nm -g --defined-only`（按 `sed 's/^_//'` 归一后排序）应逐字等于 `expected.nm`；**故意往夹具加一个 external 顶层函数**，p39 段必须变红（exit ≠ 0），删掉后转绿 | `bash selfhost/check-ast.sh` 的 p39 段，跑两次（原始/加符号）对比退出码 |
| P2 | 若 B 按「逐成员本地化」实现，`main.o` 的 `U _Dog_Speak_vtable` 将无人解析，链接报 `Undefined symbols: _Dog_Speak_vtable`；若 B 改为整档 `ld -r`，则 `ar t lib<base>.a` 只剩 1 个成员（实测已见 3→1） | 对 B 的实现跑 p39 夹具 + `ar t` |
| P3 | A 的检查在 Linux 上同一套命令可用：`nm -g --defined-only` 输出无前导 `_`（`dog_get`、`Dog_Speak_vtable`），归一后与同一份 `expected.nm` 相等；若 Linux 上输出成员顺序不同，排序后仍相等 | `sort` + `sed` 后 `diff` |
| P4 | 若某台 macOS 的**默认**工具链里能 `command -v objcopy` 或 `llvm-objcopy` 成功，则 B 的 J-2 成本显著下降，我的 J-2 主张被削弱 | `command -v objcopy llvm-objcopy` |

P2/P3 是可被反证的具体断言；P1 是可被门禁直接执行的断言。

---

## 6 E4 — 代价量化

### A 的代价

| 项 | 内容 |
| --- | --- |
| 改动文件 | **2 个**：`selfhost/check-ast.sh`（p39 段加 nm 快照比较，约 25–35 行）、`test/modules/p39_lib/expected.nm`（新增，约 8–12 行）；文档只需在 `<base>.abi.h` 顶部与 ABI 文档各加 1–2 行「非 ABI」，可并入既有 p39 文档交付物 |
| 行数 | **约 40–45 行**（≤120） |
| 平台分支 | 1 处：Darwin 符号带前导 `_`，`sed 's/^_//'` 归一后与同一份快照比较（2–3 行） |
| 影响门禁 | 只影响 `selfhost/check-ast.sh` 的 p39 段；`check-warnings`、`check-goldens`、`test/run.sh`、`check-docs` 零改动。**编译器源码 0 行改动**（Driver/Module/Emitter 都不动），`check-ast` 全量语料零回归是结构性的，不是「跑出来碰巧绿」 |
| 失败模式 | `nm` 漂移 → p39 红，人工确认是「新增导出」还是「内部符号变动」；是前者则更新 `expected.nm` 并在 CHANGELOG 记一笔，后者回退实现。工具缺失：`nm`/`ar` 是 POSIX 默认工具链成员，若真缺则 p39 段硬错（不得静默 skip） |
| 回退 | 单个提交 `git revert`；产物 `.a`/`.abi.h`/`.o` 与回退前**逐字节相同**（A 不改变任何产物），无迁移、无消费者影响 |

### B 的代价（估算，基于 E1 探针）

| 项 | 内容 |
| --- | --- |
| 改动文件 | **≥3 个**：`tool/driver/Driver.h.ct`（导出符号表生成/落盘）、`frontend/module/Module.h.ct`（`ld -r`/`objcopy` 后处理 + 重新 `ar`）、`selfhost/check-ast.sh`（p39 段）；再加夹具与文档 |
| 行数 | **约 150–220 行**（导出名列表生成、平台分支、工具探测、两条命令、失败硬错、临时文件清理、确定性 `ar`）。超出 J-4 的 120 行 |
| 平台分支 | 2 套：macOS `ld -r -exported_symbols_list <file>`；Linux `objcopy --localize-hidden <o>`（或 `--keep-global-symbol`）；macOS 无 `objcopy`，Linux 无 `-exported_symbols_list` |
| 失败模式 | 工具缺失即硬错（本机 mac 默认无 objcopy）；`ld -r` 需要先集齐全档 `.o`，与 O1「逐单元 `.o`」冲突；`ld -r` 合并节后 `nm -m` 出现 `non-external (was a private external) LC1`，确定性/可复现面变大 |
| 回退 | revert 后 `ar t` 从 1 个成员恢复为 N 个成员，p39 夹具的符号断言全部要重写；消费者侧虽不受影响，但**库自身产物形态**变了 |

**结论**：J-4 的「≤2 文件、≤120 行」A 过、B 不过；且 A 的回退是零产物改动的真回退。

---

## 7 E5 — 预判反对席最强论点（B：链接期本地化）及回应

> **【预判】** 以下为我对反对席 REQ 最强论点的复述，非其原文；若其实际主张更强，请在 `counter.md` 中给出，我按 7.11 的增量要求补证。

**反对席最强论点（steelman）**：引自 `battle/p39-2/question.md:5`——「B 链接期本地化（Mach-O `ld -r -exported_symbols_list` / ELF `objcopy --localize-hidden`），使 **`nm -g` 只剩导出面**」。展开为：

1. ABI 的定义就是「别人能链接什么」；`nm -g` 是消费者和工具链实际读的那张表。A 把 `_Dog_Speak_vtable`、`Str_*` 留在表里，任何消费者都能声明后链接，**「非 ABI」只是纸面承诺**；
2. B 用工具把内部符号变 local，**物理上**让误链不可能，这是比快照更硬的保证；
3. 我已实测 B 在 macOS 上可行（E1.3），所以「做不到」不成立。

**回应**：

1. **B 的保证只到名字解析层，且以整档重链为代价。** `nm -m` 里被本地化的符号仍以 `non-external (was a private external)` 留在归档里，调试者/`nm` 仍看得见；真正的 ABI 面是 `<base>.abi.h`，消费者只该 include 它。B 把「开发者可见」与「可链接」混为一谈。
2. **A 的承诺不是纸面的，是可红的。** `expected.nm` 把 12 个 defined global 逐个钉死；内部符号改名 → p39 红 → 发布前暴露。B 的硬隔离并不阻止「导出集合本身」变化（那由 B39-1/§3.1 管），所以 B 多买的只有「误链」这一种情况，而 A 用快照 + 文档买到了「误链可发现 + 改名不静默」两种。
3. **B 在 J-2/J-3/J-4 上都付了可见代价**：跨平台不是同一套命令、macOS 默认无 `objcopy`、`main.o` 的 `U _Dog_Speak_vtable` 要求整档 `ld -r` 从而毁掉「逐单元 `.o`」、改动 ≥3 文件 >120 行。
4. **冻结卡已裁决过这个权衡**：`docs/design/phase39-draft.md:37` 明说「`nm -g` 里仍会看到 trait vtable，它不属于 ABI 承诺」，D39-5 的理由列明说「只能锁快照」。B 要赢，不只是赢 J-1，还要说明**为什么现在推翻冻结理由**——本庭的举证里没有这个说明。

---

## 8 自评（最弱处，便于裁判直接攻击）

- **最强证据**：E1.1 的 `nm -g --defined-only`（12 个 defined global，其中 vtable + 9 个 `Str_*` 非 ABI）+ E1.0 的 `objcopy`/`llvm-objcopy` **MISSING** + E1.3 的 `U _Dog_Speak_vtable` → B 必须整档 `ld -r`（`ar t` 3→1）。
- **最弱处**：**J-1 按字面归 B**（E1.3 已复现 B 的 `nm` 只剩 `_dog_get`）；以及 A3——A 确实不能阻止消费者声明 `Str_retain` 后误链。我的全部请求都压在「J-1 按目标读」这一条解释上；若裁判采字面读，本庭应判 `undecidable` 并按 7.10 出 C（A 的快照 + B 的条件化本地化），而不是直接判 A 成立。
- 若裁判采目标读：A 满足 J-1…J-5，B 在 J-2/J-3/J-4 不满足，`verdict: upheld`。

---

## 9 复现说明

- 所有命令均可在干净 `ac040d1` 重跑；仓内文件只读（`test/modules/split/*.h.ct`、`lib/std/Str.h.ct`、`selfhost/ct-ast/**`）。
- `/tmp/p39head/ct` 为 HEAD `ac040d1` 构建的 `ct v0.37.0`；`/tmp/p39head/src` 为对应干净源码。若用仓内重建的 `ct` 替代，命令其余部分不变。
- E1.1 的 `/tmp/p39box` 是对 `test/modules/split` 的**只读复制 + 改 `main.ct`**；`shapes.h.ct`/`impl_dog.h.ct` 未改。若需完全逐字复现，按 E1.1 的命令块执行即可。
- 本文件不构成对仓库的修改；所有产物在 `/tmp`。
