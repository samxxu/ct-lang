# PH-46–PH-52 定稿反证（反证席）

> **角色**：反证席。只攻击、只举证，不写实现、不改卡、不改规范。
> **范围**：[总计划](../design/phase46-52-plan.md) 与 [phase46.md](../history/design/phase46.md)…[phase52.md](../history/design/phase52.md) 七张卡。
> **基线**：HEAD `295d6ce`（`CTC_VERSION 0.44.1`）。工作树有另一条线未提交的 `0.44.2` 改动（82 个文件，`selfhost/` 只差版本串），
> 本轮的探针全部在 `/tmp` 用该源码构建的 `ct-ast` 跑；本文与该线不交叉，提交只含本文。
> **证据口径**：每条给 `file:line`、命令加输出、或 `/tmp` 探针路径。探针不入仓。
> **与主张席的关系**：[定稿主张](phase46-52-freeze-advocate.md) 已提出 F1/F2/F10/F12/F13/F15/F18 等结论。
> 本文不重抄这些结论，只做三件事：**推翻它判「可定稿」的三张卡**（46 / 50 / 51）、
> 用探针补强或修正它的四条判断（F1 的「≤50 行闭环」、F13 的「措辞对齐」、F15 的「静默返回」、F12 的「泄漏」），
> 以及补它没覆盖的阻断项（46 的多单元失败、48 的胶水外溢、51 的泛型零告警、52 的私有可见性与成员写入）。

---

## 0 结论总表

| 卡 | 阻断定稿 | 需修正 | 只做澄清 | 现在能否定稿 |
| --- | --- | --- | --- | --- |
| 整体（计划/交接） | 4（G-1…G-4） | 0 | 0 | **不能** |
| [PH-46](../history/design/phase46.md) | 2 + G-2 | 2 | 0 | **不能**（须改验收结构，见 §12） |
| [PH-47](../history/design/phase47.md) | 1 + G-2 | 3 | 0 | **不能**（须改 `put_owned` 结构，见 §12） |
| [PH-48](../history/design/phase48.md) | 2 | 1 | 0 | **不能**（须加声明通道，见 §12） |
| [PH-49](../history/design/phase49.md) | 0 | 3 | 0 | **不能**（三条卡面/判据修正后可签） |
| [PH-50](../history/design/phase50.md) | 2 + G-2 | 2 | 0 | **不能**（须改 `try_get` 所有权结构，见 §12） |
| [PH-51](../history/design/phase51.md) | 1 | 1 | 0 | **不能**（补泛型用例与判据即可） |
| [PH-52](../history/design/phase52.md) | 1 | 3 | 0 | **不能**（收缩 E12 + 补两档诊断即可） |

> 合计 28 条：**阻断定稿 13 条、需修正 15 条、只做澄清 0 条**（按卡列相加为 16 条阻断，因为 G-2 对 46/47/50 各计一次；
> 去重后为 13 条）。
> 最难定稿的是 **PH-48**：它同时要裁定「`impl Drop` 的跨单元可见性」与「胶水由哪个单元发」，
> 前者是一个 ABI/导出面决策（会反推 46 的实例归属），后者是现在会把外单元编译搞红的既有缺口；
> 两条都不是改措辞能过的。

---

## 1 整体与交接（4 条）

### G-1 卡片 §8.1 的复现命令按原文跑不出卡面结果

- **针对**：七卡（全部 §8.1）、总计划 §10.2。
- **问题陈述**：PH-46 §8.1 的探针写成 `import "lib.h.ct";` + 先跑单文件模式；这与仓库的导入语法和单文件模式都不相容。
  同时七卡 §8.1 与总计划 §10.2 都没写 `CT_STD_DIR`，按原文跑连泛型字段都解析不了。
- **证据**：
  - 按原文（`/tmp/p46/c1`）：
    ```text
    $ ct-ast build main.ct -o out
    main.ct:1:8: error: expected an import path            # build rc=1
    $ ct-ast main.ct -o main.c
    main.ct:1:1: error: 'import' requires multi-file mode: use 'ct build'   # single rc=1
    ```
    卡面表却写「单文件 rc=0 / build rc=1，`.ctbuild/Vec.h:31:20`」——文档里的错误一次也没出现。
  - 正确写法（`import lib;` + `CT_STD_DIR=<repo>/lib/std`，`/tmp/p46/c2`）才得到：
    ```text
    build rc=1
    .ctbuild/Vec.h:30:20: error: field has incomplete type 'struct JsonRef'
    ```
    行号也已从卡面的 `31:20` 漂到 `30:20`。
  - 不设 `CT_STD_DIR` 时，连 `struct H { Vec<int> *v; };` 都报 `expected a field name`（`/tmp/p46/t.ct`）；
    这正是 [language-capability-gaps.md](../proposals/language-capability-gaps.md) §5.3 已登记的陷阱，卡面没有吸收。
- **影响**：外部 harness 照 §8.1 复跑会认为基线与卡片记录不符，或把「环境问题」当成「卡面错误」，S0 结论不可信。
- **最小修正建议**：§10.2 加一行 `export CT_STD_DIR=<repo>/lib/std`；七卡 §8.1 改成 `import lib;` 的真实模块名，
  并把「单文件对照」改成自包含文件（不 import），不要用同一份 `main.ct` 两种模式跑。
- **严重度**：**阻断定稿**（交接面）。

### G-2 「产物逐字不变 / 125 条 / 82 条 golden」没有门禁面，数字也不存在

- **针对**：PH-46（O3 / E46-2）、PH-47（O5 / E47-3 / §8.2）、PH-50（E50-4 / §8.2）。
- **问题陈述**：判据要求 `Map` 生成物「逐字不变」，但仓库里没有任何一份比对 `ct-ast` 生成 C 的 golden 含 `Map`；
  卡里的 `82/82`、`125 条` 是无出处的数字。
