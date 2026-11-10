# SH-60 · 静态映射调用点缺少实参类型检查

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`Expr` / `TypeCheck`）；std 为触发场景 |
| 严重度 | **High** |
| 锚点 | commit `a1c523a`（2026-11-07，`v0.20.0`）；裁决 2026-11-09 |
| 文件 | [TypeCheck.h.ct:75-129](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L75-L129)（`type_key` 丢弃 `const` / `volatile`）；[Emitter.h.ct:424](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L424)（同一张表的副本 `map_type_key`）；[Expr.h.ct:205-231](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L205-L231)（实参比较前的 `tnorm`）；[Expr.h.ct:1109-1122](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1109-L1122)（`argtype_check_static`，静态调用点的硬错）；[Expr.h.ct:2560-2569](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2560-L2569)（`aux == 6` 的多候选判定） |
| 状态 | **2a 已修复**（2026-11-10，`v0.26.4`）；1a/1b 待 D-60-1，2b 仍 deferred（见「子项去向」） |

## 现象

`.m.ct` 的静态映射（`map trait … for type`）在调用点不校验实参类型，`ct compile` 退出 0：

```c
/* 2a：实参类型不校验（实测 rc=0） */
import std::str::String;

int main() {
    return "abc".find(42);      /* 42 被当作 const char * */
}
```

```c
/* 2b：不存在的参数类型，编译通过 */
#include <string.h>

namespace probe;

pub trait Totally {
    int f(TotallyBogus *p);     /* 全仓没有这个类型 */
}

map trait Totally for type char * {
    f(s, p) -> strlen(s);
}
```

同一族的第二类现象（顶层 `const` 接收者被就地写）见子项二：

```c
/* 1a：字面量接收者调用会写接收者的方法（实测 rc=0，运行 SIGBUS 138） */
import std::str::String;

int main() {
    "abc".toUpper();
    return 0;
}
```

```c
/* 1b：显式 const 接收者，同样通过 */
import std::str::String;

int main() {
    const char *s = "abc";
    s.toUpper();
    return 0;
}
```

> std 包迁入 ct-pkg 后其方法与文件形态仍在调整；本条判据是**编译器行为**，不绑定 std 的具体签名与行号。

## 裁决（2026-11-09）

- 原命题「`.m.ct` 签名类型**仅作装饰**」**被推翻**：声明类型决定 `sizeof`，返回类型参与
  `expr_type` 推导，签名并非不参与编译。
- 但「签名已经约束调用者」**同样不成立**：四种静态调用形态均静默通过，且删掉
  [Expr.h.ct:1696](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1696) 的 `!is_static` 豁免是**空操作**
  （说明该豁免并不承担实际的类型检查）。
- 结论：缺陷边界收窄为「**静态映射调用点缺少实参类型检查**」，与「签名装饰性」无关；
  接收者可变性与声明点类型解析拆为独立子项。

## 历史评估（2026-11-07 立项时的判断；已被 2026-11-09 裁决推翻/取代）

> 以下五节是 2026-11-07 立项时的原始记录，按记录完整性保留，**不代表现行口径**。
> 其中「路线 A / 路线 B」「分三步修复」「另开排期」均已被 2026-11-09 裁决推翻或取代：
> 命题收窄为「静态映射调用点缺少实参类型检查」，接收者可变性与声明点类型解析拆为独立子项
> （见下方「子项去向」）。保留原文是为了留下当时的取舍依据，不要按本节排期。

### 期望行为（原）

1. **接收者诊断**：字面量或顶层 `const` 接收者调用「会写接收者」的方法时，编译期给出诊断。
   口径沿用 P20-03：`ct build` / `ct compile` 下按 `warning:` 打印、退出 0；`ct check` 下同一记录
   升为 `error:`、退出 1。文案点名方法，并说明「writes its receiver」。
   正例必须保持安静：`"abc".len()`、`char buf[8]; buf.toUpper()`。
