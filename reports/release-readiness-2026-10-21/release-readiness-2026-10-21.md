# 发布前遗留问题分析（2026-10-21）

| 项 | 值 |
| --- | --- |
| 源码锚点 | `294d7fb`（本轮评审修复收尾：`84c6677` / `015946a` / `776bfc3` / `294d7fb`） |
| 对应评审 | [review-2026-10-21-round2](../review-2026-10-21-round2/review-2026-10-21-round2.md) |
| 范围 | 本轮**未修**的 3 条（SH-9 / SH-10 残余 / SH-12）+ 准备本报告时新发现的 1 条（SH-11 附带缺陷） |
| 结论 | **没有阻断发布的缺陷**；§2 / §3 / §4 / §5 均已在报告之后修复（见 §8），无遗留项 |

> **处置更新（2026-10-21，紧随本报告）**：用户批准后，§2（SH-9）、§5（SH-11 附带缺陷）、§4（SH-12，
> 方案 A）与 §3（SH-10 残余）全部落地。落点见 §8。

---

## 0. 一句话结论

- 唯一会**产出崩溃二进制**的问题（SH-8）已修。
- 剩下三条都是「诊断体验 / 示例入口 / 生成物告警」，不影响编译器正确性，**不阻断发布**。
- 但我在复核自己的 SH-11 修复时发现：那条**新**错误的位置指向文件末尾、且留下半截 `.c`。这是我引入的，
  建议发布前修掉（小改动，§5）。

| 分级 | 条目 | 判断 |
| --- | --- | --- |
| ~~P1~~ ✅ 已修 | §5 SH-11 附带缺陷（错误位置 + 残留产物） | 见 §8 |
| ~~P2~~ ✅ 已修 | §2 SH-9 诊断格式统一 | 见 §8 |
| ~~P3~~ ✅ 已修 | §3 SH-10 残余（未引用 vtable / Drop） | 改用 `__attribute__((unused))`，见 §8 |
| ~~P3~~ ✅ 已修 | §4 SH-12（map 无 examples 正例） | 方案 A：新例子 + `//@ct-requires:` 跳过标记，见 §8 |

---

## 1. 先看清「未修」的三条到底是什么

这三条很容易被误读成「编译器有问题」，实际上都不是：

| ID | 一句话 | 影响谁 |
| --- | --- | --- |
| SH-9 | 报错文案没有文件名和列号 | 看日志的人 / 编辑器跳转 / 多文件 build |
| SH-10 残余 | 生成的 C 里有些 `static` 符号没人用，cc 会告警 | 用 `-Wall -Wextra` 或 `-Werror` 编产物的人 |
| SH-12 | `examples/` 里没有 map 的例子 | 想快速看懂 map 的新用户 |

下面逐条拆开。

---

## 2. SH-9：诊断格式不统一（P2，可不修但值得修）

### 2.1 现在的实际输出：三种形态并存

同一个 `ct` 二进制，三种错误三种长相（均为本轮实测）：

```text
# ① 语义期（重复 trait）——符合文档
/tmp/r3/dup.ct:2:9: error: duplicate trait 'T'
ctc: 1 error(s) generated

# ② 解析期（语法错误）——没有文件名、没有列号
ctc: line 2: expected an expression (at ';')

# ③ 驱动期（打不开输入文件）——位置是假的，凭空多出 "line 1:"
ctc: line 1: cannot open the input file (at '')
```

③ 最能说明问题：文件根本还没被读进来，编译器却报「第 1 行」。**这个位置是上一轮遗留在缓冲区里的状态**，
不是真位置。

而 `README.md` / `docs/tutorial.md` / `docs/glossary.md` / `AGENTS.md §4` 四处都写「错误格式为
`文件:行:列: error: 描述`」。所以 ① 合规，②③ 不合规。

### 2.2 根因：一条缓冲同时装两种消息

`ParseSupport` 只有一个 `errmsg[160]`，而下面四类生产者都往里写：

