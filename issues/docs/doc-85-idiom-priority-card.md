# DOC-85 · 惯用优先级卡：事实修正后入 `docs/idioms.md`

| 项 | 值 |
| --- | --- |
| 模块 | docs（读者路径 / 惯用法） |
| 定性 | 文档缺口 + 事实修正 |
| 严重度 | Medium |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [外部评审与惯用卡评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md) §2 |
| 状态 | verified |
| 处置证据 | **已完成（2026-11-21：`docs/idioms.md` 入库；briefing 10 条带 §N；门禁激活）** |

## 进展（2026-11-21）

- 成文 [docs/idioms.md](../../docs/idioms.md)：C 之上 + 四类偏离、所有权分层、`String`/`Str`、
  切片、`ref`/`out`、错误、ADT、`foreach`、堆与指针、泄漏、首选/避免速查；附录 briefing 10 条。
- **briefing 同步门禁已激活**：`check-docs` 输出 `10 briefing item(s)`，每条断言的 `§N`
  都能在规范解析到标题；缺节号或节号不存在即红。
- **抽查 3 条（至少含 `foreach`）**：
  - `foreach` → §4.49：数组/Vec 绑定只读 `i`，`Map` 只给 `item.key` / `item.value`（spec:2513）；
  - `String`/`Str` 存放位置 → §4.70：字段 / `Map` 键硬错，`Vec<Str>` 等存视图（spec:2975-2976）；
  - `new` 上下文关键字 → §4.71：`int new;` 仍合法（spec:2993）。
- 入口已加：`docs/README.md` 生态表、`llm-guide.md` 文档地图、README §3「先读」路径。
- 评审台账销项：[外部评审评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md)
  §2 结论与 §3 落点已改为“已按修正稿入库”。

## 现象

外部《CT 惯用优先级卡》方向正确，但原稿有硬伤，不能直接入 `docs/idioms.md`：

| 原稿 | 问题 | 修正 |
| --- | --- | --- |
| “CT 是 C 的超集” | 与 DOC-76 冲突 | 改为下方“开头叙事修正版” |
| “指针只出现在 shim/MMIO/extern” | 指针在任何 `.ct` 合法 | 改为“指针主要留在 shim/MMIO/extern 与逃生层；应用代码优先 Str/切片/box；指针仍合法” |
| `"42".to_int()` | 需 `import std::str::CharStr;`（0.19.0 及以前叫 `std::str::String`，旧名一个 MINOR 回退） | 补 import 前提；内置层不自动带 |
| “借用类型不能存（字段/容器/全局 = 硬错）” | `Vec<Str>` / `Option<Str>` / ADT 负载可编译；全局 `Str g = "x"` 也可编译 | struct 字段 / `Map` 键硬错；全局/容器/ADT 是借用视图风险；常量表安全，非 immortal 视图 lint 另立 [LANG-22](../lang/lang-22-nonimmortal-view-store-lint.md) |
| “返回局部视图 = 硬错” | `Str` 逃逸当前无 lint（SH-106）；`T[]` 是 warning | 改为“返回局部 `Str` 视图当前无 lint；返回局部 `T[]` 是 `slice escape` warning；两者归契约 + ASan” |
| “owning 自动释放” | 局部/参数自动；`String`/`box` 字段在宿主 `use Drop` 且无显式 impl 时有字段胶水；`Vec`/`Map` 字段无胶水；全局/ADT payload 显式；环泄漏 | 按类型 + 位置分层（下方） |
| “泄漏 = 告警（strict 包内 error）” | 实际是 `ct.pkg` 的 `leaks = warn\|error`，与 `c-boundary=strict` 无关 | 改为“泄漏默认 warning；`leaks=error` 才升级；strict 是另一条边界” |
| `foreach (v) { i, item }` | `i` / `item` 是**块内隐式绑定**，不是头列表；`{ i, item; }` 只是逗号表达式 | 正确写法 `foreach (v) { … i … item … }`；数组/Vec 绑定只读 `i`，`Map` 只给 `item.key` / `item.value` |
| 附录 briefing | 重复上述错误 | 同步修 |

## 开头叙事（2026-11-21 修正版）

`docs/idioms.md` 的开头按下面这段写，不再使用“C 的超集”：

> **CT 是构建在 C 之上的语言：C 的表达式、语句与类型核心按原语法可用；CT 在其上增加
> trait、句柄、借用、ADT 等声明式层。从 v1.0 起，CT 在四个最常见的语义点上明确偏离 C
> （不承诺穷举）：**
>
> 1. `new` 是上下文关键字：只有 `new T { … }` 构造时特殊；`int new;`、`new = 5;`
>    仍是普通标识符。
> 2. `T a[]` 只在形参、字段或无初始化声明中弃用；`T a[] = { … }` 仍保留为推断长度数组。
> 3. 字符串字面量的裸类型仍是 `char *`；在借用上下文按 `Str` 视图传递，
>    `String s = "x"` 绑定 immortal 块。
> 4. `String` / `Str` 传给 `printf("%s")` 需 `s.cstr()`；`char *` 字面量仍可直接传。
>
> 脚注：保留字与 strict 边界（`#include` / 函数式宏）还有额外偏离，
> 见 spec §4.66 / §4.70 / §4.71。

