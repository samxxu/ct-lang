# battle/hw-1 counter — 反对席（REVIEW）主张 B
| 字段 | 值 |
| --- | --- |
| 争点 | P0 与 PH-64 的顺序、`--freestanding`/`--alloc` 边界、const vtable 范围、pilot 定位 |
| 主张 | **B**：P0 → pilot → PH-64；freestanding 边界按“每单元 `nm -u` 符号面”而非“容器类别”收窄；const 可用全量但以 pilot 证据定案 |
| 基线 | `/tmp/pkgdiag/ct-ast` 自报 `ct-ast v0.62.0`（HEAD `485129c9` 源码构建） |
| 证据 | 全部探针在 `/tmp/hw1rev`；只读仓库，未改源码/提案/设计卡 |

## 1 主张与 J-1…J-6 对应
| # | B 的主张 | J | 关键证据 |
| --- | --- | --- | --- |
| B1 | P0 先做；范围须含 `[]`、且带初值数组不再发 `__ct_init`（今天 `[]` 会生成空循环上界） | J-1 | E1-1/E1-2；`test/cases` 无数组初值、无 `const struct`，故 P0 可零 golden 变化 |
| B2 | 容器按符号面分层：`Str` 仅 malloc/free，`--alloc` 下可用；`Vec` 暂不可——B 原主张“扩成 malloc/free/realloc”被 E1-5 证伪 | J-3 | E1-5 |
| B3 | pilot 在 PH-64 前：P0 后即可用 v0.62.0 + `--emit-c` 上板/`-nostdlib` | J-2, J-5 | E1-6/E3 |
| B4 | const 收窄为“可全量，先证伪跨模式链接”；条件化只作回退，不作首选 | J-4 | E1-7/E2 |
| B5 | PH-64 可拆两相（freestanding+alloc / const）；`layout(plain)` 文档先行 | J-5, J-6 | 两份提案均自报“未立项”（`ct-bare-metal-proposal.md:6`、`ct-hardware-pilot-proposal.md:10`） |

## 2 E1 命令与原始输出（E1-n = §2.n）
### 2.1 P0：带初值 trait 数组生成坏 C（文件作用域 / `[]` / 局部）
```console
$ /tmp/pkgdiag/ct-ast ps.ct -o ps.c; echo rc=$?
rc=0
$ grep -n "__greeter_vptr" ps.c | tail -2
20:struct Person ps[2] = { { .name = "a", .age = 1 },
21:                 { .name = "b", .age = 2 } , .__greeter_vptr = &Person_Greeter_vtable};
$ cc -std=c99 -Wall -Wextra -c ps.c -o /dev/null; echo rc=$?
ps.c:21:46: error: field designator cannot initialize a non-struct, non-union type 'struct Person[2]'
rc=1
$ /tmp/pkgdiag/ct-ast arr2.ct -o arr2.c; grep -n "__ct_i <" arr2.c
36:    for (__ct_i = 0; __ct_i < ; __ct_i++) {
```
`[]`（长度推导）形态还会额外生成**空上界** constructor；局部数组同样在元素花括号后追加顶层 designator。P0 的 B2/B4 不只是“支持 `[]`”，必须同时抑制带初值数组的 constructor。既有基线不受影响：`grep -rE "\[[0-9]*\] += \{" test/cases --include='*.expected.c'` 零命中，`grep "const struct"` 零命中（73 个 expected）。

### 2.2 constructor：文件作用域数组的 vptr 不在静态初始化里
```console
$ /tmp/pkgdiag/ct-ast pr.ct -o pr.c; grep -n "__ct_init" pr.c
33:static void __ct_init(void) __attribute__((constructor));
34:static void __ct_init(void) {
37:        ps[__ct_i].__greeter_vptr = &Person_Greeter_vtable;
$ cc -std=c99 -ffreestanding -nostdlib -c pr.c -o pr.o && otool -l pr.o | grep -c __mod_init_func
1
```
`ps.ct`（带初值）也发同一 constructor（`ps.c:34`）：只修 designator 的话，constructor 会再写一次同一 vptr，且裸机 `Reset_Handler` 不跑 `.init_array`；P0 必须一并去掉（B4 判据）。

