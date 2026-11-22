# Ct 惯用优先级（idioms）

> 中文
>
> **定位**：选型与优先级，不是语法手册。语法与语义以 [language-spec](language-spec.md) 为准；
> 面向 C 程序员的迁移心智见 [guide-for-c-programmers](guide-for-c-programmers.md)。
>
> **适用版本**：当前主线 **ct-ast**（实际版本以 `ct -v` 为准）。
>
> **同步门禁**：附录 briefing 的每条编号断言都带 `§N`；`check-docs` 校验节号在规范里存在。
> briefing 是给编码助手的压缩事实，正文才是给人读的完整口径。

## 1. Ct 是构建在 C 之上的语言，不是 C 超集

C 的表达式、语句与类型核心按原语法可用；**v1.0 起不再自称 C 超集**（[spec §1.2](language-spec.md)）。
四类常见偏离：

1. **`new` 是上下文关键字**：`int new;`、`r.new` 仍是标识符；只有 `new T { … }` 是构造（[§4.71](language-spec.md)）。
2. **`T a[]` 只在形参 / 字段 / 无初始化声明中弃用**：改 `T[]` 或 `T a[N]`；v0.x 警告，v1.0 起硬错（[§4.69](language-spec.md)）。
3. **字符串字面量的裸类型仍是 `char *`**：要 owning 写 `String s = "x";`，要借用写 `Str v = "x";`（[§4.70](language-spec.md)）。
4. **`String` / `Str` 传给 `printf` 需要 `cstr()`**：`.data` 不保证 NUL 结尾（[§4.70](language-spec.md)）。

## 2. 所有权：先问“谁负责释放”

| 位置 | 规则 | 依据 |
| --- | --- | --- |
| 局部 / 参数 | `String` 自动 retain / release；`box<T>` 走显式 `retain` / `release` | §4.70、D-016 |
| `String` / `box` 字段 | 宿主 `use Drop` 且**无显式 `impl Drop`** → 编译器生成字段胶水；写显式 impl 则胶水消失，作者负责 | §4.70、D-016 |
| `Vec<T>` / `Map<K,V>` 字段 | 没有自动胶水；即使宿主 `use Drop` 也要显式 `release()` | §4.70 |
| 全局 | 没有作用域出口，显式 `release()` | §4.70 |
| ADT payload | 本轮不生成 Drop glue；按 move 语义只释放一次 | §4.73 |
| 引用环 | 作者责任；直接环有编译期告警，不是检测 | §4.72 |

## 3. 字符串：`String` 拥有，`Str` 借用

**判据只有一条**：这份数据过了这行还要活着 → `String`；只看一眼 → `Str`。

- 字面量 / 空串是只读区 immortal；`String s = "x";` 直接绑定 immortal 块，`release()` 是 no-op。
- `Str` 是 `{ptr,len}` 视图：**不能作 struct 字段或 `Map` 键**（硬错）；
  `Vec<Str>`、`Option<Str>`、ADT 负载、全局 `Str` 可编译，但存的是视图，owner 必须先于容器死亡（[§4.70](language-spec.md)）。
- 要独立副本用 `s.to_string()`；`char *` 没有 `to_string`，先变 `String` / `Str`。
- `char *` 的方法（`length` / `to_int` / `starts_with`）来自 std 包映射，必须
  `import std::str::CharStr;`（std 0.19.0 及以前叫 `std::str::String`，旧名一个 MINOR）。

## 4. 切片：`T[]` 替代“指针 + 长度”

- 传参写 `sum(int[] a)`，不要 `sum(int *a, int n)`；长度随指针走，子切片零拷贝。
- 位置白名单：参数 / 局部 / 返回；字段、全局、接口值、`box<T>`、`Option`/`Result`、容器、
  数组元素、泛型实参、闭包捕获一律硬错（[§4.69](language-spec.md)）。
- `s[i]` 带边界 trap；`s.get(i)` 软访问返回 0 指针；`const T[]` 写元素硬错。

## 5. 参数糖：`ref` / `out`

- 需要写回调用方 → `out T`；读写 → `ref T`；不要裸出参指针。
- `out` 有定值分析；owning 实参（`String` / `box` / `Vec` / `Map`）必须先初始化（[§4.68](language-spec.md)）。
- `ref` / `out` **没有生命周期保证**：可以存起来或传给更长寿命位置，靠契约与直接 lint（J-4b 契约待补）。

## 6. 错误：`Result<T,E>` + `?` + `errdefer`

- 可失败操作用 `Result<T, E>` + 后缀 `?`；错误出口用 `return err:`；清理用 `errdefer`（[§4.62](language-spec.md)、[§4.58](language-spec.md)）。
- 不要“错误码 + `goto` 清理”；不要用 sentinel 值冒充错误。
- `?` 只在外层返回 `Result` 时可用；`?:` 与三目消歧按 §4.62。