- **证据**：
  - `selfhost/check-ast.sh:29-30`：`D34: exit status + build + output, not the generated text`；`:807-808`：`Golden .c / .h files are not compared`。
  - `selfhost/check-goldens.sh:10-13`：逐字节比对只覆盖 **L1** 对 `test/cases/*.ct` 的产物；`test/cases` 共 25 个 `.ct`，含 `Map` 的 **0** 个。
  - `find test -name '*.expected.c'` = 62；`grep -l 'Map_char\|MapEntry'` 命中 **0**。
  - `test/ast` 只有 `prog.ct` + `expected.out`（243 份），没有生成 C 的 golden。
- **影响**：这条判据写死会绿——实现可以任意改 `Map`/`MapEntry` 的生成文本而门禁仍然通过。
  主张席的「快照 `cmp`」是正确方向，但卡面本身还写着旧判据，定稿前必须替换，否则签字即失效。
- **最小修正建议**：删掉 `82/82`、`125 条`；改用「基线编译器产物快照 + 收口 `cmp`」，
  并在 `check-ast.sh` 里为四种对照形态各加一条 `cmp`（module 夹具已有 `expected.c` 比对先例，见 `check-ast.sh:910-931`）。
- **严重度**：**阻断定稿**（判据不可失败）。

### G-3 基线、版本与前置三处互斥；PH-45 未实施

- **针对**：总计划 §0/§1/§10.7、七卡第 5 行。
- **问题陈述**：卡面写「基线 `94556f29`（0.44.1）」，又写「起点为 PH-45 收口提交」，但 PH-45 仍是「待实施」；
  总计划 §10.7 的兜底「PH-45 未收口时取 PH-45 收口提交」在逻辑上不成立。`94556f29` 也已是 5 个提交之前的点。
- **证据**：`docs/design/phase45.md:3`「状态：规划中（已定稿，待项目组签字；未实施）」；
  `docs/roadmap.md:61`「Phase 45 … ⬜ 已定稿 / 待实施」；`git log --oneline -6`（HEAD `295d6ce`，`94556f29` 在尾部第 6 条）。
- **影响**：T-7 红证的父提交无法唯一确定；整波没有可开工的合法基线。
- **最小修正建议**：把「PH-45 收口」改成「PH-45 签字后开工」，或把 PH-45 移出本波前置并给出替代基线 sha；
  `baseline:` 由 S0 现场记录 HEAD，不再抄规划提交。
- **严重度**：**阻断定稿**（排期前置）。

### G-4 46 与 48 改的是同一套「定义归属」策略，不能分两相独立冻结

- **针对**：总计划 §3「46 与 48 正交」、§8「46 最小且无分歧」。
- **问题陈述**：两相都要回答「一个非头文件单元拥有的定义，如何让别的单元看见」。
  46 的答案是「实例移到命名单元、方法变 `static`」（`Emitter.h.ct:1618-1629`），
  48 的答案是「定义单元非 `static` + 消费单元 `extern`」（D48-2）。两种策略落在同一个发射器、同一类符号上。
- **证据**：`Emitter.h.ct:1609-1629`（实例归属）、`:2613-2617`（Drop 原型 `static`）、`:3102-3115`（胶水按全表 struct 发射）。
  46 先按「每单元一份静态定义」收口后，48 再把符号改成外部链接，46 的跨单元边界还要重判一次。
- **影响**：46 先做会产生一次几乎必然的返工；「正交、可并行」的判断不成立。
- **最小修正建议**：先做 48 的 S0（链接性/可见性政策）并冻结，再按同一政策实现 46 的实例归属；
  顺序改为 **48-S0 →（46 与 48 实现）→ 49**。
- **严重度**：**阻断定稿**（排序结论）。

---

## 2 PH-46（本节 2 条 + G-2，共 3 条阻断）

### R46-1 修法不是「把 `MapEntry` 加进白名单」，还要改第二实参判定

- **针对**：PH-46 D46-2 / S2；同时推翻主张席 F1 的「只需把 `MapEntry` 纳入、≤50 行闭环」。
- **问题陈述**：`inst_elem_foreign` 只在模板为 `Map` 时取第二实参（`e2`）；`MapEntry` 的 `V` 永远不会被检查，
  所以只把 `MapEntry` 加进模板白名单，仍然返回 0，定义继续留在共享头。
- **证据**：`Emitter.h.ct:2003-2004`
  ```c
  e2 = (strcmp(ins[ii].tmpl, "Map") == 0 && ins[ii].nargs > 1)
       ? ins[ii].ctype[1] : 0;
  ```
  在 `/tmp/ct46` 的仓库副本上只加白名单（不动 `e2`）重建后，J-1 探针仍报 `.ctbuild/Vec.h:30:20: field has incomplete type 'struct JsonRef'`；
  再把 `e2` 的模板条件扩到 `MapEntry` 后才通过（`rc=0`，`ok len=1`）。
- **影响**：按卡面「下沉到实例化单元」直接实现会第一次失败，S0/S2 会多一轮定位；工量判断失真。
- **最小修正建议**：D46-2 明确写「两处判定：`inst_elem_foreign` 白名单 + `e2` 的模板条件」，
  并把 `Emitter.h.ct:1981-2017` 整段列进 S0 锚点表（现在只列了 `:1597-1618`）。
- **严重度**：需修正（但会直接影响 S2 可落地性）。

### R46-2 修好后，包方的多单元形态仍然编译失败——O1／O4 的承诺只对单单元成立

- **针对**：PH-46 O1（可 `put/get/foreach/release`）、O4（`--lib` 不回归）、E46-1。
- **问题陈述**：基线里 `Map<char *, JsonRef>` 的**实例结构**已经落在命名单元（`/tmp/p46/c3`：`Map_char_p_JsonRef` 定义在 `main.c:19`），
  只有 `MapEntry` 还留在共享头（`Vec.h:28`）。把 `MapEntry` 也外移后，两个实例都只在「命名它的那一个单元」定义；
  其它单元只看到前向声明，`get/len/entry` 全都没有声明。
  卡面的夹具把所有操作放在一个文件里，因此会绿，而包方「`.h.ct` 声明字段、`.m.ct`/消费单元使用」的形态仍失败。
