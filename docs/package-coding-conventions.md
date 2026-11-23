# Ct 包编码通用条款（CG-1…CG-7）

> 中文
>
> **来源**：规范仓 `methodology/ct-package-coding-general.md`，经 PROP-004 移交（2026-11-23）；
> 原规范自 `1.15.0` 起纳入。条款正文未改，只按本仓书写规范写作 Ct，并补来源与权威关系；
> 受理记录见 [DOC-95](../issues/docs/doc-95-package-coding-conventions-intake.md)。
>
> **适用**：任何 Ct 包的公开 API 与实现组织。**不适用**：包专属条款、模块名与方法表，
> 这些留在各包自己的 `docs/`。
>
> **权威关系**：命名细则以
> [language-spec §5.1](language-spec.md#51-源码命名约定语言--标准库--ct-pkg稳定契约) 为准；
> 清单键与工具行为以 [package-guide](package-guide.md) 为准。本文只补「包 API 怎么设计」
> 这一层的判据；冲突时以二者为准，并修正本文。
>
> **生效**：Ct 侧自 2026-11-23 起。规范仓在方法论 2.0.0 发布时删除或只读存档原文件。

> 本文只写对任何 Ct 包都成立的条款，不绑定具体模块、方法表或单个包的名字账本。

## 章节索引

| 编号 | 条款 | 去哪读 |
| --- | --- | --- |
| CG-1 | 命名 | §1 |
| CG-2 | 只有对象式调用 | §2 |
| CG-3 | 能力寄生基础类型 | §3 |
| CG-4 | ①/②/③ 三层与便利层准入 | §4 |
| CG-5 | 资源由工厂出 `own`，释放留包内 | §5 |
| CG-6 | 显式失败与部分读写处理 | §6 |
| CG-7 | 映射即唯一实现 | §7 |

## 1. 命名

| # | 规则 | 判据 |
| --- | --- | --- |
| CG-1 | 标识符用 `snake_case`；默认全称，只有扫一眼不用想就知道的缩写才留；数学记号保留原样；方法名不重复宿主或类型已交代的信息 | 缩写能在包内找到同类先例；`device.tmo()`（缩写）、`circle.area_of_circle()`（重复宿主）、`path.file_mode()`（重复类型信息）、`angle.sine()`（改写数学记号）均不通过 |

```ct
/* 正例 */
device.timeout();
circle.area();
connection.reconnect();
path.mode();
angle.sin();
```

```ct
/* 反例 */
device.tmo();              // 错：缩写
circle.area_of_circle();   // 错：重复宿主
path.file_mode();          // 错：重复对象的类型信息
angle.sine();              // 错：sin 是通用数学记号，保留原名
```

## 2. 只有对象式调用，没有裸函数入口

| # | 规则 | 判据 |
| --- | --- | --- |
| CG-2 | 能力一律挂宿主；同一能力不另设自由函数入口 | 对象式入口存在时，再出现同名或同义的裸函数入口即不通过（如 `copy_from(buffer, src, n)`） |

```ct
/* 正例 */
buffer.copy_from(src, n);
item.refresh();
```

```ct
/* 反例 */
copy_from(buffer, src, n);  // 错：裸函数入口，与对象式重复
```

## 3. 能力寄生在基础类型上（含工厂寄生）

| # | 规则 | 判据 |
| --- | --- | --- |
| CG-3 | 先寄生既有基础类型；工厂从字符串起头，不新增对象包装 | 为字符串另造类型（`resource_new("config")`）、或工厂不从字符串起头（`load(r)`）即不通过 |

```ct
/* 正例 */
"config".load();
"dir".open_dir();
```

```ct
/* 反例 */
Resource r = resource_new("config");  // 错：为字符串另造类型
load(r);                              // 错：工厂没有从字符串起头
```

## 4. ①/②/③ 三层与便利层准入

| # | 规则 | 判据 |
| --- | --- | --- |
| CG-4 | ① 零代码映射；② 便利方法；③ 只给真持有资源。② 的门槛是「明显更短、读着更自然」，不是「能包就包」 | 新增 ② 须给出与 ① 的对照，证明更短或更自然；只为包装而包装、或给没有资源生命周期的类型套 ③，均不通过 |

```ct
/* 正例 */
native_call(&state);                 // ① 直连
"abc".starts_with("a");              // ② 明显更短
own Handle h = "res".open();         // ③ 真持有资源
```

```ct
/* 反例 */
struct Byte { int v; };              // 错：基础类型足够，不必建 struct
"abc".lowercase_text();              // 错：没有比 lowercase 更短或更自然
```

## 5. 资源对象由工厂出 `own`，释放留包内

| # | 规则 | 判据 |
| --- | --- | --- |
| CG-5 | 工厂返回 `own` 句柄；离开作用域由包内关闭；显式 `close()` 只供提前关闭，且幂等 | 公开接口不出现裸句柄外泄，也不把释放责任交给调用方；`close()` 重复调用不得失败 |

```ct
/* 正例 */
{
    own Handle h = "res".open();
    h.use();
}   /* 包内关闭，调用方不 free */
```

```ct
/* 反例 */
Handle *h = open_raw("res");   // 错：裸句柄外泄
/* ... */
close_raw(h);                  // 错：释放责任丢给调用方
```

## 6. 显式失败返回、部分读写与 `EINTR`

| # | 规则 | 判据 |
| --- | --- | --- |
| CG-6 | 失败用显式返回值；读写按实际字节数循环；`EINTR` 重试，不假定一次读满 | 把一次调用当作读满（`h.read(buf, want)`）、或把 `EINTR` 与真实错误合并处理（`if (n < 0) return;`）均不通过 |

```ct
/* 正例 */
char buf[4096];
int total = 0;
while (total < want) {
    int n = h.read(buf + total, want - total);
    if (n < 0) {
        if (errno == EINTR) continue;
        break;
    }
    if (n == 0) break;
    total += n;
}
```

```ct
/* 反例 */
h.read(buf, want);          // 错：忽略部分读
if (n < 0) return;          // 错：没有区分 EINTR 与真实错误
```

## 7. 映射就是唯一实现

| # | 规则 | 判据 |
| --- | --- | --- |
| CG-7 | 每个能力只有一个实现：`shim` 转发平台函数，方法层复用 ①；便利层不复制逻辑 | 方法层绕过 ①/`shim` 另写算法（如自行扫描字符串求长度）、或同一逻辑在两处出现，即不通过 |

```ct
/* 正例 */
int width() { return platform_width(self); }
char *to_text(out, cap) { return platform_to_text(self, out, cap); }
```

```ct
/* 反例 */
int width() {
    int n = 0;
    while (self[n]) n++;     // 错：绕过 ①，另写一套实现
    return n;
}
```

## 8. 与现有文档的分工

| 条款 | 细则在哪 |
| --- | --- |
| CG-1 命名 | 源码命名契约见 [language-spec §5.1](language-spec.md#51-源码命名约定语言--标准库--ct-pkg稳定契约)；包名与依赖范围见 [package-guide §3](package-guide.md#3-命名与依赖版本范围)；本文只给包 API 判据 |
| CG-2 对象式调用 | 本文 |
| CG-3 能力寄生 | 本文 |
| CG-4 三层模型 | 本文 |
| CG-5 资源与释放 | `own` / `Drop` / `Box<T>` 语义见 [language-spec §4.71](language-spec.md#471-box--new单对象句柄phase-81仅-ct-ast) 与 [memory-guide](memory-guide.md)；本文只给包公开接口的责任边界 |
| CG-6 显式失败 | 本文（实现侧）；C 边界契约见 [c-shim-contract](c-shim-contract.md) |
| CG-7 映射唯一实现 | 本文；binding / `map` 写法见 [package-guide](package-guide.md) 与 [test/bindings/README.md](../test/bindings/README.md) |
