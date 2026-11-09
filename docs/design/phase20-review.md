# Phase 20 独立评审：CT 对 ct-pkg 的完整支持

**本文件是 Phase 20 的独立评审，不是设计稿。** 评审在未阅读 `phase20.md` / `phase20-disputes.md`
的前提下完成，结论只依据源码与可复现探针；与争议清单的裁决见 §9。

**日期**：2026-11-06
**评审对象**：`ct` @ `915c12c`（`CTC_VERSION 0.19.1`）+ `ct-pkg` 各包当前 HEAD
**方法**：读 `Module.h.ct` / `Parser.h.ct` / `MapBuild.h.ct` / `Emitter.h.ct` / `Pkg.h.ct` /
`Driver.h.ct`，读 8 个包的目录、`ct.pkg`、shim、README、CI；在 `/tmp/p20`–`/tmp/p32` 写 24 个探针，
用本仓库 `ctc` 与自举出的 `ct-ast` 实跑。

---

## 0. 结论摘要

- **阻断 1 条**：清单没有提到——**单元基名就是全局身份**，产物按 basename 拍平到同一个 `outdir`，
  两个不同命名空间的同名单元会**静默互相覆盖**，构建仍返回 0。
- **应修 6 条**：命名空间单元无法 `use` 跨单元 trait；单文件程序 + `pub trait` + `impl` 生成不可编译的 C；
  类型宿主歧义没有任何逃生口；`int` 没有宿主而字符字面量按 P0 是 `int`（P0 与 P1 互相拆台）；
  `ct build` 不读 `ct.pkg`/`ct.lock`；`.m.ct` 除了 trait 与 recipe 什么都声明不了。
- **建议 7 条**：`use` 的 vptr 字段改变结构体布局且无去虚拟化；`.h.ct` 其实能出口 `pub fn`（std 的全 shim 政策是自限）；
  包 CI/测试只有 std 一家；编译器没有可安装产物；索引只留最高 tag；shim 的 `static inline` 状态每 TU 一份；包管理器容量上限。
- **清单十条的裁决**：3 条不成立（1、3、4），2 条部分成立（8、10），5 条成立但优先级不同（2、5、6、7、9）。
  不成立的 3 条如果照单执行，会把预算花在错误的问题上。
- **终局判断**：按清单做完，包作者**仍会撞三面墙**——同名单元不能共存（阻断）、`int` 不能有方法、
  包无法在 CI 里廉价验证自己。前两面是技术限制（可修，但都在编译器里）；第三面是可接受的取舍，
  前提是先给出可安装的编译器。

---

## 1. 证据索引

| 探针 | 命令要点 | 结论 |
|---|---|---|
| P-A | `a/Thing.h.ct` + `b/Thing.h.ct`，两个命名空间各一个同名单元 | `out/Thing.c` 只剩后者，cc 行把同一文件列两次 |
| P-B | `lib/Util.h.ct` 定义 `pub fn`，他被另一个单元导入并调用 | **可导出、可调用、可运行**（推翻「`.h.ct` 不能出口函数」） |
| P-C | `pub trait` + `struct use` + `impl` 全在一个单元、单文件程序 | cc 报 `variable has incomplete type 'struct P_vtbl'` |
| P-D | 同上，但 trait 为私有 `trait` | 通过（rc=0） |
| P-E | 命名空间单元 `import lib::P` + `use P`（P 在另一单元） | `struct 'S' uses undefined trait 'P'` |
| P-F | 同上，但实现单元**不声明** `namespace` | 通过并运行（hal 的实际形态） |
| P-G | 两个包各把 `len` 绑到 `char *` | `ambiguous type-host map`，且 4 种全限定拼写全部失败 |
| P-H | `int` 接收者调用 std 的方法；`'7'.isDigit()` | 均失败；`((char)'7').isDigit()` 成功 |
| P-I | `use` 一个 trait 后 `sizeof` | 结构体多一个 vptr 字段；`s.area()` 走间接调用 |
| P-J | 两个包都有 `Str.m.ct` + `Str.shim.h` | `shim base name 'Str' is ambiguous`，**无解** |
| P-K | `-I vendor/std` 消费 std 的 `str`/`num` | 可构建；cc 行含 `-I vendor/std/std/num`（shim 根）与 `-I <outdir>` |
| P-L | std 的 `Vec`/`Map`/`Arena`/`Test` | 产物为 `Vec.c`、`Map.c`、`Arena.c`、`Test.c`——最容易被第三方撞上的名字 |

---

## 2. 阻断

### F1 单元基名即全局身份，产物扁平覆盖（静默）

**位置**：[Module.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/module/Module.h.ct)
的 `emit_unit` 输出路径、`build_main` 的 cc 行（`-I %s` 在 1063/1069，输出为 `"%s/%s.c"`）。

**事实**：`out/<base>.c` / `out/<base>.h`，`base` 是**文件名去扩展名**，不含命名空间。探针 P-A：

```
out/Thing.h   ← 只有 b 的结构体
out/Thing.c   ← 只有 b 的函数体
cc -std=c99 out/main.c out/Thing.c out/Thing.c -o app     ← 同一文件编译两次
```

`a_value` 完全消失，`main` 里对它的引用变成 undefined reference；而 `ct build` 退出码是 0，
没有任何诊断。单元自身的符号（`a_Thing`、`b_Thing`）**是**带命名空间 mangle 的——只有文件名没有。

**三种失败模式，按发现顺序**：