- **证据**（`/tmp/p46/b6`，用 R46-1 修补后的 `ct-ast`）：
  ```text
  main.ct:19:31: error: variable has incomplete type 'struct Map_char_p_JsonRef'
  main.ct:22:32: error: call to undeclared function 'Map_char_p_JsonRef_len'
  main.ct:24:51: error: call to undeclared function 'Map_char_p_JsonRef_entry'
  ... 7 errors generated.
  ```
  对照：同一形态换成「指针元素」`Map<char *, JsonRef *>` 时 `rc=0`（`/tmp/p46/b8`），说明这是**按值元素 + 多单元**的组合缺口，不是 JSON 类型本身。
  更关键的是：**基线**下 `Vec<Elem>` 在同一形态（`.h.ct` 命名、消费单元调用）也失败——
  `main.ct:18:24: error: call to undeclared function 'Vec_Elem_len'`（`/tmp/p46/b7`），
  所以卡面 §0 的「`Vec` 的实例已经能留到单元内解决」只在单单元成立。
- **影响**：E46-1 的夹具绿了也不证明 J-1 对包方可解；`ct-json` 的 `JsonValue` 若在 `.h.ct` 暴露 `Map` 字段，
  消费单元第一次 `get` 就断。这是「做完 46 包方仍写不出」的直接证据。
  包方确实可以「只让定义单元碰 `Map`，对外只暴露函数」绕过，但卡面没有写这个限制，
  而它恰好否定了「`Map` 可以作为 `pub struct` 的公开字段」的设计意图——这一点必须由卡面明说，不能留给实现者自己发现。
- **最小修正建议**：E46-1 增加一条多单元夹具（`.h.ct` 声明含 `Map<char*, US>` 指针字段 + 另一个单元 `get/foreach`），
  并明确 `MapEntry` 的「单一定义点」在多单元下如何满足；若本期不做，就把 O1 收缩为「单单元 build」并写明包方限制。
- **严重度**：**阻断定稿**。

### R46-3 D46-2 的备选「共享头补 `#include`」存在 include 环；且 E46-2 的对照面为空

- **针对**：PH-46 D46-2 备选、E46-2、O3。
- **问题陈述**：备选方案在真实目录结构下不可行：`lib.h` 先 include `Vec.h`，若 `Vec.h` 再 include `lib.h`，
  第二次进入时 `LIB_H` 已定义，`JsonRef` 仍未声明，`MapEntry` 依旧不完整。O3/E46-2 的「四种形态逐字不变」也没有比对面（见 G-2）。
- **证据**（`/tmp/p46/.ctbuild`，生成物）：
  ```text
  .ctbuild/lib.h:8:  #include "Vec.h"
  .ctbuild/Vec.h:18: struct JsonRef;          # 只有前向声明
  ```
  头文件 guard 是单向的：从 `main.c` 进入时，`Vec.h` 里 include `lib.h` 会被 `LIB_H` 挡掉。
- **影响**：S0 一旦判定「下沉与 `--lib` 冲突」改走备选，会撞死路，浪费一轮；而 O3 的判据无论如何都绿。
- **最小修正建议**：删掉备选，或把备选改成「在实例化单元里同时生成 `MapEntry` 的私有定义 + 前向声明」；
  O3/E46-2 按 G-2 的快照 `cmp` 重写（module 夹具已有 `expected.c` 先例，`check-ast.sh:910-931`）。
- **严重度**：**阻断定稿**。

### R46-4 §8.1 的三步之外，夹具落盘位置也错；E46-3 / E46-4 不可判定

- **针对**：PH-46 S1、E46-3、E46-4。
- **问题陈述**：`test/ast/*` 的门禁只跑单文件 `prog.ct`（`check-ast.sh:502`），build 模式夹具必须放
  `test/modules/<name>/main.ct` 并手写进 `check-ast.sh`。S1 却写 `test/ast/p46_map_struct/`（build 模式）。
  E46-3 的「`nm -g` 面与第 39 相口径一致」没有给出符号集；E46-4 的 `grep -c 'struct MapEntry_'` 没写目标文件，
  一个工程里每个 `.c` 各有一份前向声明，`=1` 不成立。
- **证据**：`check-ast.sh:502`（`for d in test/ast/*/`）、`:910-931`（module 走 `build --emit-c test/modules/...`）；
  `/tmp/p46/b6` 的 `.ctbuild` 里 `main.c`、`doc.c` 各有一份 `struct MapEntry_...;` 前向声明。
- **影响**：S1 的红证无法被 `check-ast.sh` 发现；E46-3/4 的断言在不同目标文件上会给出相反结果。
- **最小修正建议**：夹具改到 `test/modules/p46_map_struct/`；E46-3 点名 `phase39-draft.md` 的归一化符号集与 diff 命令；
  E46-4 拆成「共享头 0 处定义 + 恰好 1 个 `.c` 有定义」。
- **严重度**：需修正。

---

## 3 PH-47（本节 1 条 + G-2，共 2 条阻断）

### R47-1 `put_owned` 没有「每条目键所有权」的存放载体，S3 无法落地

- **针对**：PH-47 D47-4 / S3、O2 / O3。
- **问题陈述**：`MapEntry` 只有 `key` / `value` 两个字段，`ct_buf` 只有 `refs/len/cap/data`；
  `release` 只遍历值（`Vec.h.ct:517-537`）。要在释放时区分「借来的键」与「复制的键」，
  必须有每条目一位；加字段又直接违反 PH-46 的「不改 `MapEntry` 布局 / 不破坏 `from` 字面量」。
- **证据**：`lib/std/Vec.h.ct:47-50`（`MapEntry`）、`:30-35`（`ct_buf`）、`:517-537`（`release` 只 `__ct_elem_release(&es[i].value)`）。
- **影响**：S3「只加入口，不改 `put`」不可能实现；若改布局，PH-46 的 D46-1 与既有 `from` 夹具同时被打破。
- **最小修正建议**：采用主张席 D47-3′（`Str` 键一律深拷贝、删除 `put_owned`），或在卡里另立「`Map` 私有元数据」设计并重估工量。
- **严重度**：**阻断定稿**。