- 解析器自己（`sup->fail`）——**应该带位置**
- `Symbols` / `TypeCheck` / `Memory` 的错误，经 `sup->fail` 转发——大多**应该带位置**
- `Module` 的 I/O 与构建配置错误（`cannot open the input file`、`too many units`、`too many imports`）——**不该带位置**
- 发射器 `Emitter::fail` 的 27 处错误——有的该带（源码问题），有的不该（`cannot write the output file`）

打印侧同样混在一起：`driver.ct` 5 处、`Module.h.ct` 7 处，共 **12 个 `fprintf(stderr, "ctc: %s")`**，
全部无差别地加 `ctc: ` 前缀。其中只有 2 处（`driver.ct:234`、`Module.h.ct:616`）是真正的解析失败。

所以「加个文件名」不是改一行格式串，而是**先把两条错误通道拆开**：谁有位置、谁没有，得在记录时就决定，
而不是在打印时猜。

### 2.3 为什么我没有顺手改

1. 改完会动到 **12 个打印点 + 4 个生产者**，以及 `check-ast.sh` 里依赖 `^ctc: ` 的断言（现有 4 处）。
2. `docs/design/phase10.md` 的**非目标**明确冻结了「`ctc:` 驱动错误前缀」（SH-3 决策）。要改就得区分
   「驱动错误保留前缀」与「源码诊断改成 `file:line:col:`」——这是需要你拍板的口径问题，不是实现问题。
3. 它不影响编译结果，只影响读日志的人。**不是发布阻断项。**

### 2.4 如果要修，建议的形状

| 步骤 | 内容 | 触及 |
| --- | --- | --- |
| 1 | `ParseSupport` 增加 `fail_at(line, msg)`，记录位置；`fail` 保持裸消息 | `ParseSupport.h.ct` |
| 2 | 解析期/语义期统一走 `file:line:col: error:`；I/O 与配置错误走 `ctc: msg` | `Parser.h.ct`、`Module.h.ct`、`driver.ct` |
| 3 | 同步 `check-ast.sh` 的 4 处断言与 12 个负例的期望形态 | `selfhost/check-ast.sh` |
| 4 | 文档确认：§4 的格式只描述「源码诊断」，驱动错误单列 | `AGENTS.md`、`README.md` |

代价：一次全量门禁 + 改 4 处断言。收益：③ 那种「假位置」消失，编辑器能按 `file:line:col` 跳转，
多文件 build 能说清是哪个单元。

**我的意见：值得做，但不该和这次发布捆在一起。** 它是一次独立的「诊断通道」小阶段。

---

## 3. SH-10 残余：生成物里的 `static` 符号没人用（P3，建议不修）

### 3.1 现状

`_self` 那条已经修掉了（方法体不引用 `self` 时补 `(void)_self;`）。剩下两类，共 **7 个语料文件**：

```
test/cases/04_signatures.ct              unused variable 'Dict_Hashable_vtable'
test/ast/13_map_instance/prog.ct         unused variable 'uart1_Controller_vtable'
test/modules/sig_mismatch{,_json}/       unused variable 'S_T_vtable'
test/modules/map{,_file,_file_build}/    unused function 'Person_Drop_drop'
```

原因是结构性的：**一个 `impl` 就发一份 vtable，一个 `use Drop` 就发一个 `Drop_drop`**，编译器不做
「这个 trait 的方法在本单元被调用过吗」这种跨过程可达性分析。那 7 个文件恰好声明了 trait / Drop
却从没调用过。

### 3.2 三种可选做法

| 方案 | 做法 | 代价 | 我的评价 |
| --- | --- | --- | --- |
| A 可达性分析 | 扫描整个单元，没被引用就不发 | 大；算漏了会变成**链接期缺符号**，比告警危险得多 | 不建议为告警做这个 |
| B `__attribute__((unused))` | 给这些 `static` 符号加上属性 | 小 | 会把 GCC/clang 扩展写进「可读的普通 C」产物，与项目卖点冲突 |
| C 记为限制 | 文档写清，用户自己抑制 | 零 | **推荐**（已写入 language-spec §6.2，中英） |