“原样可用”只指**核心语法**，不承诺任意 C 源文件原样通过。

## 两档宣言修正（原卡 §3）

原卡“基础档/进阶档”里的“借用类型不能存（字段/容器/全局 = 硬错）”按实测改为：

- **硬错**：`Str` 作 struct 字段、`Map<Str,V>` 的键；
- **可编译但存的是视图**：`Vec<Str>`、`Option<Str>`、ADT 负载、全局 `Str`；
  owner 必须先于容器/值/全局的初始化源存活；全局只应指向 immortal 字面量；
- **安全惯用法**：`Vec<Str> names = { "uart0", "uart1", "i2c0" };` 全是 immortal 字面量，
  永远安全，不禁止；
- **非 immortal 视图**（如 `v.push(local_string.as_str())`）→ 规划中的 **warn 级 lint**
  （[LANG-22](../lang/lang-22-nonimmortal-view-store-lint.md)，v1.1），不做硬错。

## owning 释放分层（v0.88 实测）

- **局部/参数**：自动 retain/release；
- **`String` / `box<T>` 字段**：宿主 struct `use Drop` 且**没有显式 `impl Drop`** →
  编译器生成字段胶水；写了显式 `impl Drop` 就由作者负责；
- **`Vec<T>` / `Map<K,V>` 字段**：自动胶水为空；即使宿主 `use Drop`，也要显式 `release()`；
- **全局**：没有作用域出口，必须显式 `release()`；
- **ADT payload**：本轮不生成 Drop glue（v0-PH-84 简化项，v1.1 可能变）；
- **引用环**：仍泄漏。

字段不是“一律不释放”，而是“释放挂在宿主的 Drop 上”；宿主没有 Drop 路径才是泄漏。

## 附录 briefing 修正版（2026-11-21）

```text
你是 CT 语言（source-to-source 编译到 C）的编码助手。CT 的约定：

1. CT 是构建在 C 之上的语言；C 的表达式、语句与类型核心按原语法可用。
   v1.0 起有四类常见偏离：new 是上下文关键字（D-016；int new; 仍合法）；
   T a[] 只在形参/字段/无初始化声明中弃用；字符串字面量的裸类型仍是 char *；
   String/Str 传给 printf 需 cstr()。
2. 所有权：局部/参数自动 retain/release；String/box 字段在宿主 use Drop 且
   无显式 impl 时有自动胶水；Vec/Map 字段、全局、ADT payload 需作者处理；
   引用环仍泄漏。
3. Str 是借用视图：不能作 struct 字段或 Map 键；Vec<Str>/Option<Str>/ADT 负载/
   全局可编译但存的是视图；字面量常量表安全，非 immortal 来源有风险。
4. String 用字面量直接初始化；char * 方法需 import std::str::CharStr
   （std 0.19.0 及以前叫 std::str::String）。
5. 数组传参用 T[]，不要 int *a, int n。
6. 可失败操作用 Result<T,E> + ? + errdefer，不要错误码 + goto。
7. 多形态数据用 enum + match（穷尽），不要 int kind + switch。
8. 遍历用 foreach(item)；数组/Vec 有块内只读 i，Map 只给 item.key / item.value。
9. 堆单对象用 box<T> = new T { ... }；指针主要在 shim/硬件/逃生层，但合法。
10. 泄漏默认 warning；ct.pkg 的 leaks=error 才升级。动态派发的一行链当前被拒
    （SH-110 修复中）；静态宿主链可用。

权威：docs/language-spec.md；guide-for-c-programmers.md；idioms（待入库）。
```

## 期望

1. 按上表修正原稿，新增 `docs/idioms.md`；
2. 从 `docs/README.md` 与 `llm-guide.md` 的读者路径引入，避免“仓库一套、外部一套”；
3. 与 [DOC-86](doc-86-readme-v088-rewrite.md)（README 大改）同批施工；
4. 不把原稿直接复制入库；修正稿逐条对照本 issue；
5. **同步门禁**：`docs/idioms.md` 入库时，briefing 每条关键断言标 spec 节号。
   该门禁已挂进 `docs/README.md` 文档约定第 8 条，并由 `check-docs` 的
   `check_idiom_briefing` 执行：编号断言缺 `§N` 或节号在 `language-spec.md`
   中不存在即红；`idioms.md` 未入库时该检查跳过，文件落地即生效。
6. **拼写依赖**：briefing 与正文的 `box<T>` 依赖 [LANG-24](../lang/lang-24-box-pascalcase-rename.md)。
   卡片按目标版本择一：v1.0 起写 `Box<T>`（`box<T>` 只作迁移说明），v1.1 起只写 `Box<T>`；
   不与 LANG-24 的落地版本冲突。

## 验收

- 修正稿不再出现“超集”“只出现在”“一律硬错”“i, item”；
- 每个“首选/避免”条目可在 spec、guide 或实测找到出处；
- `check-docs` 绿；`idioms.md` 不重复 `language-spec` 的完整语法表。

## 非目标

- 不新增语言特性；
- 不改 `llm-guide.md` 的既有行为规矩（只加读者路径）。

## 关联

- [评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md)
- [DOC-86](doc-86-readme-v088-rewrite.md)
- [SH-106](../selfhost/sh106-str-view-escape-no-lint.md)