### R47-2 `Str` 键的「借用默认」没有判据；E47-1 只是靠临时量泄漏才成立

- **针对**：PH-47 D47-3 / O2 / E47-1（主张席 F6 提到风险，本文给出「判据不可判定」的实证）。
- **问题陈述**：E47-1 用内联 `str_from_len(...)` 作键。临时 `Str` 不会被 drop（生成 C 里没有 `Str_Drop_drop`/`release`），
  所以键的 buffer 一直有效——测试通过依赖「临时量泄漏」，而不是「借用契约正确」。
  同时，实现若改成深拷贝，E47-1 同样通过，因此 O2 的「默认借用」无法由该夹具判定。
- **证据**（`/tmp/p51/strtmp.ct`）：
  ```text
  int take(Str s) { return s.len; }
  int main(void) { int n = take(str_from("ab")); ... }
  ```
  生成 C 中 `str_from` 之后没有 `Str_Drop_drop`/`release`（`grep` 无命中），临时 buffer 泄漏。
- **影响**：O2 的语义与实现是否一致不可判；将来若给临时量加自动释放，E47-1 会突然变成悬垂键。
- **最小修正建议**：E47-1 改用**命名** `Str`（并保持变量活到 `release()` 之后）作为借用用例；
  再加一条「源 `Str` 提前 `release()` 后键失效」的负向断言，才能锁住「借用」而不是「泄漏」。
- **严重度**：需修正。

### R47-3 E47-2 的 leak 判据与 §8.2 自相矛盾

- **针对**：PH-47 E47-2 / §8.2。
- **问题陈述**：E47-2 写「`release` 后 ASAN 无 leak / double-free」；同一张卡 §8.2 写 `detect_leaks=0`、
  「不允许以 sanitizer 通过代替泄漏判据」。两条不能同时成立。
- **证据**：`selfhost/check-all.sh:94-104`（11 道硬门禁不含 sanitizer）；`phase47.md:152`
  原文「`bash selfhost/check-sanitizers.sh` rc=0（`detect_leaks=0`，**不宣称泄漏检测**）」。
- **影响**：收口时无法判定 E47-2 是否通过；按主张席的「释放计数器」改法需要显式写入卡面。
- **最小修正建议**：E47-2 删 `leak`，只留 UAF/double-free；泄漏改用「分配/释放计数相等」夹具。
- **严重度**：需修正（与 48/49 同源，建议一次统一）。

### R47-4 「`Map<Str,V>` 特化」是第三份实现，任务与工量都漏了

- **针对**：PH-47 S2 / §7、PH-50 S3。
- **问题陈述**：`Map` 的方法在通用块与 `Map<char*,V>` 块各有一份，按名字遮蔽（`Vec.h.ct:210-215`）。
  新增 `Str` 键必须写**第三份** `put/get/remove/from`（以及后续的 `has/try_get`），
  而 S2 只写「`Str` 键特化 + 白名单放行」，S3 又只写 `put_owned`。
- **证据**：`lib/std/Vec.h.ct:216-409`（`impl<V> Map<char*,V>` 的 put/get/remove/from），`:346-409`（通用 `Map<K,V>` 同名方法）。
- **影响**：100–180 行的 `lib/std` 估算偏低；每漏一个方法，`Map<Str,V>` 就会回落到 `memcmp`（比较 16 字节 + 4 字节 padding，见 `Vec.h.ct:371`）。
- **最小修正建议**：把「三份实现清单」写进 S2/S3 的验收：`put/get/remove/from/clear/has/try_get` 逐项点名。
- **严重度**：需修正。

---

## 4 PH-48（2 条阻断）

### R48-1 消费单元拿不到「impl 存在」的信号，O2 与 O3 互斥

- **针对**：PH-48 O2 / O3 / D48-2 / D48-3 / E48-5。
- **问题陈述**：O2 要求消费单元发 `extern` 并调用真实体；O3 要求「看不到 impl 就硬错」。
  但 `impl Drop` 跨单元时，消费单元的符号表最多知道「这个类型 `use Drop`」（由 `.h.ct` 源导入），
  却拿不到「别处有 impl」的信号：导出的 `.h` 文本里既没有 `use Drop`，也没有 `<S>_Drop_drop` 原型。
  于是它只能二选一——发空桩（O2 失效）或硬错（O3 误杀所有跨单元 `delete`）。
- **证据**（`/tmp/p46/d4`，`cfg.h.ct` + `main.ct`）：
  ```text
  build rc=0；./out 只打印 done（真实体 res drop 7 不出现）
  .ctbuild/cfg.h  → 只有 struct Res { int id; };（无 use Drop、无原型）
  .ctbuild/cfg.c  → static void Res_Drop_drop(void *self) { ... }   # 真体
  .ctbuild/main.c → static ... Res_Drop_drop(void *self) { (void)self; }  # 空桩
  ```
  代码侧：`Emitter.h.ct:2613-2617` 给所有 `uses_drop` struct 发 `static` 原型；
  `:3107-3112` 用本单元的 `has_drop_impl` 决定是否发空桩——该标志不跨单元传播。
- **影响**：D48-2 的「单独一档链接性」缺少声明通道；按卡实现后，跨单元 `delete` 要么继续静默，要么全部硬错，J-3 仍未解。
- **最小修正建议**：先裁定「`impl Drop` 的可见性」——建议沿用 P34 S5b 的既有通道
  （`emit_inherent_protos`，`Emitter.h.ct:3543-3565` 已给 `pub` struct 的固有方法发原型），
  为 Drop 发一条非 `static` 原型，并把「有无 impl」写进导出头；再据此决定空桩/`extern`/硬错。
- **严重度**：**阻断定稿**。

### R48-2 自动胶水被发进外单元，跨单元直接编译失败（卡面改动面漏了 unit 过滤）

- **针对**：PH-48 O4 / S2（只列了 `:3132` 与 `:5800-5801` 两处）。
- **问题陈述**：自动胶水的发射循环遍历**全部** `structs`，不按 `owner` 过滤。
  当 A 单元定义的 `Holder` 含指针字段、且它被 B 单元导入时，B 也会尝试生成 `Holder_Drop_drop` 的胶水，
  但 B 看不到 `Holder` 的完整定义。