### 3.3 影响面

只是告警，不是错误：产物能编、能跑、行为正确。只有把告警当错误（`-Werror`）的人会受影响，而这类人
本来也会先看 `README` 的编译参数说明。

**我的意见：不修，保持已文档化的状态。** 如果将来真要做，应该是 A 的一个受限版本（只在「本单元完全
没有该 trait 的任何派发」时省略 vtable），而不是 B。

---

## 4. SH-12：`map` 缺「逛仓库就能看到」的正例（P3，可不修 / 或花 5 行修）

### 4.1 先纠正报告里的一条过时结论

报告说「tutorial.md 章节 0–13 里没有任何 map 相关的段落或示例」——这条**已经不成立**了。
[`docs/tutorial.md` §9](../../docs/tutorial.md) 就是「`map` 与 bindings：把 trait 绑到已有的 C 库」，
带完整可粘贴示例、硬约束说明和「只在 ct-ast 支持」的提示。报告锚点之后补的，属于旧结论。

### 4.2 真正缺的是什么

缺的是 **`examples/` 和 `test/cases/` 里的例子**。而这两个目录有一个硬约束：

> `test/run.sh` 的 examples 层用的是 **L0**（`$TMP/ctc`）编译。

L0 不认识 `map`，会把 `map trait Controller for instance uart1 {` 整行当普通 C 透传，随后 cc 报错。
所以「往 examples 放一个 map 例子」不是加文件就行，得先给门禁加一条「本用例需要 ct-ast」的约定
（`07_dialect` 现在靠「目录里有 `ct-dialects/`」间接跳过，算是先例但不是通用机制）。

### 4.3 map 现在其实被三层覆盖着

| 位置 | 覆盖什么 | 谁在跑 |
| --- | --- | --- |
| `test/ast/13_map_instance` | map 声明 + 包装函数生成 | `check-ast.sh` |
| `test/ast/14_map_dispatch` | 装箱后经 vtable 派发（端到端） | `check-ast.sh` |
| `test/ast/15_map_args` | CALL 参数子集 | `check-ast.sh` |
| `test/modules/map*`（7 个目录） | 单文件 / build / `--emit-map` / 不可写 | `check-ast.sh` |
| `docs/tutorial.md` §9 + `bindings/mock-hal/` | 用户视角的完整用法 | 人工 |

也就是说：**功能有测试、有文档，缺的只是「在 examples 目录里点得开」**。

### 4.4 两个选择

| 方案 | 内容 | 代价 |
| --- | --- | --- |
| A | `examples/08_map_binding/` + `test/run.sh` 支持 `//@ct-requires: ct-ast` 跳过标记 | 约 10 行（例子 + 跳过逻辑 + 文档一句） |
| B | 维持现状，在 `README` 的示例清单里点明「map 例子见 `test/ast/14_map_dispatch`」 | 约 2 行 |

**我的意见：A 更好看，B 更保守。** 两者都不阻断发布；A 需要你同意引入一个新标记约定（门禁约定变动我
不擅自决定）。

---

## 5. 新发现：我给 SH-11 加的那条错误有两个附带缺陷（**P1，建议发布前修**）

这一条不在评审报告里，是我准备本报告、复核自己改动时发现的，必须如实说明。

### 5.1 现象

复现（`/tmp/r3/order.ct`，出问题的是**第 22 行**）：

```c
    int x = 0;
    x = (gi++) + mk().m();       /* 第 22 行 */
    printf("x=%d gi=%d\n", x, gi);
    return 0;
}
```

```text
$ ct order.ct -o order.c
ctc: line 25: a method call on a temporary is only allowed at the start of a statement or of an assignment (at '')
exit=1

$ ls -l order.c
-rw-r--r--  774  order.c        # ← 残留半截产物
$ tail -2 order.c
    int x = 0;                  # ← 文件写到这里就断了
```

两个问题：