### 2.3 `const` 数组：vptr 静默不写，`cc` 全绿
```console
$ /tmp/pkgdiag/ct-ast cons.ct -o cons.c; echo rc=$?
rc=0
$ grep -c "__greeter_vptr = " cons.c
0
$ cc -std=c99 -Wall -Wextra -c cons.c -o /dev/null; echo rc=$?
rc=0
```
### 2.4 四单元链接与 `-nostdlib`
```console
$ CT_STD_DIR=/Users/samxx/dsh-ws/ct-lang/lib/std /tmp/pkgdiag/ct-ast build hello.ct --emit-c -o gh
cc -std=c99 -I gh gh/Vec.c gh/Option.c gh/Result.c gh/Str.c gh/hello.c -o a.out
$ ls gh
Option.c Option.h Result.c Result.h Str.c Str.h Vec.c Vec.h hello.c
$ for f in Vec Str Option Result; do cc -std=c99 -ffreestanding -nostdlib -fno-stack-protector -c gh/$f.c -o $f.o; echo "== $f"; nm -u $f.o; done
== Vec
___memcpy_chk ___memset_chk __stderrp _abort _fprintf _free _malloc _realloc
== Str
_free _malloc
== Option
== Result
```
（`Option`/`Result` 的 `nm -u` 为空是因为未实例化；用了 `unwrap` 见 2.6）一个**完全不用容器**的 `hello.ct` 也被拉进四个单元；`cc -nostdlib -static -Wl,-e,_main vprog.o Vec.o Str.o Option.o Result.o` → `rc=1`，未定义符号含 `___memcpy_chk/___memset_chk/__stderrp/_abort/_fprintf`（宿主 clang 的 FORTIFY 名，目标端对应 `memcpy/memset`）。`ct build --freestanding` 今天不存在：`ctc: unknown option '--freestanding'`（`--alloc` 同）。

### 2.5 `Str` vs `Vec` 的真实符号面（本场最硬的一条，且部分不利 B）
```console
$ cc -std=c99 -ffreestanding -nostdlib -c gh/Str.c -Dmalloc=pool_alloc -Dfree=pool_free -o Str_alloc.o; nm -u Str_alloc.o
_pool_alloc
_pool_free
$ ld -r strprog.o Str_alloc.o -o str_combined.o; echo "ld -r rc=$?"; nm -u str_combined.o
ld -r rc=0
（空）
$ cc -std=c99 -ffreestanding -nostdlib -c gh/Vec.c -Dmalloc=pool_alloc -Dfree=pool_free -Drealloc=pool_realloc -o Vec_alloc.o; nm -u Vec_alloc.o
___memcpy_chk ___memset_chk __stderrp _abort _fprintf _pool_alloc _pool_free _pool_realloc
```
`Str` 只要 malloc/free，且映射后可做干净的重定位链接；`Vec` 即使把 alloc 扩成 malloc/free/realloc，仍有 5 个非分配器符号（`fprintf(stderr)` 计 `__stderrp`+`_fprintf`，另有 abort/memcpy/memset；`Vec.h.ct:73,83,102,148`）。**B 的“扩到 realloc 即可带容器”不成立**；可保留的是“按符号面分层”这条判据本身。

### 2.6 pilot 前已有可用基线；纯值容器也并非无 libc
```console
$ /tmp/pkgdiag/ct-ast local.ct -o local.c && cc -std=c99 -ffreestanding -nostdlib -fno-stack-protector -c local.c -o local.o; echo rc=$?; nm -u local.o
rc=0
（空）
$ /tmp/pkgdiag/ct-ast /Users/samxx/dsh-ws/ct-lang/test/bindings/mock-hal/uart.h.ct -o uart_binding.c && cc -std=c99 -ffreestanding -nostdlib -I /Users/samxx/dsh-ws/ct-lang/test/bindings/mock-hal -c uart_binding.c -o uart_binding.o; nm -u uart_binding.o
_mock_uart_send
$ /tmp/pkgdiag/ct-ast build o.ct --emit-c -o go   # Option<int>.unwrap()
$ nm -u go/Option.o
___stderrp _abort _fprintf
```
无堆 trait 程序与 `#include` 直通的 HAL binding 今天就能进 `-nostdlib` 对象（唯一未定义符号是 C shim）；但 A 承诺“`Option`/`Result` 纯值仍可用”只在不用 `unwrap` 时成立（`Option.h.ct:59-60`、`Result.h.ct:77-78` 直接 `fprintf(stderr); abort()`），F2 的“`nm -u` 为空”会红。