- **证据**（`/tmp/p46/d5`：`cfg.h.ct` 定义 `Res`，`main.ct` 定义 `struct Holder { Res *r; } use Drop;`）：
  ```text
  build rc=1
  ./cfg.h.ct:22:25: error: incomplete definition of type 'struct Holder'
  note: Str.h:17:8: note: forward declaration of 'struct Holder'
  ```
  `main.c` 能单独编译；失败发生在 **`cfg.c`**——它在为 `main.ct` 的 `Holder` 发胶水。
  代码侧：`Emitter.h.ct:3102-3115` 的 `for (si = 0; si < self->sym->nstructs; si++)` 没有 owner 判断。
- **影响**：PH-48 的「两处胶水点」不止两处语义问题，还漏了「谁有权发胶水」；
  包方一旦在 `.h.ct` 里定义含指针字段的类型，另一个单元就会整体编译失败。工量与风险都低估。
- **最小修正建议**：S2/S3 增加「胶水只由 struct 的 owner 单元发」；夹具加一条跨单元指针字段用例。
- **严重度**：**阻断定稿**。

### R48-3 E48-3 的 leak 与「必跑但不进门禁」使判据无人执行

- **针对**：PH-48 E48-3 / R48-5 / §8.2。
- **问题陈述**：E48-3 写「无 use-after-free / double-free / leak」，但 §8.2 写 `detect_leaks=0` 且
  「用 sanitizer 代替泄漏判据」被禁止；R48-5 又承认 ASAN 脚本「本相必跑，但不计入 11 道硬门禁」。
  「必跑」没有执行者。
- **证据**：`selfhost/check-all.sh:94-104`（11 道门禁清单）；`phase48.md:117`（R48-5 原文）。
- **影响**：泄漏与「空桩是否被调用」都只能靠人工；O2 的跨单元修复没有自动回归。
- **最小修正建议**：E48-3 删 `leak`；把「跨单元夹具的输出顺序」与「胶水文本」放进 `check-ast.sh` 的自动断言，
  ASAN 脚本只作为补充证据，不作为唯一判据。
- **严重度**：需修正。

---

## 5 PH-49（0 条阻断，3 条需修正）

### R49-1 `own` 仍要求 `use Drop`，卡面没写；与包方「别用 Drop」的建议冲突

- **针对**：PH-49 O1 / D49-1 / E49-1。
- **问题陈述**：`own` 的既有规则是「pointee 必须是 `use Drop` 的 struct」（`Memory.h.ct:104-106`），
  D49-1 只放行「返回 `struct X *` 的函数调用」，没有解除这条。于是
  `own JsonDoc *doc = json_decode(text);` 仍要求 `JsonDoc use Drop`；而评审二对包方的建议是「先别依赖 Drop，用 `json_free`」。
  两张卡之间没有一句话对齐。
- **证据**：`selfhost/ct-ast/backend/mem/Memory.h.ct:100-106`；
  `own int *p = malloc(...)` 实测报 `struct 'int' does not use trait 'Drop'`（`/tmp/p51/o5.ct`）。
- **影响**：包方按评审二的建议写（不用 Drop），本卡的 O1 仍不可用；J-4 的「构造即托管」没有真正闭环。
- **最小修正建议**：O1 明确写前置「pointee 必须 `use Drop`」，并说明与评审二的建议如何取舍；
  或在 D49-1 里裁定「工厂返回值不要求 Drop，AutoDrop 只 `free`」，但这需要新的所有权语义，报价要改。
- **严重度**：需修正。

### R49-2 E49-1 的 leak 判据不可执行；「块尾执行 Drop」依赖 48 的真实体

- **针对**：PH-49 E49-1 / E49-6 / §8.2。
- **问题陈述**：E49-1 写「ASAN 无泄漏」，§8.2 又写 `detect_leaks=0`（同 R47-3）。
  另外 E49-1 的「块尾执行 Drop」在 build 模式下依赖 PH-48 的跨单元真实体；48 未解时该断言只能单单元跑。
- **证据**：`phase49.md:137`（`detect_leaks=0`）；`/tmp/p46/d4`（跨单元真实体不执行）。
- **影响**：E49-1 只能证明「单单元 own 语法通过」，不能证明跨单元释放。
- **最小修正建议**：删 `leak`；把「Drop 计数 = 分配计数」写成夹具；跨单元用例显式标注「以 48 收口为前置」。
- **严重度**：需修正。

### R49-3 D49-1 没定义「函数调用」的解析方式，`Memory` 单元没有表达式类型器

- **针对**：PH-49 D49-1 / S2。
- **问题陈述**：`own` 的校验在 `Memory` 单元，只有 `arena` / `sym` / `path`，没有 `static_ctype`；
  「返回 `struct X *` 的函数调用」只能靠 `find_func` 查符号。卡里没写：只认自由函数还是也认方法、按源名还是 `cname`、泛型实例是否接受。
- **证据**：`selfhost/ct-ast/backend/mem/Memory.h.ct:45-58`（结构体字段）、`:84-131`（`mark_owned` / `expr_alloc`）。
- **影响**：S2 会先花时间补一套类型查询；若实现按 `cname` 查而用户写源名，工厂形态会被误拒。
- **最小修正建议**：D49-1 补四句（调用形态 / 名字解析 / 返回类型匹配 / 拒绝面），并写进 S0 锚点。
- **严重度**：需修正。

---

## 6 PH-50（本节 2 条 + G-2，共 3 条阻断）

### R50-1 O3 的契约句对 `Vec<Str>` 是错的，照写会导致二次释放

- **针对**：PH-50 O3 / §5 文档交付 / D50-4（主张席 F13 只判「措辞需对齐」，本文判「阻断」并给出 `Vec<Str>` 的实测）。
- **问题陈述**：O3 写「容器 `release` 不跑元素 Drop，元素释放归调用方显式遍历」。
  这句话只对「仅 `use Drop`、没有 `release()` 方法」的元素成立；对 `Vec<Str>`，容器 `release` 会调用 `Str_release`，
  调用方再遍历释放就是双释放。卡面 §0 缺口③ 也只测试了 `Vec<L>`（`L use Drop`）。