1. **行号错**：报 `line 25`（文件最后一行），真凶在 22 行。这一行来自发射阶段：此时解析早已结束，
   词法器的「当前 token」停在 EOF，`sup->fail` 就把它当成了出错位置。
2. **留产物**：`.c` 是先 `fopen` 再发射的，发射中途失败就留下半截文件。而 Phase 10.4 的多错误恢复
   明确承诺「错误不留产物」，SH-8 的解析期错误也确实做到了（因为它在 `fopen` 之前就失败）。

### 5.2 为什么必须修，而不是记进文档

- 行号错**比没有行号更糟**：用户会去第 25 行找一个不存在的表达式。
- 半截 `.c` 会被 `#include` 或 Makefile 当真产物，属于「静默生成坏文件」。
- 这两个缺陷是我这次改动**新引入**的路径，不是历史包袱。

### 5.3 修法（小，不动现有文案）

| 步骤 | 内容 | 触及 |
| --- | --- | --- |
| 1 | 发射器记录出错节点的行号（`N_MCALL` 自带 `line`），并暴露一个访问器 | `Emit.h.ct` |
| 2 | `ParseSupport` 增加 `fail_at(line, msg)`：位置由调用方给，而不是取当前 token | `ParseSupport.h.ct` |
| 3 | `Module::emit_program` 转发发射器错误时改用 `fail_at`（行号有效时） | `Module.h.ct` |
| 4 | 发射失败时删除半截 `.c`（`driver.ct` / `Module::emit_unit`） | `driver.ct`、`Module.h.ct` |

对**既有**错误文案零影响：只有行号已知（`> 0`）时才用 `fail_at`，其余照旧。新增 1 个字段、
2 个 pub 包装器（`MAX_FUNCS` 余量足够）。

注意：这一步只让**新错误**位置正确，**并不等于**修好 SH-9——整体格式统一仍是 §2 那件事。

---

## 6. 发布就绪度判断

### 6.1 我的结论：可以发布，但建议先补 §5

| 维度 | 判断 |
| --- | --- |
| **正确性** | 无已知缺陷。SH-8（唯一会产崩溃二进制）已修，且有负例与断言钉住 |
| **回归面** | 八关全绿：`test/run.sh` 118 / pkg 35 / `check-ast` 138 / acceptance 20 pass 0 pending / `check-all: OK (8 hard gates green)` |
| **可移植性** | macOS（Apple clang）+ Debian 12（gcc 12，arm64 容器）双向验证；GCC 警告集与 BSD 探针已做平台适配并文档化 |
| **自洽性** | 干净 clone 可独立跑通全部门禁 |
| **已知限制** | 已在 language-spec §6.2 / tutorial §11 文档化；无「静默出错」项 |

### 6.2 如果按「先修 §5 再发布」

工作单元建议如下（一个提交一件事）：

1. `fix(codegen): keep the position of an emitter diagnostic`（§5 步骤 1-3）
2. `fix(driver): drop a half-written artefact on emit failure`（§5 步骤 4）
3. 或者把两者合成一个 `fix(diagnostics): report the node's line and clean up` —— 二者是同一个失败路径

补完后需要重跑：`bash selfhost/check-all.sh`（八关）+ 手工三件套 + 上面那个 `order.ct` 复现。

### 6.3 如果**现在**就发布

需要在 tag 说明里写清两条已知行为，避免用户以为是 bug：

- 表达式中间的右值接收者会被拒绝，但报错行号指向文件末尾（内容正确、位置不准）；
- 该失败会留下半截 `.c`，请删除后重试。

我**不推荐**带着这两条发布——第一条尤其容易让人误判成「编译器在瞎报」。

---

## 7. 附：本轮已修清单（供对照）

| ID | 状态 | 提交 |
| --- | --- | --- |
| SH-8 impl 完整性 | ✅ | `84c6677` |
| SH-7 嵌套 vptr 重复初始化 | ✅ | `015946a` |
| SH-11 右值接收者越界提升 | ✅（位置/产物见 §8） | `015946a` + §8 |
| SH-10 `_self` 未使用 | ✅（残余见 §3） | `015946a` |
| DOC-18/19/20/21 | ✅ | `776bfc3` |
| 报告与 issue 归档 | ✅ | `294d7fb` |