2. **`.m.ct` 参数类型检查**：
   - 调用点：静态 trait（`map trait … for type`）的实参进入与普通 trait 方法相同的 19.2 粗粒度比对
     （`"abc".find(42)` 至少出 warning，`ct check` 下 error）；
   - 声明点：trait 方法参数里无法解析的类型名必须报错（`TotallyBogus *`）。

### 技术路线评估（原）

#### 路线 A：trait 方法标注接收者可变性（`mut self` 方向）

CT 的 trait 方法**没有显式 `self`**（声明形如 `int len();`，`self` 由 `impl` 侧隐式声明），
所以不能照抄 `mut self`，需要先定拼写，例如 `int toUpper() mut;` 或 `mut int toUpper();`
（决策点 D-60-1）。

| 维度 | 代价 |
| --- | --- |
| 前端 | Lexer 加一个上下文关键字（`mut` 今天是普通标识符，需先查冲突）；trait 声明解析加可选标注 |
| 表结构 | `Symbols` 的 trait 方法表加 1 个 flag（不改节点、不改 ABI） |
| 调用点 | 判定接收者是否字面量 / 顶层 `const`，与 flag 组合出诊断；复用现有 `type_warn` 通道 |
| 生成物 | **不变**：vtable 槽位、mangled 名、golden 全不受影响 |
| 兼容性 | 默认不标注 = 今天的行为，零回退；覆盖率取决于作者标注纪律 |
| 配套 | ct-pkg 的 std 标注 `toUpper` / `toLower` / `copyFrom` 三个方法；spec / tutorial 各一段 |

**判定（原）：推荐作为打底。** 它把「会不会写」变成显式契约，成本集中在一个 flag + 一条调用点检查，
不碰类型键，也不会让字面量的读方法失配。**（已被 2026-11-09 裁决取代：接收者可变性移出 Phase 25，
待 D-60-1 决策。）**

#### 路线 B：类型键保留顶层 `const`，`char *` 与 `const char *` 分属不同宿主

| 维度 | 代价 |
| --- | --- |
| 归一化 | 三处必须同步改：[TypeCheck.h.ct:82](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L82) 的 `type_key`、[Emitter.h.ct:424](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L424) 的 `map_type_key`、[Expr.h.ct:208](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L208) 的 `tnorm` |
| 匹配面 | 宿主匹配（[Expr.h.ct:1629-1634](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1629-L1634)、[Emitter.h.ct:2767-2776](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2767-L2776)）与 `impl` 的 trait 匹配一起受影响 |
| 直接后果 | **今天所有字面量 / `const` 接收者的读方法都会失配**（`"abc".len()` 找不到 `char *` 宿主），std 大面积回退 |
| 补救的循环 | 要避免回退，只能让 `char *` 宿主「有条件」接受 `const` 接收者；而「有条件」就是「这个方法会不会写」，编译器仍然不知道，于是又绕回 A |
| 其他 | `impl` 在 `const T *` 接收者上的解析、71 个 golden 的重生成风险；ct-pkg 若不改，每个写方法要复制一份 `for type const char *` 绑定 |

**判定（原）：单独实施是回归，不是修复。** 它可以作为 A 落地后的后续细化（若将来要区分指针层级的
`const`），但不能替代 A。**（已被 2026-11-09 裁决取代：路线 A/B 均不作为 Phase 25 的方案。）**

### 归属建议（原）

**另开排期（本条 SH-60），不并入 Phase 20。** 理由：

1. Phase 20 已随 `v0.20.0` 收口，P20-02 / P20-03 均已 landed；往回加项会破坏 roadmap 的版本口径
   与已关闭的验收清单。
2. 参数类型检查与 P20-03 同族，但可以直接复用 19.2 的 `argtype_check`，**不需要新语法**，
   适合作为 `v0.20.x` 补丁先落。
3. 接收者可变性标注要改语言表面（trait 方法语法），超出「包支持」的收口范围，应单独立项
   （Phase 24 候选，或 0.21 之后）。

**（已被 2026-11-09 裁决取代：实参类型检查并入 Phase 25 / 25.1；接收者可变性另立子项。）**

### 修复建议（分三步，前两步互不依赖）（原）