- **证据**（`/tmp/p51/vecrel.ct`）：生成的 `Vec_Str__elem_release` 调用 `Str_release`；
  `Vec<Zed>`（Zed 仅 `use Drop`）则是 `(void)e;`（`/tmp/p51/v4.c`）。
  规范侧：`docs/language-spec.md:2326` 原文「`Vec<Str>` / `Vec<Probe>` 的 `release()` 会调用元素的 `release()`」。
- **影响**：按 O3 写进 `package-guide.md` 会教用户对 `Vec<Str>` 二次释放；这与本相「让失败可判」的目标相反。
- **最小修正建议**：契约句改成「元素协议只认 `retain` / `release` 固有方法；`impl Drop` 不参与；
  无 `release` 的元素需调用方显式释放」，并在夹具里同时覆盖 `Vec<Str>` 与 `Vec<L use Drop>`。
- **严重度**：**阻断定稿**（文档交付物写错）。

### R50-2 `try_get(..., V *out)` 新开一类双释放，且借用守卫覆盖不到出参

- **针对**：PH-50 O1 / D50-2 / E50-1（主张席 F12 判「会泄漏」，本文实测是**双释放**）。
- **问题陈述**：`Vec::get` 返回值会被标记为 borrowed view（释放会被 L31-14 拒绝）；
  但 `try_get` 通过 `*out = 元素` 复制，既没有 retain，也不会给调用方的变量打 borrowed 标记。
  调用方对 `out` 调用 `release()` 就会与容器二次释放。
- **证据**（`/tmp/p51/outparam.ct`，用现有 `get` 模拟同样的出参形态）：
  ```text
  ct rc=0；ASAN:
  ERROR: AddressSanitizer: attempting double-free ... in Str_release
  #2 Vec_Str__elem_release   #3 Vec_Str_release
  ```
  borrowed 标记原位：`Expr.h.ct:450-458`（只看局部变量的初始化式），`:4292`（释放借用视图时报错）。
- **影响**：PH-50 会在「越界可判」的收益之外引入新的内存安全缺口，且现有门禁不会发现（没有 `Vec<Str>` + 出参的 ASAN 用例）。
- **最小修正建议**：把 `try_get` 定义为「拷贝且不转移所有权」并在契约里禁止对 `out` 调用 `release()`；
  或者对含 `retain/release` 的元素在写入前 `retain`、旧值 `release`（需要明确覆盖写语义），并为 `Vec<Str>` 加一条 ASAN 负例。
- **严重度**：**阻断定稿**。

### R50-3 `Map<char*,V>` 的特化块必须同步加 `has` / `try_get`，卡里漏了这条工作项

- **针对**：PH-50 S3 / D50-5 / E50-2。
- **问题陈述**：`Map<char*,V>` 与通用 `Map<K,V>` 是两份实现，按名字遮蔽。若只在通用块加 `has` / `try_get`，
  `Map<char*,int>::has("k")` 会落到通用块的 `memcmp(&key, &k, sizeof(k))`——比较的是指针值，永远不命中。
- **证据**：`lib/std/Vec.h.ct:210-215`（遮蔽规则）、`:216-409`（char* 特化块）、`:371`（通用 `memcmp`）。
- **影响**：E50-2 会红，但卡面没有对应任务，S3 会临时扩面；`Map<Str,V>` 还要再写第三份（同 R47-4）。
- **最小修正建议**：S3 明写「通用 / `char *` / `Str` 三份都要加」，并把 E50-2 的用例扩到三种键。
- **严重度**：需修正。

### R50-4 E50-3「随机 32 例」不可复现

- **针对**：PH-50 E50-3。
- **问题陈述**：没有种子、没有生成器，门禁结果不可重复；这与主张席的「固定 32 行表」建议一致，但卡面还没改。
- **证据**：`phase50.md:104` 原文「随机 32 例」。
- **影响**：收口判定不稳定（今天绿、明天红）。
- **最小修正建议**：改成固定 32 行表 + `cmp` 期望文件。
- **严重度**：需修正。

---

## 7 PH-51（1 条阻断）

### R51-1 泛型实例的同一缺陷零告警，E51-3 看不见；「影响面分叉」是伪分叉

- **针对**：PH-51 O3 / E51-3 / D51-4 / E51-4。
- **问题陈述**：两层事实被混在一起：
  1. `check-warnings.sh` 已经对全部生成 C 用 `-Wall -Wextra -c` 并要求 stderr 为空，非泛型指针接收者的
     `.` 调用会触发 `-Wincompatible-pointer-types`，门禁直接红。所以「现有门禁只跑默认告警、缺陷长期不可见」不成立；
     S0 的计数只要门禁是绿的，就必然是 0（除非基线已红）。「零依赖 → 硬错 / 有依赖 → 自动解引用」不是真分叉。
  2. 泛型实例的方法 `self` 是 `void *`（`Emitter.h.ct:1778`），`S_f(&p)` 把 `S**` 传给 `void *` **完全合法、零告警**，
     运行时静默错值/崩溃。E51-3 的 `-Werror=incompatible-pointer-types` 对这一半缺陷永远为绿。
- **证据**：
  - `selfhost/check-warnings.sh:5-8`（「check-ast 的告警被忽略，本门禁是缺失的那一半」「fails if stderr is not empty」）、`:86`（`-Wall -Wextra -std=c99 -c`）。
  - 非泛型（`/tmp/p51/pr.ct`）：生成 `S_get_id(&p)`，`cc -Wall -Wextra` 报 `incompatible-pointer-types`。
  - 泛型（`/tmp/p51/gen.ct`）：
    ```text
    Vec<int> *v; v->h = 0; v.push(7);
    生成: Vec_int_push(&v, 7)      # 形参 void *self
    cc -Wall -Wextra rc=0（无告警）
    运行 rc=134（abort）
    ```