**手工等价物（模拟 P0 输出，不是 ct 产物）**：把 vptr 移入元素花括号、删 constructor 后 `ps_fixed.c` 经同一条 `-ffreestanding -nostdlib` 编译 `rc=0`，`nm -u` 空，`__mod_init_func` 计数 0。

### 2.7 const vtable：今天在可写段；全量只需三处
```console
$ nm -m local.o | grep vtable
(__DATA,__data) non-external _Person_Greeter_vtable
$ sed 's/^static struct Greeter_vtbl/static const struct Greeter_vtbl/' local.c > local_const.c
$ cc -std=c99 -Wall -Wextra -c local_const.c -o local_const.o
local_const.c:30:67: warning: initializing 'struct Greeter_vtbl *' with an expression of type 'const struct Greeter_vtbl *' discards qualifiers
$ nm -m local_const.o | grep vtable
(__DATA,__const) non-external _Person_Greeter_vtable
```
只改 vtable 不加 `const` 到 `__vptr`/`vt` 会破坏 `-Wall -Wextra` 零告警；生成物侧只有三处形态（vtable 定义、`__vptr`、`iface.vt`），emitter 发射点有 8 个（`Emitter.h.ct:1861,3145,2729,2732,2747,2750,1596,2842`）。合成跨模式夹具（`struct P` 的成员一处 `struct V *`、一处 `const struct V *`，分 TU）：编译 `rc=0`、链接 `rc=0`、运行 `rc=0`——布局同为 8 字节指针，A 的“跨模式链接对不上”未在链接层复现（形式上是不同类型，属 UB，但代价是头文件选型而非 ABI）。

## 3 E2 `file:line`
| 方向 | 位置 | 事实 |
| --- | --- | --- |
| 利 B | `lib/std/Str.h.ct:25`、`:39` | `Str` 仅 `free`/`malloc`，符号面 2 个；一刀切禁容器会误伤它 |
| 利 B | `lib/std/Option.h.ct:59-60`、`Result.h.ct:77-78` | “纯值”容器也发 `fprintf(stderr)`+`abort`；验收轴应是符号面，不是容器类别 |
| 利 B | `Emitter.h.ct:2934-2939` | 数组初值后无条件追加顶层 designator；P0 是单点修复，不动 ABI |
| 不利 B | `lib/std/Vec.h.ct:73,83,102,148,153` | `Vec` 的裸机障碍是 abort/memcpy/memset/fprintf，不止 realloc；B 的 alloc 扩展方案不充分 |
| 不利 B | `Emitter.h.ct:1861,3145,2729,2732,2747,2750,1596,2842` | const 生成物形态只三处、布局不变；B 的“条件化省 ABI 风险”缺乏依据 |
| 不利 B | `AGENTS.md:339` vs `:341` | “PH-62 → v0.61.0（d=1）”与“PH-62 起恢复 d=0”互相矛盾；B 的 pilot-first 也须先让 REQ 修版本位，否则 PH-64 卡照样无法开卡 |

## 4 E3 可证伪预测
1. P0 落地后，pilot H1/H2 的生成物在目标 `cc -ffreestanding -nostdlib -c` 下 `nm -u` 只含 C shim 符号，pilot 可在 PH-64 前产出可启动镜像；**证伪**：首个可启动镜像必须依赖 S1/S2 的任一标志或代码改动。
2. `Str` 在 `--alloc(malloc,free)` 下可用；**证伪**：`Str_alloc.o` 出现 `pool_alloc`/`pool_free` 之外的符号（今天实测 0 个）。
3. 把 alloc 扩成 malloc/free/realloc 后 `Vec` 仍不可 freestanding；**证伪**：`Vec_alloc.o` 的 `nm -u` 只剩三个 `pool_*`（今天实测另有 5 个）。
4. 全量 const 无 ABI 影响；**证伪**：`_vtbl` 布局或跨 TU 链接因 const 改变（今天实测只换段与告警）。
5. PH-64 拆相后 const 可独立收口；**证伪**：const 必须与 S1/S2 同改（例如 vptr 形态随 freestanding 变），否则 48/73 golden 无法只差三处。