1. **补丁级（无新语法）**：去掉 [Expr.h.ct:1696](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1696) 的
   `!is_static` 豁免，让 `.m.ct` 静态 trait 的实参走 19.2；补 `"abc".find(42)` 负例。
2. **声明级**：在 trait 声明解析处校验参数类型可解析——CT 内建、本单元或导入单元的 struct / union /
   enum / trait / 类型别名；C 头引入的类型（`size_t` / `FILE *` 等）如何豁免见决策点 D-60-2。
3. **语言级**：A 路线落地 `mut` 标注与调用点诊断；std 标注三个写方法。

**（已被 2026-11-09 裁决取代：第 1 步并入 25.1；第 2 步归子项三「声明点未知类型」；第 3 步移出本相。）**

### 验证（原）

- 1a / 1b 在 `ct check` 下报 `error:`、`ct build` 下 `warning:` 且退出 0；生成物不变；
- 2a 在 `ct check` 下报 `error:`、`ct build` 下 `warning:`；2b 在两种模式下都报 `error:`；
- 正例：`"abc".len()`、`"abc".compare("x")`、`char buf[8]; buf.toUpper()` 零诊断；
- `check-ast.sh` 增两条负例断言（接收者、实参），`test/modules` 增一条 `.m.ct` 未知类型负例；
- ct-pkg `std` 的 `tests/run.sh` 全绿；`bash selfhost/check-all.sh` 保持全绿。

**（已被 2026-11-09 裁决取代：现行判据见文末「验证（并入 Phase 25 / 25.1 后的判据）」。）**

## 子项去向

| 子项 | 状态 | 去向 |
| --- | --- | --- |
| 静态映射调用点缺少实参类型检查 | **已修复**（2026-11-10） | 25.1 已接入 19.2 比对但只出 warning；本轮把四个静态形态的确信不匹配升为硬错，见「处置（2026-11-10）」 |
| 顶层 `const` 接收者不区分 | 待 D-60-1 决策 | 依赖「接收者可变性」的语言表面拼写（`mut self` 方向），不在 Phase 25 范围内 |
| 声明点未知类型不报错（`TotallyBogus *`） | **deferred** | 等 D-60-2；属「头文件 typedef 透传」设计的一部分 |

## 处置（2026-11-10，`v0.26.4`）

**现状核对。** Phase 25.1 已把四个静态调用形态接进 19.2 的逐位比对（`argtype_mismatch` +
`tnorm`）：`aux == 6`（`recv.find(42)`）、`ns::Trait.method`、`ns::method`、`Trait::method(recv, …)`。
但比对结果走 `type_warn`，`ct build` / `ct compile` 仍是 `warning:` + 退出 `0`，`"abc".find(42)` 照样
「能编译过」；`ct check` 是单单元入口，看不到被 `import` 的映射单元，结构上无法兜底。

**争点（battle）。**

| 主张 | 判据 | 结果 |
| --- | --- | --- |
| A：维持 19.2 口径，静态调用点也按 warning | 严重级一致；§9 明文写「arity / 实参类型在 build 下放行」；避免误报打断构建 | 否 |
| B：静态调用点的确信不匹配改为硬错 | `ct check` 覆盖不到 imported 映射单元；recipe 把实参直接拼进生成的 C 调用，ct 放行后没有第二道闸（`cc` 对 `strlen(42)` 只给 warning）；本轮用户要求「在 ct 阶段报错」 | **采纳** |

判决范围只限**静态映射调用点的实参类型**；普通函数 / trait 方法的 19.2 仍是 warning，`ct check`
照旧升 error。规范 §9 已补例外条款（中英各一处）。

**改动。**

- [Expr.h.ct:1109-1122](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1109-L1122)：新增
  `argtype_check_static`，复用 `argtype_mismatch`（同一套 `tnorm` 逐位比较），确信不匹配时
  `ct_sem_error` 并返回 `-1`。
- [Expr.h.ct:3058](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3058)、
  [:3100](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3100)、
  [:3167](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3167)：`qf == 3/4/5` 三个形态改用强校验。