- **影响**：按 E51-3 收口会漏掉「泛型实例的 `.` 调用」——而这正是 `Vec`/`Map`/`Option` 链式最常见的形态；
  「任何链式方案都会踩」的判据只覆盖一半。
- **最小修正建议**：E51-1 增加泛型实例用例（`Vec<int> *v; v.push(1)`）；
  E51-3 之外增加「生成文本断言 `Vec_int_push(v, ...)`」或运行值断言；D51-4 删掉「现有门禁只跑默认告警」的错误前提
  （计划 `phase46-52-plan.md:46` 的「`cc` 只给 warning」也要改成「非泛型警告、泛型静默」），
  §0 摘要里的「待用户裁定」改成「按 S0 源码计数触发」。
- **严重度**：**阻断定稿**。

### R51-2 选型 A 下 E51-3 与 E51-1 互斥

- **针对**：PH-51 E51-1 / E51-3 / S3。
- **问题陈述**：选型 A 的期望是 `rc=1` 且不写 `.c`；E51-3 却要求「生成 C 在 `-Werror` 下编译」——没有产物可编译。
  两条判据不能同时要求。
- **证据**：`phase51.md:102`（E51-1「不写 `.c`」）、`:104`（E51-3「生成 C」）。
- **影响**：收口时必然有一条无法执行，容易被标 skip 或临时删。
- **最小修正建议**：E51-3 只在选型 B 生效；选型 A 用「rc=1 + 文案 + 不落 `.c`」。
- **严重度**：需修正。

---

## 8 PH-52（1 条阻断）

### R52-1 RL1-E12 与方案 A 自相矛盾：`v[0]` 不可能硬错

- **针对**：PH-52 RL1-E12 / D52-2 / §8.2「JSON 单层」（主张席 F15 已提出；本文补「`0` 是空指针常量所以 `cc` 也不会报」并把 E12 判为阻断）。
- **问题陈述**：方案 A 只按「方法名 + 参数个数 + 非 static」匹配，不看实参类型。
  只要 `JsonValue` 有 `get(char *)`，`v[0]` 就会命中并展开为 `v.get(0)`；`0` 是空指针常量，`cc` 不报错，
  `Map::get` 的 `k == 0` 分支返回 0——结果是**静默返回空**，不是「硬错并提示 `get_idx`」。
  E12 要求的诊断在九条 `RL1-L*` 里没有对应项，全仓 `grep get_idx` 也无命中（这条提示没有既有落点，需新增）。
- **证据**：`custom-index-protocol.md` 的 RL1-D3（名 + 参数个数）；`lib/std/Vec.h.ct:260-269`（`k == 0` 返回 0）；
  `grep -rn "get_idx" selfhost/` 无命中。
- **影响**：E12 无法通过；若为了过它临时加类型特判，就等于偷偷引入方案 B，违反 D52-2。
- **最小修正建议**：删掉 `v[0]` 的「硬错」主张；E12 收缩为「`v["k"]` 单层可用；`v[0]` 本期不主张，
  数字索引用显式 `get_idx(i)` 调用」（与主张席一致）。
- **严重度**：**阻断定稿**。

### R52-2 R52-4 引用了不存在的 `ct_impl_inst`

- **针对**：PH-52 R52-4。
- **问题陈述**：仓库只有 `ct_inst_find`；`ct_impl_inst` 不存在，草案 RL1-D6 写的也是 `ct_inst_find`。
- **证据**：`selfhost/ct-ast/frontend/sym/Symbols.h.ct:433`（声明）、`:1753`（定义）；全仓 `grep ct_impl_inst` 无命中。
- **影响**：S4 的「泛型类型名还原」会按错误函数名去改，返工一轮。
- **最小修正建议**：改成 `ct_inst_find`，并给出「实例名 → 源拼写」的还原路径。
- **严重度**：需修正。

### R52-3 缺「`get` 不可见」这一档诊断

- **针对**：PH-52 RL1-L1–L9 / O3。
- **问题陈述**：Phase 42 之后方法默认私有（`Emitter.h.ct:1733` 对非 `pub` 方法 `exported = 0`）。
  若 `X` 声明在 `.h.ct`、`get` 未标 `pub`，消费单元的 `x[k]` 仍会先命中订阅、随后链接/`cc` 失败——
  正是本相要消灭的「`ct` rc=0、`cc` 才报错」形态。九条诊断没有一条覆盖可见性。
- **证据**：`Emitter.h.ct:1720-1733`（`exported` 只看 `d != 1`）；`phase42` 的方法级 `pub` 规则（既有卡）。
  本项是代码事实，但**端到端复现需在实现后**，标为未确认。
- **影响**：跨单元 JSON 访问会出现「编译过、链接炸」，与 RL1-O3 的承诺不符。
- **最小修正建议**：增加 `RL1-L10`（或并入 L1）：`get`/`set` 必须对本单元可见（`pub` 或同单元），否则硬错。
- **严重度**：需修正（未确认端到端）。

### R52-4 `x[k].field = v` / `x[k].m()` 未覆盖，仍会落到 `cc`

- **针对**：PH-52 D52-4 / RL1-L8。
- **问题陈述**：L8 只覆盖「写形态非语句 / 接收者非左值」。`x[k].name = "a"` 是语句、接收者 `x` 也是左值，
  但左侧节点是 `N_MEMBER`，不是下标调用；现有 Vec 的守卫会沿 `N_MEMBER`/`N_ARROW` 回溯并归咎下标
  （`Expr.h.ct:3913-3956`），自定义 kind 3 若只处理直接 `x[k] = v`，这些形态仍原样发射 C。
  JSON 的实际写法就是 `doc["a"].name`。
- **证据**：`Expr.h.ct:3919-3935`（`container_subscript_kind` 沿成员链回溯）、`:3956-3983`（写/取址判定）。
- **影响**：RL1-O2 声称的「写形态只收语句 + 左值」在实际成员写入上不生效，仍由 `cc` 兜底。
- **最小修正建议**：明确 `x[k].f = v` / `x[k].f()` 的处理：要么归入 L8 硬错，要么把 `get` 的返回类型参与成员写入；
  并加一条夹具。