---

## 8. 处置记录（2026-10-21，报告之后）

### 8.1 落点

| 内容 | 落点 |
| --- | --- |
| 诊断通道拆分 + SH-11 位置/产物 | `9050ed2` |
| SH-12：map 例子 + `//@ct-requires:` 跳过标记 | `e383798` |
| SH-10 残余：`__attribute__((unused))` | 本文 §8.3 |

### 8.2 改了什么

`ParseSupport` 从「一个缓冲 + 一种格式」变成「一个缓冲 + 记录位置」：

| 入口 | 用途 | 打印形态 |
| --- | --- | --- |
| `fail(msg)` | 解析期 / 语义期源码诊断，位置取当前 token | `file:line:col: error: msg` |
| `fail_at(line, msg)` | 调用方知道位置（发射器按 AST 节点报错） | 同上，行号由调用方给、列固定 1 |
| `fail_driver(msg)` | I/O、路径、上限、`Module` 构建错误 | `ctc: msg`（无位置） |
| `report()` | 12 个打印点统一收口；未记录消息时不输出空行 | 按记录时的形态 |

配套：

- `Emitter` 记录出错节点的 `line`（新增 `fail_from(n, msg)`，覆盖 9 个源码级失败点），对外暴露
  `ct_emit_error_line()`；`Module::fail_emit` 据此选择 `fail_at` 或 `fail_driver`。
- 发射失败时删除已打开的半截 `.c`（`driver.ct` 的 compile 路径、`Module::build_main` 的 build 路径）。
- build 模式发射前把 `mem->path` 指向当前单元，保证诊断里的文件名是该单元。
- `check-ast.sh`：负例循环改为要求 `file:line:col: error:`；新增一条断言，钉住「右值接收者报在自己的
  行、且不留产物」。
- `docs/tutorial.md`（中英）区分「源码诊断」与「驱动层错误」两种形态。

### 8.3 后续修复（同日）

- **§3（SH-10 残余）**：不再走「可达性分析」，改用发射器侧标注——vtable 的前向声明与定义、
  map 实例 vtable、`Drop_drop` 的定义一律加 `__attribute__((unused))`。之前担心的「扩展写进产物」已经
  不成立：生成物早就在用 `__attribute__((constructor))`（`__ct_init`），两者同源。
  属性必须写在**声明符之前**（`static void __attribute__((unused)) f(void)`）——写在参数列表之后时
  clang 报 `-Wgcc-compat`，这是第一版踩到的坑。
  复扫 69 个生成物：发射器产出的告警归零，只剩 5 条源文件层面的告警（3 个 leak fixture 的 `p` unused、
  2 个 sig_mismatch fixture 的 `-Wreturn-type`）。
- **§4（SH-12）**：方案 A 落地——`examples/08_map_binding/`（两个实例、各一份 vtable）+ `test/run.sh`
  的 `//@ct-requires: ct-ast` 跳过标记；例子实际由第 8 关的语料等价层编译运行（check-ast 139 → 140）。

### 8.4 诊断形态（§2 / §5 的验证）

```text
$ ct order.ct -o order.c
order.ct:22:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
$ ls order.c        # No such file or directory

$ ct bad.ct -o bad.c
bad.ct:2:11: error: expected an expression

$ ct nope.ct -o nope.c
ctc: cannot open the input file

$ ct dup.ct -o dup.c
dup.ct:2:9: error: duplicate trait 'T'
ctc: 1 error(s) generated
```

### 8.5 全量门禁

`bash selfhost/check-all.sh`：八关全绿（`test/run.sh` 118 — examples 层对 08 标 `skip`；pkg 35；
`check-ast` 140；acceptance 20 pass 0 pending；`check-all: OK (8 hard gates green)`，EXIT=0）。
手工三件套输出不变。