1. 同一单元同时 `import a::Thing; import b::Thing;` → `one alias names two imports`（可 `as` 绕开）；
2. 两个包都有同名单元且都有 shim → [Module.h.ct:974](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/module/Module.h.ct#L974)
   `shim base name 'Str' is ambiguous`，**无绕法**（shim 必须与 `.m.ct` 同基名）；
3. 无 shim 时 → 上面的静默覆盖。

**为什么 std 的多套一层目录救不了**：`std/str/String` 只让 *import 路径*唯一；
产物仍然叫 `String.c`、`Vec.c`、`Map.c`。第三方包只要有一个 `Map.h.ct`，它和 std 的 `Map` 就在
同一个 `outdir` 里抢同一个文件。std 恰好占用了最容易重名的四个基名（P-L）。

**影响**：这就是「两个包无法在同一个程序里共存」的**真实原因**，比清单第 2 条（类型宿主歧义）硬得多，
因为歧义至少有诊断，这个连诊断都没有。包作者无法通过改包名、加命名空间、改目录规避——
除非改文件名，而文件名是包 API 的一部分（`import Uint;` 这种写法在 ct-pkg 里到处都是）。

**最小修法**：产物按命名空间分目录或加前缀。

- 方案 A（推荐）：`out/<ns path>/<base>.c|h`，`#include` 与 cc 行同步；文件名不再全局，`import` 语义不变。
- 方案 B：`out/<ns_joined>_<base>.c`，改动更小，但 `#include "std_str_String.h"` 影响所有 golden 的头文件名。
- 兜底：即使不做 A/B，也必须在编译期检测「两个已加载单元的 base 相同」并**报错**（当前只在 shim 上做了）。

**验收**：P-A 必须变成编译期诊断；`#include` 全部可解析；golden 全量重生成后再比对差异应只有文件名。

---

## 3. 应修

### F2 命名空间单元无法 `use` 跨单元 trait

**位置**：[Parser.h.ct:496](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Parser.h.ct#L496) 的导入绑定与
`use` 的 trait 查找。

**事实**（P-E / P-F）：同一份代码，

- 实现单元**不写** `namespace` → 通过并运行（hal 的 `examples/fake-uart` 就是这种形态）；
- 实现单元写 `namespace lib;` → `error: struct 'S' uses undefined trait 'P'`，
  即使类型导入（`import lib::Q;` 的 `struct Q`）在同一文件里工作正常。

**影响**：`hal` 能工作纯属「它是扁平的」。任何采用 std 那套 `<pkg>/<ns>/<unit>` 目录的包，
都**只能把 trait 和 impl 关在同一个单元里**，不能把契约单独发布成
`Contract.h.ct` 让别人实现。这是包分层最常用的形态（接口/实现分离），当前写不出来。

**最小修法**：`use` 查 trait 时先查本单元，再查导入绑定表；导入绑定里记录的应是
「源名 → 该单元中的 trait 索引」，而不是只登记类型。验收：P-E 必须通过，并补一条 gate。

### F3 单文件程序 + `pub trait` + `impl` 生成不可编译的 C

**位置**：[Emitter.h.ct:1089](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct#L1089)
`emit_vtable_fwd` 在单单元（`emit_program`）路径下的调用。

**事实**（P-C / P-D）：`pub trait P` + `impl P for S` 在 `ct build x.ct`（整个程序一个单元）下，
`struct P_vtbl` **只有前置声明，没有定义**，而 impl 生成了带初始化器的
`static struct P_vtbl S_P_vtable = {…}` → cc 报 incomplete type。把 `pub` 去掉即通过；
多单元构建（std/test 那种）也通过。

**影响**：单文件教程/示例只要用到 public trait 就编不过——恰好是「五分钟上手」的路径。
与 F2 叠加时很容易被误判成同一问题。

**最小修法**：单单元路径也调用 `emit_vtable_fwd`（或在定义 vtable 变量前内联 `struct …_vtbl { … }`）。
验收：P-C 通过；把 std 的 tutorial 代码按单文件跑一遍。

### F4 类型宿主歧义没有逃生口

**位置**：[Emitter.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct) 的类型宿主派发
（`aux == 6` 分支）与 `map_visible`。

**事实**（P-G / P-J）：两个包都把 `len` 绑到 `char *` 时，唯一可用的写法 `s.len()`
报 `ambiguous type-host map for method 'len' on type 'char *'`；
`Str::len(s)`、`p1::Str::len(s)`、`p1::StrA.len(s)`、`StrA.len(s)` **四种拼写全部失败**
（前两种报「该命名空间没有这个函数」，后两种报语法/解析错误）。

**影响**：现状不是「冲突被推到每个调用点」，而是**连推到调用点的路都没有**。
两个包或者二选一（删掉一个），或者消费者把其中一个包的整个 import 摘掉。
清单第 2 条成立，且比「无 re-export」更严重。

**最小修法**（两条一起做才有意义）：

1. 给类型宿主加一个全限定调用形态 `Trait::method(recv, args…)`（对象宿主/命名空间宿主已有
   `host::Trait.method(…)`，类型宿主缺这一档）；
2. 诊断里直接给出可用写法：`ambiguous …; write p1::Str::len(s) to pick one`。

只做 1 不做 2，用户仍然要读源码才知道有哪个 trait 名。

### F5 `int` 没有宿主，而字符字面量是 `int`（P0 × P1 互相拆台）

**事实**（P-H）：

- `std` 的 `Num.m.ct` 只给 `long` / `long long` / `char` 建宿主，**刻意不给 `int`**；
  于是 `int n; n.toString()` / `n.abs()` → `no method … for type 'int'`，而 `long n` 可以。
- P0 把字符字面量判成 `int`（与 C 一致），`Char` 宿主是 `char`；
  于是 `'7'.isDigit()` → `no method … for type 'int'`，必须写 `((char)'7').isDigit()`。
  上一轮 README 里「`'7'.isDigit()` 命中的是 int 宿主」的说法**已不成立**。

**影响**：`int` 是 C 的默认整数类型，也是绝大多数表达式的类型。一个「让基本类型有方法」的框架
在自己的 std 里放弃了 `int`，等于告诉包作者：**你要么接管全世界的 `int`（并与任何同样做的包冲突），
要么不支持 `int`**。这不是 std 的疏忽，是缺少「作用域」的直接后果。

**最小修法**（择一，建议 1）：

1. 给 `int` 建宿主，但把 `int` 的方法放在**低优先级层**：同一方法名同时存在 `long`/`char` 宿主时
   优先更具体的宿主；同名冲突时才报歧义。这样 std 可以安全地拥有 `int`，第三方也能覆盖个别方法。
2. 折中：字符字面量在类型宿主查找时**同时**按 `int` 和 `char` 试一次（P0 的类型判定不动）。
   这能救 `'7'.isDigit()`，但救不了 `int n` 的整体缺位。

无论选哪条，都要在 `primitive-methods.md` 里把「`int` 不在宿主表」写成显式决定，并说明理由。

### F6 `ct build` 不读 `ct.pkg` / `ct.lock`，`requires` 只警告

**位置**：[Pkg.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/tool/pkg/Pkg.h.ct) 的 `install_main`；
[Module.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/module/Module.h.ct) 的 `build_main`。

**事实**：`ct build` 只认 `-I` / `--cflags` / `--ldflags`，**从不打开 `ct.pkg` 或 `vendor/ct.lock`**。
唯一的桥是 `ct install` 打印出来的一行命令：

```
ct build -I vendor/std --cflags "-I vendor/zlib/zlib" --ldflags "-lz" <all *.ct> -o build
```

- 包更新了 `cflags`，消费者的旧命令不会知道自己过期了；
- `requires = ct >= 0.20.0` 在 `ct install` 时只 `fprintf(stderr, …)` 警告，**build 完全不看**；
- 这也是清单第 8 条（`requires` 与 `dep` 易混）的真身：不是命名，是一个被检查、一个不被检查。

**影响**：包作者改一次 `ldflags`，所有消费者的 README 都变成错的，而且没有任何工具能发现。
包管理器实际只完成了「下载 + 打印」。

**最小修法**：给 `ct build` 加 `--pkg`（或在当前目录有 `ct.pkg` 时默认）读取 `vendor/ct.lock`，
自动追加 `-I vendor/<pkg>`、聚合 cflags/ldflags、并在版本不满足 `requires` 时**失败**（不是警告）。
打印那一行保留给「不想依赖清单」的用户。

### F7 `.m.ct` 除了 trait + recipe 什么都声明不了

**位置**：[Parser.h.ct:795](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Parser.h.ct#L795)。

**事实**（P-M）：`#ct-raw` 在 `.m.ct` 里被拒（[Parser.h.ct:797](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Parser.h.ct#L797)），
`pub struct`、`pub fn` 同样被拒。所以映射单元只能放「trait + 绑定」，
任何需要类型或函数体的映射都必须拆成 `.h.ct` + `.m.ct`（+ 可选 `.shim.h` / `.shim.c`）。

**为什么清单第 1 条不成立**：`.m.ct` **不产生产物**，`#ct-raw` 放开也没有地方落地——
除非把它内联进每个消费者的 `.c`，那正是 `#include "<base>.shim.h"` 已经在做的事，
而且会造成每 TU 一份代码。所以放开白名单不会把两文件压回一文件，只会把 shim 的缺点搬到 `.m.ct` 里。
SH-58 判「有意边界」是对的；但理由要写对：不是「团队保守」，而是**零产物约束的直接推论**。

**真正值得评估的变体**：允许 `.m.ct` 声明 `pub struct`（把类型定义搬进去）。
这不成立，因为类型定义必须有 `.h` 产物，而 `.m.ct` 的契约就是不产物。
→ 结论：**维持现状**，在文档里把它写成「一个映射模块的最简形态是三个文件，这是设计代价」。

---

## 4. 建议

### F8 `use` 的 vptr 字段改变结构体布局，且没有去虚拟化

`struct Sq { int side; } use Shape;` 的 `sizeof` 从 4 变成 16（LP64），
`s.area()` 直接生成 `s.__shape_vptr->area(&s)`，即使接收者静态类型已知、程序里只有一个 impl。
两个独立问题：

- **ABI**：任何「用 CT 结构体镜像 C 布局」的包（hal 的定位）一旦 `use` trait 就不再是裸 C 结构体，
  不能按值传给 C、不能嵌入 C 数组。这是设计取舍，但要在包文档里明写，不能只写在 `Test.h.ct` 的注释里。
- **性能**：静态接收者 + 单 impl 的去虚拟化是很小的改动（派发前查一次「该 (struct,trait) 是否只有一个 impl」），
  `self->area()` 在 impl 内部也应能直呼。热路径数据结构（向量、哈希表）受益明显。
  → 建议 P2，不进 P0。

### F9 `.h.ct` 能出口 `pub fn`，std 的全 shim 政策是自限

探针 P-B：`.h.ct` 里的 `pub fn` 有原型、有 mangle、跨单元可调用、可运行
（[Emitter.h.ct:971](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct#L971) 无条件为 `pub` 函数写原型）。
所以「`.h.ct` 不能出口函数」是**错误前提**，清单第 3 条不成立。

但 std 现在的政策（映射模块 = `.m.ct` + `.shim.h`，绝不出口函数）**不是纯损失**：

- shim 的 `static inline` 在 `-O2` 下会内联进调用点，跨 TU 不产生调用；
- `.shim.h` 的 helper 不会出现在包的公开符号表里（`static`），不会污染链接；
- 反过来，`.h.ct` 的 `pub fn` 是外部符号，一旦发布就永远不能改签名。

**评估**：把 std 的 shim 改写成 `.h.ct` **是纯返工，没有净收益**，而且会让 6 个包的自定义 helper
暴露成 ABI。→ **不重估**，但要在 README 里把「为什么用 shim 不用 `.h.ct`」写成一段显式理由，
否则下一个人会重复这个疑问。真正需要 `.h.ct` 出口函数的是**包自己的非映射模块**
（如 `std/vec/Vec.h.ct` 已经这么做了），那部分无需改动。

### F10 包测试与 CI：只有 std 一家

- `std` 有 `tests/run.sh` + `tools/bootstrap-ct.sh` + `.github/workflows/test.yml`；
- `clib` 没有任何测试；
- `zlib` / `png` / `sqlite` 有 `test/` 目录（`demo.ct` + `expected.out`），**没有 runner**，靠人肉 `diff`；
- `tools/publish-package.sh` 与 `tools/release-package.sh` **不跑 `ct build`，不跑任何测试**。

→ 也就是说「发布一个包」和「这个包能不能编译」在工具链里没有关系。这是 Phase 20 应该补的**约定 + 一个脚本**，
不需要动编译器：`ct.pkg` 增加 `[test]` 段（或约定 `tests/run.sh`），`ct test` 只负责
「在 `vendor/` 里跑一遍消费者视角」——**在包内 `-I .` 跑不算数**，那是作者视角。

### F11 编译器没有可安装产物

`std` 的 CI 在每次 PR 里 clone `ct-lang` 并从 L0 自举到 `ct-ast`。第三方包要测自己，
必须先有一个编译器源码树。这不是包的错，是**发行缺失**：`ct install` 只装包，不装编译器。
→ Phase 20 的「完整支持」如果只做编译器特性，第三方作者的第一次体验仍然是「先自举编译器」。

### F12 索引只保留最高 tag

`index/tools/refresh-index.sh` 每次从零重写，每个包只取最高 `v*` tag；
`gen-index.sh` 虽然按 `name+version` 去重（能保留多行），但源头只有一行。
于是 `dep = "foo@^1.0.0"` 在 `foo 2.0.0` 发布后**从索引解析不到**，只能改成 git URL 直连。
`ct.lock` 做了 commit + sha256 内容摘要，这一半是好的；缺的是「索引保留最近 N 个主版本」。

### F13 shim 的 `static inline` 状态每 TU 一份

`std/num/Num.shim.h` 用 `static char ring[4][32]` 做返回值环形缓冲。
`static` + `inline` 在头文件里意味着**每个消费者 TU 各有一份**：
文档说的「第 5 个结果覆盖第 1 个」只在单个 TU 内成立；跨 TU 比较两个 `toString()` 的结果不会互相影响，
但内存与「全局唯一缓冲」的心智模型不一致。若某天某个 shim 需要**共享**可变状态，这个模型会静默错。
→ 文档写明「shim 状态是 TU 私有的」；需要共享状态的包必须走 `.shim.c`（有产物、可放真正的全局）。

### F14 包管理器容量上限

`MAX_PKG_DEPS 16`、`MAX_PKG_DEPTH 8`（[Pkg.h.ct:24/27](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/tool/pkg/Pkg.h.ct#L24)）。
16 个直接依赖对上层应用偏紧，且超限时的报错是否可诊断需要确认。不建议在 Phase 20 调，
但要在文档里写成已知上限，避免作者撞上后以为是 bug。

### F15 清单第 4 条已不成立

`-I <outdir>` **已经在** cc 行里（[Module.h.ct:1069](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/module/Module.h.ct#L1069)），
并且在 shim 根之后（1063），顺序是有意为之：`#include "<base>.shim.h"` 必须先命中源码树里的 shim，
生成的同名头再命中 outdir。探针 P-K 的 cc 行同时含两者。

---

## 5. 清单十条逐条裁决

| # | 清单项 | 判定 | 依据 | 建议归属 |
|---|---|---|---|---|
| 1 | `.m.ct` 禁 `#ct-raw`，被迫拆两文件 | **不成立** | 零产物约束的推论；`#ct-raw` 无落脚点；`.shim.c` 已覆盖非内联 helper | 关闭（文档补理由） |
| 2 | 类型宿主歧义、无 re-export → 两包不能共存 | **成立，且更严重** | 无任何全限定逃生口（P-G） | P1 |
| 3 | `.h.ct` 不能出口 `pub fn` | **不成立** | P-B：可导出、可调用、可运行 | 删除；改为「std 为何仍用 shim」的文档 |
| 4 | cc 行缺 `-I <outdir>` | **不成立** | 1069 已有，顺序有意 | 删除 |
| 5 | 映射方法不校验实参个数（SH-56） | **成立** | 已记录、未排期 | P1（便宜、防静默错调用） |
| 6 | 声明之后的 `import` 静默丢弃（SH-57） | **成立** | 已记录、未排期 | P1（便宜、防静默） |
| 7 | `use` 结构体方法永不内联 | **部分成立** | 真实成因是两个：vptr 字段改布局 + 无去虚拟化 | ABI 写文档（P2），去虚拟化 P2 |
| 8 | `requires` 与 `dep` 语义易混 | **部分成立** | 命名没问题；问题是 `requires` 只警告、build 不检查 | 并入 F6（P0/P1） |
| 9 | 索引只收最高 tag | **成立** | `refresh-index.sh` 从零重写 | P2（索引工具，不动编译器） |
| 10 | `-I vendor/<pkg>` 要求命名空间根 = 包根 | **部分不成立** | 规则本身是「包根 = include 根」，std 多一层是它自己的命名空间选择；真问题是 `ct.pkg` 无法**声明**根 | P2 + 文档 |

---

## 6. 按清单做完，包作者还会撞什么墙

1. **同名单元**（F1）：`ct build` 返回 0，产物是错的。清单完全没有覆盖——这是唯一一条会让人
   「以为成功、实际丢代码」的问题。
2. **`int` 没有方法**（F5）：作者写 `n.toString()` 失败，去读 std 源码才知道「std 不接管 int」，
   然后面临「我要不要接管 int、接管了会不会和 std 冲突」的二次选择。
3. **包无法自证**（F10/F11）：写完包，没有 `ct test`，没有 CI 模板，发布脚本不编译。
4. **契约不能在别处实现**（F2）：想发布「接口包」，只能在非命名空间布局下做。
5. **歧义时无法选择**（F4）：两个字符串包都提供 `len` 时，用户无解。

1、2、4、5 是技术限制（可修，但都在编译器里，不是包能绕的）；3 是工具链缺失。
剩下的是可接受的取舍：`.m.ct` 三文件形态、`use` 的 vptr、shim 的 TU 私有状态、扁平 outdir 之外的命名。

---

## 7. 对 Phase 20 范围的建议（评审方版本）

**P0（不做则「完整支持」不成立）**

1. F1 产物按命名空间去重 + 同名单元编译期诊断（含 shim 已有的那条）。
2. F4 类型宿主全限定调用 `Trait::method(recv, …)` + 歧义诊断给写法。
3. F6 `ct build` 读取 `vendor/ct.lock`（`-I`、cflags、ldflags、`requires` 失败）。

**P1（包作者每天都会碰）**

4. F2 命名空间单元的跨单元 trait `use`。
5. F3 单文件程序的 vtbl 定义。
6. F5 `int` 宿主的优先级规则（或字符字面量的双宿主回退）+ 文档。
7. F10 `ct test` / `tests/run.sh` 约定 + `publish` 前强制 build。
8. SH-56 / SH-57 两条既有 issue。

**P2（不阻塞，但决定体验）**

9. F8 去虚拟化（同单元单 impl）。
10. F9/F1 文档：shim 与 `.h.ct` 的选择理由、`.m.ct` 三文件形态、vptr 布局。
11. F12 索引保留最近 N 个主版本。
12. F11 编译器发行（make install / release tarball）。

---

## 8. English summary

This is an independent Phase 20 review of CT's support for `ct-pkg`, written before reading
`phase20.md` or `phase20-disputes.md`. Findings, in order of severity:

**Blocker.** A unit's base filename is its global identity, and every artifact is flattened into one
`outdir` as `<base>.c` / `<base>.h`. Two units with the same base in different namespaces silently
overwrite each other; `ct build` exits 0. Three failure modes exist (import-alias conflict, a hard
"shim base name is ambiguous" error, and the silent overwrite). The `std` package already occupies
`Vec`, `Map`, `Arena`, `Test` — the four basenames most likely to collide.

**Must fix.** (a) A unit that declares a `namespace` cannot `use` a trait imported from another unit,
so contract/implementation cannot be split across namespaced units; `hal` only works because it is flat.
(b) A single-file program with `pub trait` + `impl` emits an incomplete `struct *_vtbl`.
(c) Type-host ambiguity has no escape hatch: `Trait::method(recv)`, `ns::Trait::method(recv)` and
`ns::Unit.method(recv)` all fail, so two packages cannot both bind a method to `char *`.
(d) `int` has no host while character literals are typed `int`, so `'7'.isDigit()` fails and
`int n; n.toString()` fails. (e) `ct build` never reads `ct.pkg` / `ct.lock`; the only bridge is the
command line that `ct install` prints, and `requires` is a warning only. (f) A `.m.ct` can declare
nothing, which — not `#ct-raw` — is why mapping modules are three files.

Of the ten candidate items, three are false (`.m.ct` / `#ct-raw`, `.h.ct` cannot export `pub fn`,
missing `-I <outdir>`), two are partly false, and five hold. The recommended P0 is: namespace-unique
artifact names with a collision diagnostic, qualified type-host dispatch, and `ct build` consuming the
lockfile.

---

# 第二部：对 [phase20-disputes.md](phase20-disputes.md) 的裁决与实施方案

> 写在 [phase20.md](phase20.md) 与 [phase20-disputes.md](phase20-disputes.md) 之后，§0–§8 未改一字。
> 编号沿用争议清单的 P20-0x；新增项用 P20-00、P20-09…P20-13，并在表里标「新增」。

## 9. 逐条裁决

### 9.1 总表

| 争议项 | 裁决 | 一句话理由 |
| --- | --- | --- |
| A1 `.m.ct` 禁 `#ct-raw` | **部分同意** | 「有意」确实不等于「合理」；但结论仍是本相不放开，理由不是态度而是**零产物**：`.m.ct` 不写 `.c/.h`，`#ct-raw` 没有落点。 |
| A2 类型宿主歧义 | **同意问题，反对现有解法已可用的表述** | 歧义成立且必须进 P0；但 `a::ALen::len(s)` 在 v0.19.1 上**不可用**（实测四种拼写全失败），P20-01 必须包含实现。 |
| A3 `.h.ct` 出口 `pub fn` | **同意「不成立」，同意不重估 std** | 独立复现通过；std 改回 `.h.ct` 是纯返工并暴露 ABI，无净收益。 |
| B4 `-I <outdir>` | **同意** | 已在 `915c12c`，只补回归探针。 |
| B5 SH-56 arity | **同意目标，反对落点** | 检查应放 Emitter 的 map 绑定处（aux 5/6），不是 `Expr.h.ct:1562`；那里还没有选中 map。 |
| B6 SH-57 late import | **同意** | 改在主解析循环，不在 `scan_imports`。 |
| B7 去虚拟化 | **部分同意** | 现象成立；但 impl 函数是 `static`，跨单元看不到，去虚拟化只对**同一单元内**的 impl 有效。验收基准要改。 |
| C8 `requires`/`dep` | **同意 P0 + `--force`** | 必须与「`ct build` 读 lock」同批做，否则硬失败只覆盖 install 一条路。 |
| C9 索引只收最高 tag | **同意 P1** | 消费者是 `dep@range`；必须同时按编译器版本过滤，否则旧 `ct` 会选中新版然后硬失败。 |
| C10 命名空间根=包根 | **同意方向，反对因果** | 多套一层的成因是导入按目录解析，`-I` 只是打印；`namespace =` 的价值是**允许**收层，不是自动收层。 |
| N1 跨根同名单元 | **部分同意** | 「先命中先用」只是跨根；更严重的是**同根不同目录、两个都加载、产物同名静默覆盖**（F1），N1 没覆盖。 |
| N3 `v0.20.0` 含 `915c12c` | **同意** | 且 `requires` 改硬失败后，v0.19.1 用户将完全装不上 std——必须写进发布说明。 |
| 排除 `ct test` | **同意排除子命令，反对排除发布门禁** | 7/8 个包没有 CI、发布脚本不编译，这不是「各仓 CI 承担」能带过的。 |
| 排除 re-export / 任意 C 表达式 | **同意** | 限定调用 + shim 已够，不再造第二套可见性。 |
| 清单覆盖面 | **反对「清单已完整」** | 缺 F1（阻断）、F2、F3、F5、F6，见 §9.4。 |

### 9.2 三个重点，逐一说实话

**① A3：能，且 std 不该回头改。**

我用 P-B 独立复现：`.h.ct` 里 `pub int add(...)` 生成 `int p_add(int, int)` 的原型与定义，跨单元调用与运行均 rc=0。
所以「不能出口」是错误前提，争议清单判定正确。

但「能」不等于「该用」。std 的 shim 有三件 `.h.ct` 出口函数做不到的事：

1. `static inline` 在 `-O2` 下进调用点，跨 TU 零调用开销；`pub fn` 是外部符号，永远多一次调用。
2. `static` 的 helper 不进包的公开符号表；改成 `pub fn` 等于把 shim 的内部 helper（全生态 9 个）永久写进 ABI。
3. recipe 是逐字发射的 C 片段，调用 `pub fn` 只能写改写后的 C 名（`p_add`），把命名空间改写规则
   耦合进配方文本；`static inline` 的裸名才是稳定接口。

结论：**同意不重估**，且这不是「团队保守」，是三条具体代价。文档必须把这三条写出来，
否则下一轮还会有人问同一个问题。

**② A1：「有意」不等于「合理」，但「不合理」也不等于「该放开」。**

争议清单 §4 否掉 SH-58 的论证方式是对的——「有意边界」不能当论据。但它的收益算错了：

- `.m.ct` **不产物**。`#ct-raw` 放开后，文本只能内联进每个消费者的 `.c`，也就是
  `#include "<base>.shim.h"` 已经在做的事，且必须 `static`（否则多消费方重复定义）。
  所以「两文件压回一文件」换来的是**把 shim 的每 TU 一份搬进 `.m.ct`**，不是消除它。
- 更关键：需要类型定义的映射模块**仍然压不掉**——`.m.ct` 不能声明 `pub struct`
  （P-M 实测），所以 `.h.ct` 那半边无论如何都在。能压成一文件的只有「无类型、纯配方」的模块，
  而那类模块本来就没有 `.h.ct`。

因此：**本相不放开**。但理由要按上面两条重写，不用「有意边界」四个字；
`#ct-raw` 若要做，只能走争议清单的选项 B（实现段、隐式 `static`、每消费方发射），
且必须单独立项设计，不能顺手放开。**取消 SH-58 的「设计如此」结论**，改成「受零产物约束，暂不放开」。

**③ A2：解法只解决了「派发」，没解决「身份」。**

争议清单 §5 写「调用点必须写 `a::ALen::len(s)` 才能编译」。**这句话在 v0.19.1 上不成立。**
四种拼写实测：

```
p1::StrA::len(s)  -> error: no function of that name in that namespace
Str::len(s)       -> error: no function of that name in that namespace
p1::Str.len(s)    -> error: no map binds trait 'p1_Str' to namespace 'p1'
Str.len(s)        -> error: use of an undeclared variable
```

原因是 `parse_qual_path` 的 `is_call` 分支只查函数（`find_func`），没有「限定路径末段是方法」这一档；
`host::Trait.method(…)` 那条（`qf == 3`）只处理命名空间宿主，且要求 `.` 不是 `(`。
所以 P20-01 不是「文档化一个已有能力」，是**新增解析 + 新增发射分支**。

至于「共存」的体验，说实话：

- **方法派发层面**：修完之后两个包可以共存，代价是每次调用要写全限定名。`s.len()` 仍然报歧义，
  这是设计，不是缺陷。可以靠 `import a::ALen as ALen;` 缩短，但名字还是得写。
- **单元身份层面**：**没有解决**。两个包各有一个 `Str.m.ct` + `Str.shim.h` 时，
  现在直接 `ctc: shim base name 'Str' is ambiguous`，无绕法；没有 shim 时更糟——静默覆盖（F1）。
  也就是说，A2 的「两个包无法共存」只对「类型宿主同名方法」成立；
  「同名单元」这一层的共存，P20-01 一点忙都帮不上。

因此我在 §7 把 F1 放在所有 P0 之前：**先让两个包能进同一个 outdir，再谈两个方法怎么选**。
争议清单把 A2 定为 P0 第一条、F1 完全没提，顺序是反的。

### 9.3 需要修正的事实与措辞

| 出处 | 原文 | 修正 |
| --- | --- | --- |
| disputes §5 | 「调用点必须写 `a::ALen::len(s)` 才能编译」 | 现在**不能**编译；这是 P20-01 的交付，不是现状。 |
| disputes §2 A1 | 「限制覆盖整个单元」的结论对；但「前导区」只出现在错误文案里 | 保留，P20-08 只改文案不改语义。 |
| disputes §2 B5 | 「`"abc".len(1)`」 | v0.19.1 上需 `char *s = "abc"; s.len(1);`；字面量接收者属 `915c12c`。 |
| disputes §2 B4 | 「来自提交 `915c12c`」 | 正确；但该提交尚未打 tag，回归探针要进本相。 |
| disputes §4 B7 验收 | 「std::vec 现有基准与手写直接调用同量级」 | impl 函数 `static`，跨单元无法直呼。基准必须是**同一单元内**的 struct+impl，否则测不出。 |
| disputes §8 | 「`ct test` 排除，因为各仓 CI 承担」 | 事实是 7/8 包无 CI、`publish/release` 不编译。排除子命令可以，排除门禁不行。 |
| disputes §9 N1 | 「跨根同名先命中先用」 | 补一条：同根不同目录、两个都加载时，是**静默覆盖且退出码 0**（F1）。 |

### 9.4 清单漏掉的（按严重度）

1. **F1 单元基名即全局身份**（阻断，新增 P20-00）。争议清单完全没有；N1 只覆盖了跨根遮蔽。
2. **F2 命名空间单元不能 `use` 跨单元 trait**（新增 P20-09）。hal 能跑只是因为它是扁平的。
3. **F3 单文件 + `pub trait` 生成不可编译的 C**（新增 P20-10）。教程路径，且与 F2 极易混淆。
4. **F6 `ct build` 不读 `ct.pkg`/`ct.lock`**（新增 P20-12）。争议清单把 C8 只当「警告太软」，
   实际是**两条路只有一条在检查**。
5. **F5 `int` 无宿主**（新增 P20-11，落点在 std 而非编译器）。争议清单未提；它不是编译器 bug，
   而是「没有作用域可见性」的后果，P20-01 落地后才敢让 std 接管 `int`。
6. **F10/F11 包无法自证、编译器无发行产物**（新增 P20-13）。不修编译器，但决定第三方体验。
7. **F13/F14 文档项**：shim 的 `static` 状态是 TU 私有；`MAX_PKG_DEPS 16` 是硬上限。并入 P20-08。

---

## 10. 实施方案

> 前置：`selfhost/check-all.sh` 现有 11 道硬门禁全绿（`check-ast.sh` 465 passed）。
> 新增探针一律**加进已有 gate**，不要新增 `run_gate`——否则要同步改
> `README.md`、`docs/README.md`、`docs/glossary.md`、`issues/README.md` 的 `<!-- gates:N -->`
> 与 `ci.yml` 的文案，纯属自找。

### 10.1 P0（不做则「完整支持」不成立）

#### P20-00（新增，P0）产物身份：按根 + 相对路径镜像，同名即报错

- **改哪个单元**
  - `frontend/module/Unit.h.ct`：新增 `char outrel[256];`。
  - `frontend/module/Module.h.ct`：`emit_unit` 前计算 `outrel`；`:1005`、`:1033`、`:1040`、`:1072`、`:1115`
    五处的路径参数从 `self->units[u].base` 换成 `self->units[u].outrel`（格式串不变）；写文件前对
    `outrel` 的目录部分做一次 `mkdir -p`。`:870`、`:873` 的 `#include` 用依赖的 `outrel`。
  - `backend/emit/Emitter.h.ct`：`:870`、`:873`、`:951` 三处 `#include "%s.h"` 改用 `units[u].outrel`。
  - `selfhost/check-ast.sh`：`"$work/astsrc"/*.c` 与各处 `$work/<case>/<base>.c|.h` 路径断言改为
    `find "$work/astsrc" -name '*.c'`；`selfhost/check-all.sh` 里若有同样 glob 一并改。
  - `ct-pkg/std/tools/bootstrap-ct.sh`：cc 行同样从 glob 改成 `find`。
- **怎么改**：`outrel = <root-label>/<源相对路径去掉 .ct>`。`root-label` 是该单元所属 `-I` 根的目录名
  （入口单元用其所在目录名，`.ctbuild` 之外的目录名不做 API 承诺）。产物写
  `out/<outrel>.c|.h`，`#include "<dep.outrel>.h"`，cc 行列 `out/<outrel>.c`，`-I <outdir>` 不变。
  加载完成后做一次全表检查：任意两个非 map 单元的 `outrel` 相同 → `error: two units share the
  output name '<outrel>': '<path a>' and '<path b>'`，退出非零。
- **验收**
  - P-A（`a/Thing.h.ct` + `b/Thing.h.ct`）不再静默覆盖；两个 `.c` 都存在，`main` 运行 rc=0。
  - 极端探针：两个 `-I` 根的目录名也相同 → 报上面那条错，不再产出错误产物。
  - 两个包各带 `Str.m.ct` + `Str.shim.h` → 由现有 shim 检查报错（不变），且**不会**再出现同名 `.c`。
  - `check-ast.sh` 与 `bootstrap-ct.sh` 自举仍绿。
- **golden**：没有 C 文本 golden；但 `check-ast.sh` 内约 30 处生成物路径断言必须同步改。**必须单独提交**。
- **合并**：不与任何项合并。

#### P20-01（P0）限定类型宿主派发（实现，不是文档）

- **改哪个单元**：`frontend/parse/Expr.h.ct`（`parse_primary` 的 `is_call` 分支，`:2114-2132`）、
  `backend/emit/Emitter.h.ct`（新增 `aux == 7`，紧跟 `:2733` 的 `aux == 6`）、
  `docs/language-spec.md`（§4.12 类型宿主一节）。
- **怎么改**
  1. `find_func` 失败后，若 `qpath`（如 `a_ALen`）或 `seg[0]`（如 `ALen`）命中
     `static AND type_host` 的 trait，则解析实参，取首参节点调 `self->sup->expr_type(...)` 得 `rt`；
     构造 `N_MCALL`：`aux = 7`、`text = rt`、`text2 = 方法名`、`text3 = trait 的 C 名`、
     `a = 首参`、`b = 其余实参链`。找不到才回退到原来的 `no function of that name`。
  2. Emitter `aux == 7`：按 `trait + type_key(text) + method` 找唯一 map（**不看是否歧义**，
     这正是显式选择的意义），`emit_recipe(receiver = a, args = b)`。
  3. `aux == 6` 的歧义报文追加两条可直接粘贴的写法：
     `ambiguous …; write 'p1::ALen::len(s)' or 'p2::BLen::len(s)'`。
- **验收**
  - `s.len()` 仍报歧义，且 hint 给出两个写法；
  - `a::ALen::len(s)` 与 `ALen::len(s)`（trait 已被导入）都编译并返回正确值；
  - 不存在的 trait → 仍报原 `no function of that name in that namespace`；
  - 现有全部 `.m.ct` 的未限定调用零变化。
- **golden**：不重生成（新增语法不改既有生成物）；探针加进 `check-ast.sh` 的 type-host 段。
- **合并**：单独提交（parser + emitter + spec 是同一条语义）。

#### P20-02（P0）晚 import 直接报错

- **改哪个单元**：`frontend/parse/Parser.h.ct:789-825`（主循环）。
- **怎么改**：加 `seen_decl`，`namespace` 或任一 `top_decl` 成功即置 1；遇 `import` 且 `seen_decl`
  → `error: 'import' must appear before the first declaration (move it to the top of the file)`。
  `scan_imports` 不动；它此后只需承担「收集前导 import」。
- **验收**：SH-57 两个复现都指向 import 行；全仓语料 + ct-pkg 七包零新增失败（先跑一遍确认没有既有文件把 import 放后面）。
- **golden**：无。
- **合并**：与 P20-03 合并（同属「只加诊断」）。

#### P20-03（P0）映射方法 arity

- **改哪个单元**：`backend/emit/Emitter.h.ct` 的 `aux == 5`（`:2709-2731`）与 `aux == 6`（`:2733-2773`）；
  `frontend/parse/Expr.h.ct:1562-1586` 只改注释。
- **怎么改**：选中 `maps[mi].b[bj]` 后，数 `node.b` 链长度，与 `b[bj].nparams` 比；不等则
  `fail_from(n, "method 'len' takes 1 argument, got 2")`（`aux 6` 的接收者是隐式的，不计入）。
  **不要**改 `Expr.h.ct:1562` 的 `arity_check`：静态 map 在 parse 阶段尚未选中，写在那里只会误报。
- **验收**：`char *s; s.len(1);` 报错并指向调用点；`s.len()` 正常；SH-56 复现转为负例；
  std/zlib/png/sqlite/clib/net-posix 全量构建零新增失败。
- **golden**：无。
- **合并**：与 P20-02。

#### P20-04（P0）`requires` 不满足 = 失败，`--force` 降级

- **改哪个单元**：`tool/pkg/Pkg.h.ct:1561-1584`、`:1282` 调用点、`install_main`/`get` 的参数解析、
  `docs/package-guide.md`。
- **怎么改**：`pkg_check_requires` 返回 1；调用点并入 `rc`；`get`/`install` 识别 `--force`
  （全局 `force` 标志），置位时退回 warning。`verify` 不受影响。
- **验收**：`requires = ct >= 99.0.0` → 非零退出且报文含 `requires 'ct >= 99.0.0', but this is v0.20.0`；
  `--force` → 0 + warning；std 在 v0.19.1 上装失败、v0.20.0 上成功。
- **golden**：无（`test/pkg`）。
- **合并**：与 P20-12（同一条「包清单语义」线）。

#### P20-12（新增，P0）`ct build` 读 `ct.pkg` / `ct.lock`

- **改哪个单元**：`main.ct:110-118`（分发处）、`tool/pkg/Pkg.h.ct`（从 `install_main:1274-1299`
  抽出 `pkg_lock_flags(inc[], ninc, cflags, ldflags)`）、`tool/driver/Driver.h.ct`（只确认
  `--cflags`/`--ldflags` 是追加还是覆盖）。
- **怎么改**：`argv[1] == "build"` 且 `./ct.pkg` 存在时：
  1. 读 `./ct.lock`，逐包 `pkg_check_requires`（硬失败，`--force` 降级）；
  2. 构造新 argv：`ct build <用户原始参数> -I vendor/<pkg>… --cflags "<聚合>" --ldflags "<聚合>"`，
     交给 `ct_driver_run`。
  `Driver` 若当前是覆盖语义，改成追加。用户手工 `-I` 仍完全可用，行为兼容。
- **验收**：消费者目录只跑 `ct build main.ct -o app` 就能链上 zlib（不再需要 `ct install` 打印的那行长命令）；
  删掉 lock 条目 → 失败；`requires` 不满足 → 失败；无 `ct.pkg` 的目录行为零变化。
- **golden**：无。
- **合并**：与 P20-04。

### 10.2 P1（包作者每天会碰）

| ID | 改哪个单元 | 怎么改 | 验收 | golden | 合并 |
| --- | --- | --- | --- | --- | --- |
| P20-05（C9） | `ct-pkg/index/tools/refresh-index.sh`；`Pkg.h.ct:1464 pkg_index_lookup` | 每个 `v*` tag 一行（尾字段 `requires`）；lookup 过滤「range + 当前编译器版本」后取最高；旧五字段行照旧 | 索引同时有 std 0.1.x/0.2.0；v0.19.1 选旧版、v0.20.0 选新版 | 无 | 单独（跨 ct-pkg/ct 两仓，两个提交） |
| P20-06（C10/N1） | `Pkg.h.ct`（读 `namespace =`）；`Module.h.ct:277-340 resolve_import`、`:347-430` 加载 | 先试 `<root>/<去掉第一段的 rel>`，再回退原路径；两个根命中同一 rel → 报错列两路径 | 平铺 `std/str/String.m.ct` + `namespace = std` 能导入；旧 `std/std/...` 仍可；两包同名 `Uart` 报错 | 无 | 单独；**必须排在 P20-00 之后** |
| P20-09（新增，F2） | `Parser.h.ct:1693 parse_use_list`、`:1449` 检查；必要时 `Symbols.h.ct resolve_type` | 先打点确认是 alias 未登记还是 `ns+name` 抢先命中；修 `use` 的 trait 解析走与类型相同的别名路径 | P-E 通过；std/test 形态不变；未导入的 trait 仍报原错 | 无 | 与 P20-10 |
| P20-10（新增，F3） | `Emitter.h.ct:869`（`.c` 是否 include 自己的 `.h`）、`Module.h.ct:1030`（`.h` 只给 `is_hdr`） | `.h` 对「含 pub 声明」的单元也写；`.c` 的 include 条件从 `is_hdr` 改为「本单元写了 `.h`」 | P-C（单文件 + `pub trait` + `impl`）通过；教程单文件跑通 | 单文件含 pub trait 的生成物多一行 include → 更新对应断言 | 与 P20-09；若 diff 大则拆开 |
| P20-11（新增，F5） | `ct-pkg/std/std/num/Num.m.ct`；`docs/primitive-methods.md` | 给 `int` 建宿主（字符方法委托给 `char`）。这是包侧改动，不动编译器；排在 P20-01 之后才安全 | `int n; n.toString()` 与 `'7'.isDigit()` 工作；与第三方 `int` 宿主同时导入时未限定报歧义、可限定调用 | 无 | 包仓单独提交 |
| P20-13（新增，F10/F11） | `ct-pkg/tools/publish-package.sh`、`release-package.sh`；新增 `ct-pkg/tools/ci-template.yml` | publish 前强制 `ct build`（无 `ct` 则拒绝并给指引）；约定 `tests/run.sh`；CI 模板跑 `bootstrap-ct.sh` + `tests/run.sh` | 故意写坏一个包 → publish 失败；模板在 zlib 跑通 | 无 | ct-pkg 单独提交 |

### 10.3 P2（不阻塞，但决定体验）

- **P20-07（B7）去虚拟化**：`Emitter.h.ct:2789-2806`。只在「接收者静态类型是具体 struct **且 impl 在本单元**」
  时发直接调用；iface/trait 值仍走 vtable。**验收基准改成同单元 struct + impl**，
  不能用 `std::vec` 跨单元基准（impl 是 `static`，跨单元根本没有直接调用的符号）。若同单元实测无收益，
  本项降级为「只写 vptr ABI 文档」。golden：有 diff，单独提交。
- **P20-08（原 P2）文档与文案**：`.m.ct` 错误补 `put the C implementation in <base>.shim.h`；
  `unsupported requires` 补 `use dep = pkg@range for package dependencies`；
  package-guide 明确 **`.h.ct` 可以导出函数**、std 为何仍用 shim（三条代价）；
  `.m.ct` 的最简形态是「`.m.ct` + `.shim.h`（+ `.shim.c`）」；
  shim 的 `static` 状态是 **TU 私有**，要共享状态必须走 `.shim.c`；
  `MAX_PKG_DEPS 16` / `MAX_PKG_DEPTH 8` 是被文档化的硬上限。
- **发布前置（N3）**：`CTC_VERSION` 四处（l0/l1/l2/ct-ast）同步 bump `0.20.0`，并确认 `915c12c` 在 tag 内；
  发布说明写明「`requires` 现在是硬失败，v0.19.1 用户无法安装 std 0.2.0」。

### 10.4 提交切分（可直接照做）

| 提交 | 内容 | 是否改生成物 |
| --- | --- | --- |
| ① | P20-00 | 是（产物路径与 include 行）；单独 |
| ② | P20-01 | 否 |
| ③ | P20-02 + P20-03 | 否 |
| ④ | P20-04 + P20-12 | 否 |
| ⑤ | P20-09 + P20-10 | 可能（单文件 pub trait 的 include） |
| ⑥ | P20-06（依赖 ①） | 否 |
| ⑦ | P20-05（ct-pkg + ct 各一） | 否 |
| ⑧ | P20-07 | 是；单独 |
| ⑨ | P20-11（ct-pkg/std） | 否 |
| ⑩ | P20-13（ct-pkg/tools） | 否 |
| ⑪ | P20-08 文档 + 版本 bump | 否 |

### 10.5 终局判断

做完 P0 + P1 后，包作者剩下的墙是：

1. **同名方法的调用要写全限定名**（P20-01 后可选，不是不可用）——取舍，不是限制。
2. **`.m.ct` 三文件形态**——零产物约束的直接代价，取舍。
3. **`use` 的 vptr 改变结构体布局**——ABI 取舍，必须写进包文档。
4. **没有泛型 / 没有包级作用域可见性**——真正剩下的技术限制，属 Phase 21+。

F1（同名单元静默覆盖）是唯一「会让人以为成功、实际丢代码」的问题；它不在争议清单里，
却必须在 P20-01 之前修。其余项做完之后，「两个包能不能共存」的答案是：
**能，但第一次要写限定名，且两个包不能有同名单元**——后者在 P20-00 之后会变成一条明确的错误，
而不是一份错误的产物。