- **严重度**：需修正。

---

## 9 七张卡做完，包方还能不能写 ct-json

按 [评审二](../review/ct-json-proposal-review.md) 的推荐设计逐条核对：

| 阻塞 | 卡 | 做完后的真实状态 | 证据 |
| --- | --- | --- | --- |
| J-1 `Map<char*, JsonRef>` 按值 | 46 | **部分**：单单元可编译；`.h.ct` 声明 + 消费单元取用仍失败 | `/tmp/p46/b6`（7 错）、`/tmp/p46/b7`（`Vec` 基线同样失败） |
| J-2 `Str` 键 / 键保真 | 47 | **可解**（按 D47-3′ 深拷贝）；现行 D47-3 的借用默认无法判定 | `/tmp/p51/strtmp.ct`、`Vec.h.ct:371` |
| J-3 跨单元 Drop | 48 | **未解**：消费单元拿不到 impl 信号；O2/O3 互斥；胶水还会发进外单元 | `/tmp/p46/d4`、`/tmp/p46/d5` |
| J-4 `own` 接工厂 | 49 | **有条件**：仍要求 `JsonDoc use Drop`，与包方建议冲突；跨单元依赖 48 | `Memory.h.ct:100-106` |
| J-6 同名函数 | — | 不在本波，包方改名 | 计划 §6 |

结论：**七卡全做完，包方仍写不出「原生容器 + 值语义 + 自动释放」的推荐形态**；
能写的只有「单单元 + 指针元素 + 显式释放」的绕法。这不是「卡没写全」，而是 J-1 的多单元与 J-3 的可见性两条被当成「已解」。

---

## 10 未确认项（不当作定论）

1. PH-52 的 `get` 私有可见性（R52-3）：代码事实成立，但端到端报错要等实现后才能复跑。
2. PH-47 的 `Str` 键借用：在 `Map<Str,V>` 落地前无法用真实代码复现；本文只证「判据不可判定」。
3. PH-46 的「多单元失败」是否会被实现方用「所有 Map 访问集中在定义单元」规避：卡面没有这个限制，故按通用形态判定。

---

## 11 最小放行条件（按卡）

| 卡 | 放行前必须完成 |
| --- | --- |
| 46 | ① 修法写全（白名单 + `e2`）；② 增加多单元夹具并决定 O1 是否收缩；③ 备选方案删除或改设计；④ 判据按 G-2 重写 |
| 47 | ① `put_owned` 改 D47-3′ 或补所有权载体；② E47-1 改命名 `Str` + 失效负例；③ 去 leak；④ 三份实现清单 |
| 48 | ① 裁定 Drop 的可见性/声明通道；② 胶水按 owner 过滤；③ 去 leak + 跨单元输出进自动断言 |
| 49 | ① 写清 `use Drop` 前置；② 去 leak；③ D49-1 补解析规则 |
| 50 | ① 重写 O3 契约句；② `try_get` 出参所有权规则 + ASAN 负例；③ 三份实现清单；④ 固定 32 例 |
| 51 | ① 泛型实例用例与判据；② 删「门禁只跑默认告警」前提；③ E51-3 只在 B 生效 |
| 52 | ① E12 收缩；② `ct_impl_inst` 改 `ct_inst_find`；③ 可见性诊断；④ `x[k].f` 边界 |

> 本文件只做反证，不代改卡片。上述「最小修正」全部落在卡片文字与判据层，不涉及实现。

---

## 12 必须改结构（不是改措辞）的四张卡

**PH-46**：验收结构要从「单文件 build 通过」改成「两单元夹具 + 归属政策」。
具体做法：在 `test/modules/p46_map_struct/` 里放 `doc.h.ct`（声明 `pub struct Doc { Map<char *, JsonRef> *slots; }` 与一个写函数）
和 `main.ct`（读 `get`/`foreach`/`len`），把「谁定义 `MapEntry`、谁发方法声明」当作 O1 的一部分验收；
若本期不做多单元，就删掉 O4 的 `--lib` 承诺，并在 O1 明写「仅限定义单元内访问」。
只加一个单文件夹具，等于把当前已知会失败的形态留在卡外。

**PH-47**：`put_owned` 需要从「新增一个入口」改成「所有权模型二选一」。
推荐直接删掉 `put_owned`，规定 `Map<Str,V>` 的键一律深拷贝（等价于主张席 D47-3′），
`Map<char*,V>` 维持借用，并把「借用/复制」写进 `get`/`remove` 的契约与夹具；
若坚持保留 `put_owned`，必须同时设计每条目的所有权位（不能动 `MapEntry` 字段，就要在 `Map` 侧带私有元数据），
并给出 `from`/`entry`/`release` 三条路径的所有权规则。两者取其一，不能只加一个方法名。

**PH-48**：核心不是「两处胶水点」，而是「跨单元 Drop 的声明通道」。
具体做法：给 `pub struct ... use Drop` 的导出头加一条非 `static` 原型（沿用 P34 S5b 的 `emit_inherent_protos` 先例），
由定义单元发真体、消费单元只发 `extern` 声明；同时把自动胶水的发射循环按 `struct` 的 owner 过滤，
否则外单元会因为不完整类型编译失败。L48-2 的「可见」要据此重新定义：可见 = 头里有真实原型，而不是「本单元有 impl 节点」。

**PH-50**：`try_get` 的签名可以保留，但所有权语义要重写。
「拷贝出参」对含 `retain`/`release` 的元素会产生双释放（`Vec<Str>` 已实测）；
要么规定 `try_get` 只返回借用视图（与 `get` 同受 L31-14 约束，但那就不可能通过 `V *out` 表达），
要么在写入 `*out` 前对元素 `retain`、并对覆盖的旧值 `release`，同时把「调用方不得再 `release`」写进契约。
无论选哪条，都要新增一条 `Vec<Str>` + 出参的 ASAN 用例，否则这条 API 会把新的内存安全缺口带进包里。