## 5 E4 代价与回退
- **顺序**：A 的工作集 = P0(M) + PH-64(S1 M,S2 S,S3 M,S4 M,S5 可裁) + pilot(H0 S,H1 M,H2 M)；B 是同一工作集重排，**不新增切片**。B 的额外代价只有硬件/工具链前置占用与 PH-64 排期后移一个 pilot-P0 周期（pilot P0 = H0 S + H1 M + H2 M，约 3 个任务轮）；收益是避免在错误轴上冻结 S1/S2（E1-5 已证“容器”不是正确轴）。
- **PH-64 拆两相**：多 1 张卡 + 1 个 MINOR/tag（v0.63→v0.64），换来 const 的 48/73 golden 变更与 S1/S2 隔离；A 自己要求 S3 不与 S1 同提交（提案 §5 末句），拆相只是把该边界升到版本层。
- **const 条件化**：跨模式重定位链接实测 `rc=0`，布局不变 → ABI 风险≈0；代价是 emitter 双分支 + 两套模式测试。全量：3 处 + 48/73 golden。**B 结论：全量更便宜**，条件化只在 pilot 确需混链时启用。
- **回退**：P0 一个 fix 提交、golden 零变化；pilot 是仓外参考工程，no-go 即停；const 一个提交（3 处 + 48 golden），可与 S1 分开 revert；拆相各自 tag。

## 6 E5 对 A 最强论点的 steelman 与逐条反驳
1. **A 最强：契约先行，避免 pilot 反向设计语言。** 反驳：两份提案均无语言新特性（bare-metal 自述“1 个补丁 + 3 份生成物契约”；pilot 自述“不要求新语法”），pilot 只能影响 CLI/发射策略；而 E1-5 已证不先测就会把边界定错（B 自己也定错过 `Vec`），说明需要的是**证据校正**而非“不试错”。
2. **A：freestanding 一刀切禁容器最可机械验收。** 反驳：更机械的判据是“每单元 `nm -u` ⊆ 允许符号集”——`Str` 2 个、`Vec` 9 个，靠 `nm` 可枚举；一刀切会把能用的 `Str` 禁掉，却允许同样发 abort/fprintf 的 `Option.unwrap`，反而不可机械解释。
3. **A：const 一次改到底，双形态会让 `.h` 类型随模式变化。** 这是 A 最强的一条，B 接受其结论：实测三处改动、48/73 golden、外部 C 不依赖 vtbl 类型（bindings/examples 零命中）；条件化省不了 ABI 风险，只多双模式测试。**B 在此点让步，唯一坚持是收口判据 F6（diff 只有三处 + 零告警）。**
4. **A：PH-64 收口后再 pilot，否则拿未冻结契约试点。** 反驳：pilot P0 不需要 `--freestanding`；E1-6 已用 v0.62.0 产出 `-nostdlib` 干净的 HAL binding 对象，P0 形态等价物也干净；pilot 恰好能替 PH-64 提供 F1–F6 的夹具来源。
5. **A：`Option`/`Result` 纯值按需拉仍可用。** 反驳：`unwrap` 发 `fprintf/abort`，F2 的 `nm -u` 空会红；这条与 B 的 `Vec` 主张同源——分类维度（堆/纯值）与真实符号面不一致。

## 7 结论
**B 胜出的条件**：EDITOR 采纳顺序 P0 → pilot H0/H1/H2 → PH-64（可拆两相）；PH-64 的 freestanding 边界改写成“每单元 `nm -u` ⊆ 允许符号集（默认仅 malloc/free，`--alloc` 逐项追加）”，而不是容器名单；P0 范围含 `[]` 与“带初值数组不发 constructor”；const 按 A 的全量方案，以 F6 三处 diff 收口。

**B 不成立的条件**：pilot 在 PH-64 前无法产出可启动镜像（即首个镜像必须依赖 S1/S2）；或硬件/工具链在 H0 前无法就位，使 PH-64 被无限期阻塞；或符号面验收被证明不可枚举（标准库单元符号随实例化漂移到无法列出允许集）；或 P0 无法零 golden 落地（现状不支持：73 个 expected 无数组初值、无 `const struct`）。B 已自证一条细节错误（`Vec` 的 realloc 扩展），故“B 全对”不成立，胜出仅限顺序与验收轴。
