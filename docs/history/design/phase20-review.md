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