- [Expr.h.ct:2560-2569](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2560-L2569)：`aux == 6`
  在「所有 arity 合适的候选都对不上实参」时由 `type_warn` 改为硬错。
- [check-ast.sh:1031-1096](../../selfhost/check-ast.sh#L1031-L1096)：四个负例从「退出 0 + warning」
  改为「非零退出 + `error: type mismatch: …`」；正例 `ok.ct` 仍零诊断。删掉强校验会让这四条立刻变红。

**验证（原始输出）。**

```
$ /tmp/cta-build/ct-ast build --emit-c -I test/modules/p25_static_argtype test/modules/p25_static_argtype/aux6.ct -o /tmp/p25t
test/modules/p25_static_argtype/aux6.ct:6:11: error: type mismatch: 'find' argument 1: expected 'char *', got 'int'
ctc: 1 error(s) generated
rc=1
```

`q3` / `q4` / `q5` 分别报 `'g' argument 1`、`'f' argument 1`、`'find' argument 1`，均 `rc=1`；
`ok.ct`（四种形态各传一次正确实参）`rc=0` 且无 `type mismatch`。完整断言在 `check-ast.sh`
的 `p25_static_argtype_*` 段，`bash selfhost/check-all.sh` 全绿。

## 证据

- **类型键按设计丢限定词**：[TypeCheck.h.ct:75-81](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L75-L81)
  的注释写明「`const` / `volatile` 被丢弃……`const char *` 和 `char *` 是同一个宿主」，
  并注明 [Emitter.h.ct:424](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L424) 的 `map_type_key`
  是同一张表的副本，两处必须同步改。
- **实参比较也丢限定词**：[Expr.h.ct:205-231](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L205-L231)
  的 `tnorm` 注释同样写明 `const char *` 与 `char *` 比较相等。
- **静态 trait 跳过实参类型检查**：[Expr.h.ct:1694-1699](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1694-L1699)
  的 `if (!self->sym->traits[t].is_static && …)` —— arity（P20-03）已覆盖，类型比对没有。
- **`impl` 方法有参数类型比对，但 `.m.ct` 的 `map` recipe 走不到**：
  [Parser.h.ct:2202-2226](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2202-L2226) 只处理带类型参数的
  `impl` 方法；recipe 参数是裸名字，只在 MapBuild 里与调用实参做位置对应。
- **全仓没有类型名解析检查**：`unknown type` 零命中。`.h.ct` 的未知类型最终由 C 编译器在头文件里发现，
  `.m.ct` 没有头文件，于是无人发现。

## 影响

**High**。两类都是「源码看起来合法、`ct compile` 退出 0、运行期才炸」：

- 字面量 / `const` 接收者被就地写属于未定义行为，在 macOS 上是 SIGBUS、在别的平台可能静默改坏
  `.rodata` 或段错误；std 的 `toUpper` / `toLower` / `copyFrom` 是应用层最常用的写方法，
  一个拼写顺序就能触发。
- `.m.ct` 参数类型不校验意味着 std 的签名只是文档：传错类型（数字当指针、结构体当整数）不会被拦，
  错误一律推迟到运行期；签名里写错类型名也不会被发现，读者会误以为该参数有约束。
- 现有门禁没有覆盖这两种组合：`check-ast` 的实参负例都走普通函数 / 已解析 trait 方法。

## 验证（现行判据，2026-11-10）

- 2a 在 `ct build` / `ct compile` 下报 `error: type mismatch: '<method>' argument N: …` 并退出 `1`；
  `ct check` 是单单元入口，不覆盖 imported 映射单元（§9 例外条款）；
- 正例：`"abc".len()`、`"abc".compare("x")`、`char buf[8]; buf.toUpper()` 零诊断；
  `test/modules/p25_static_argtype/ok.ct` 四种形态零诊断；
- `check-ast.sh` 的 `p25_static_argtype_{aux6,q3,q4,q5}` 断言非零退出 + `error:`；删掉强校验即变红；
  `bash selfhost/check-all.sh` 保持 11 道全绿。