## 7. 多形态：`enum` 负载 + `match`

- 成员带括号负载即 ADT；`match` 是语句，分支体要花括号，没有 fallthrough（[§4.73](language-spec.md)）。
- 必须覆盖全部变体，或最后写一个 `_`；全部覆盖后再写 `_` 会被提示“多余”。
- **ADT 不生成 drop glue**：payload 里的 owning 句柄按 move 语义只释放一次；构造不 retain，
  绑定是浅拷贝，释放后原句柄悬垂。
- 上限：64 个 ADT / 16 变体 / 8 负载；无泛型 ADT、无 or 模式、无表达式形式 `match`。

## 8. 遍历：`foreach` 的隐式绑定

- 块内隐式绑定，**不是头列表**：正确写法 `foreach (v) { … i … item … }`；`{ i, item; }` 只是逗号表达式。
- 数组与 `Vec`：同时绑定 `item`（值拷贝）与只读 `i`；`i` 不回写容器。
- `Map`：**只绑定 `item`**，用 `item.key` / `item.value`；没有 `i`（[§4.49](language-spec.md)）。

## 9. 堆与指针

- 单对象堆分配用 `box<T> p = new T { … };`：16 字节句柄 + 8 字节 `{refs,aux}` 头；
  `p.f` 自动解引用；`at()` 是借用视图，`release()` 后失效（[§4.71](language-spec.md)）。
- `new` 只接受具名、非泛型 struct；跨单元 `box<T>` 仍有边界（单文件 / 单单元可用）。
- 指针**仍然合法**，但主要在 shim / MMIO / extern 与逃生层；应用代码先想 `Str` / 切片 / `box`。

## 10. 泄漏

- 默认 `warning`；`ct.pkg` 写 `leaks = error` 才让 build / compile 失败（[§4.72](language-spec.md)）。
- `c-boundary = strict` 是另一条边界，与泄漏无关。
- 引用环仍泄漏；直接环有编译期告警，`--debug-leaks` 只报未配对计数，不叫环检测。

## 11. 首选 / 避免速查

| 场景 | 首选 | 避免 | 依据 |
| --- | --- | --- | --- |
| 字符串参数 | `Str` | `String`（除非要所有权） | §4.70 |
| 字符串字段 | `String` | `Str`（硬错） | §4.70 |
| 数组参数 | `T[]` | `T *a, int n`；`T a[]` 形参 | §4.69 |
| 出参 | `out T` | 裸 `T *out` | §4.68 |
| 多形态数据 | `enum` + `match` | `int kind` + `switch` | §4.73 |
| 单对象堆分配 | `box<T>` + `new` | `own T*` + `malloc`（除非有转移语义） | §4.71 |
| 遍历 Map | `foreach` + `item.key` / `item.value` | 手写并行数组 | §4.49 |
| 错误处理 | `Result` + `?` + `errdefer` | 错误码 + `goto` | §4.62 |

## 附录 briefing

```text
你是 CT 语言（source-to-source 编译到 C）的编码助手。CT 的约定：

1. CT 是构建在 C 之上的语言；C 的表达式、语句与类型核心按原语法可用。v1.0 起不再自称 C 超集；四类偏离：new 是上下文关键字（int new; 仍合法）、T a[] 只在形参/字段/无初始化声明中弃用、字符串字面量裸类型仍是 char *、String/Str 传给 printf 需 cstr()。§1.2
2. 所有权分层：局部/参数自动 retain/release（String）；String/box 字段在宿主 use Drop 且无显式 impl 时有自动胶水；Vec/Map 字段、全局、ADT payload 需作者处理；引用环仍泄漏。§4.70 §4.72
3. Str 是借用视图：不能作 struct 字段或 Map 键；Vec<Str>/Option<Str>/ADT 负载/全局可编译但存的是视图；字面量常量表安全，非 immortal 来源有风险。§4.70
4. String 用字面量直接初始化；char * 方法需 import std::str::CharStr（std 0.19.0 及以前叫 std::str::String）。§5.1
5. 数组传参用 T[]，不要 int *a, int n；T a[] 形参/字段已弃用。§4.69
6. 可失败操作用 Result<T,E> + ? + errdefer，不要错误码 + goto。§4.62 §4.58
7. 多形态数据用 enum + match（穷尽），不要 int kind + switch；ADT 不生成 drop glue，payload 按 move 只释放一次。§4.73
8. 遍历用 foreach(item)；数组/Vec 有块内只读 i，Map 只给 item.key / item.value（没有 i）。§4.49
9. 堆单对象用 box<T> = new T { ... }；指针主要在 shim/硬件/逃生层，但合法。§4.71
10. 泄漏默认 warning；ct.pkg 的 leaks=error 才升级；动态派发的一行链当前被拒（SH-110 修复中），静态宿主链可用。§4.72
```
