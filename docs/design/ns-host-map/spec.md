# 规格：命名空间宿主 map（SH-20）

状态：已确认路线，待实现
锚点：commit `c423533`（Batch 2 复核修复收尾）
关联：`issues/selfhost/ct-ast-map-requires-instance.md`、`docs/language-spec.md` §4.10

## 1. 目标

让 `map` 可以不依附任何全局对象，直接把 trait 绑定到**一个命名空间**，并在消费侧
用一个表达式取得该绑定对应的接口值。目标是纯函数式 C 库（socket / epoll / zlib）的
绑定不再需要伪造宿主变量。

明确的目标形态：

```ct
namespace hal;
pub trait Writer { int write(char *buf, int len); }
int hal_write(char *buf, int len) { ... }

map trait Writer for namespace hal {
    write(buf, len) -> hal_write(buf, len);
}

// 消费侧：不声明任何实例
Writer w = Writer::hal;
w.write(buf, 8);
```

## 2. 语法

### 2.1 map 声明

```
map trait <TraitName> for instance <name>            { ... }   // 既有形态，保留
map trait <TraitName> for namespace <NsPath>         { ... }   // 新增
```

- `<NsPath>` 是一段或多段标识符，以 `::` 连接（`hal`、`hal::netlib`）。
- `for` 之后不是 `instance` 或 `namespace` 时报
  `expected 'instance' or 'namespace'`。
- 命名空间宿主**不校验该命名空间是否存在**（编译器没有命名空间注册表）；
  RHS 的解析与 C 编译器的符号检查仍是兜底。

### 2.2 装箱表达式

```
<TraitName>::<NsPath>
```

- 只有 `<TraitName>` 解析为**trait**（`type_kind == 3`）时才走新形态；`struct` /
  `typedef` 限定符保持既有语义（有 `(` 是限定调用，无 `(` 是限定变量引用）。
- 路径末段后跟 `(` 时仍是限定调用，不进入新形态。
- 只支持 trait 的**裸名或 alias**（`Writer` / `W`）；`hal::Writer::hal` 这种带命名空间
  的 trait 限定名不在本次范围（与 SH-18 的限定类型名限制一致）。

## 3. 语义

- 接口值的 `self` 是 **`(void *)0`**。
  - wrapper 体内的 `(void)self;` 已经成立，self 不会进入用户代码。
  - **不合成**宿主变量，不新增任何 C 符号，因此不会有 `-Wunused-variable` 或
    全局符号污染。
- 命名空间宿主是**无状态单例**：所有装箱得到的接口值共享同一张 vtable，`self` 恒为 0。
- 命名空间宿主**禁止直绑**（`-> f;`）：vtable 槽的首参是 `void *self`，直绑会把 NULL
  当作目标函数的第一个实参交给一个本来没有该参数的纯 C 函数。报
  `a namespace host has no self: bind with a wrapper call`。
- 一个 `(prefix, trait)` 只允许一个 map（跨单元同样生效）。
- 既有的 `instance` 形态完全不变，`void *host;` 这种占位写法继续有效。

## 4. 命名规则

设：

- `h` = 宿主命名空间路径把 `::` 换成 `_`（`hal::netlib` → `hal_netlib`）；
- `rtrait` = trait 的 C 名（已按命名空间 mangling，如 `hal_Writer`、`net_Stream`）。

```
symbol prefix p = rtrait                  当 rtrait 以 h + "_" 开头
                = h + "_" + rtrait        否则

wrapper = p + "_" + <method>
vtable  = p + "_vtable"
```

例：

| trait | 宿主 | 前缀 | vtable |
| --- | --- | --- | --- |
| `hal::Writer` | `hal` | `hal_Writer` | `hal_Writer_vtable` |
| `net::Stream` | `hal` | `hal_net_Stream` | `hal_net_Stream_vtable` |

既有的变量宿主保持原规则：前缀 `<实例 C 名>_<trait>`，如 `hal_uart1_hal_Writer_vtable`。

所有拼接都要做 `MAX_TEXT`（160）溢出检查，超长走 `fail("... is too long")`。

## 5. 导出与链接

- **变量宿主**：`pub trait` 且实例是 `pub` 全局时 vtable 外部链接（现状）。
- **命名空间宿主**：只要 `pub trait`，vtable 即外部链接；provider 的 `.h` 写
  `extern struct <Trait>_vtbl <vtable>;`，`.c` 定义它；wrapper 保持 `static`。
- `--emit-map` 的 `maps[]` 增加 `"host": "namespace" | "instance"`；`instance` 字段保留，
  命名空间宿主时填宿主路径（如 `hal`）。

## 6. 诊断

| 场景 | 消息 | 位置 |
| --- | --- | --- |
| `for` 后关键字不对 | `expected 'instance' or 'namespace'` | `for` 行 |
| 命名空间宿主直绑 | `a namespace host has no self: bind with a wrapper call` | 绑定行 |
| 同 prefix 的重复 map | `duplicate map of trait '<t>' for instance '<i>' (first at <path>:<line>)` | map 行 |
| trait 不匹配的装箱 | `interface type mismatch`（`maybe_box` 既有诊断） | 使用点 |
| 命名空间宿主值用在非接口目标 | `a namespace host value is only usable as an interface value` | 装箱行 |
| 没有任何 map 绑定该 trait×宿主 | `no map binds trait '<Trait>' to namespace '<path>'` | 装箱行 |

最后两条依赖发射期校验（实现见 §7.5），因为装箱点解析时同文件后面的 map 可能尚未登记。

## 7. 实现清单（精确到文件与函数）

### 7.1 `selfhost/ct-ast/frontend/module/Map.h.ct`

`struct Map` 增加：

```ct
char prefix[160];   /* wrapper / vtable 的符号前缀（§4） */
int  ns_host;       /* 1 = 命名空间宿主 */
```

`vtable` 改为由 `prefix` 派生，`cname` 保留（装箱与 JSON 用）。

### 7.2 `selfhost/ct-ast/frontend/parse/MapBuild.h.ct` — `parse`

- 把 `expected 'instance'` 分支改为二选一；新增的 namespace 分支：
  - 逐段读取标识符，同时累积 `inst`（源写法，`::` 连接）与 `icn`（`_` 连接）。
  - 置 `m->ns_host = 1`，跳过 `find_var` / `var_cname`。
- 计算 `prefix`（§4）与 `vtable`，所有 `snprintf` 做溢出检查。
- 重复检测的键从 `(trait, inst)` 改为 `prefix`（前缀相同即会重复发射同一批符号）。
- 绑定循环中计算 `b->wrapper` 时改用 `m->prefix`。
- `b->direct` 判定后：`if (b->direct && m->ns_host) fail(...)`。

### 7.3 `selfhost/ct-ast/frontend/parse/Expr.h.ct`

- `ExprOps::parse_qual_path` 增加出参 `int *form`（0 = 限定变量，1 = 限定调用，
  2 = 命名空间宿主值）。`parse_qual_path` 在 `!is_call` 且 `seg[0]` 解析为 trait 时：
  - `name` ← trait 的 C 名（覆写，供调用方使用）；
  - `cname` ← 宿主前缀 `h`；
  - `qpath` ← 宿主源路径（`::` 连接，供诊断）；
  - `*form = 2`。
- `parse_primary`：`form == 2` 时构造装箱节点
  （`kind = N_BOX`，`text` = trait C 名，`text2` = 宿主前缀，
  `text3` = `"<源 trait 名>|<宿主路径>"`，`a = -1`，`aux = 4`，`b = -1`），直接返回。
  `form == 0` 走既有 `find_qualified_global`。

### 7.4 `selfhost/ct-ast/frontend/type/TypeCheck.h.ct`

- `expr_type` 的 `N_BOX` 分支：指针判定由 `aux >= 2` 改为 `aux & 2`。
- `maybe_box` 的 `N_BOX` 快速路径：
  - 先比对 `nodes[n].text` 与期望 trait，不等报 `interface type mismatch`；
  - 通过后置 `nodes[n].b = 1`（表示「已被正确接口上下文接收」），再按现有逻辑处理
    `addr`（需要取地址时套 `N_ADDR`）。

### 7.5 `selfhost/ct-ast/backend/emit/Emit.h.ct`

- `emit_expr` 的 `N_BOX` 分支改为按位处理：
  - `aux & 2` → 前缀 `&`；
  - `aux & 4` → self 发射 `0`，vtable 用 `&<text2>_vtable`；
  - 否则保持「操作数是变量则取地址、是指针则直接转」的原逻辑；
  - `aux & 4` 时先做两项校验：`nodes[n].b != 1` 报
    `a namespace host value is only usable as an interface value`；
    在 `maps` 中找不到 `trait == text && prefix == text2` 的条目时报
    `no map binds trait '<text3 前半>' to namespace '<text3 后半>'`。
- `map_vtable_exported`：`ns_host` 时只看 `pub trait`，不再查 `pub` 全局。
- `write_map`：`maps[]` 条目增加 `"host"` 字段。
- `emit_maps` 无需改动（wrapper / vtable 名都已由 `Map` 存好）。

### 7.6 不动的部分

- L0 / L1 / L2 完全不涉及（map 不在冻结内核里）。
- 不新增 Module 方法，不改 `driver.ct`、`load_unit`（校验放在发射期）。
- 不改任何既有 golden（本次是新增语义，`compile` 输出对既有用例不变）。
- 不 bump `CTC_VERSION`。

## 8. 验证计划

新增 fixture：

1. `test/ast/26_ns_host/prog.ct` + `prog.expected.out`：单文件、命名空间宿主 map、
   `Writer w = Writer::hal;` 装箱并派发；断言生成物含 `(void *)0` 与
   `&hal_Writer_vtable`。
2. `test/ast/errors/ns_host_no_map.ct`：`Writer w = Writer::nosuch;` 无对应 map →
   非零退出且定位诊断。
3. `test/ast/errors/ns_host_direct.ct`：命名空间宿主 + `-> f;` 直绑 → 非零退出。
4. `test/modules/ns_host/`（`hal.ct` + `main.ct` + `expected.out`）：跨单元装箱；
   `hal.h` 含 `extern struct hal_Writer_vtbl hal_Writer_vtable;`，`hal.c` 定义它，
   wrapper 仍是 `static`；`main.c` 含 `(void *)0`。
5. `selfhost/check-ast.sh`：新增上述模块断言块与两条负例的精确消息断言；
   `check-warnings.sh` 若为显式枚举则补新用例。

执行顺序：

```sh
rm -rf /tmp/ctb/astsrc
/tmp/ctb/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/ctb/astsrc
cc -Wall -Wextra -std=c99 /tmp/ctb/astsrc/*.c -o /tmp/ctb/ct-ast
bash selfhost/check-ast.sh
bash selfhost/check-warnings.sh
bash selfhost/check-all.sh        # 九关全绿
```

文档同步：

- `docs/language-spec.md` §4.10：语法、NULL self、命名规则、导出、禁止直绑、两条新诊断；
  中英双语对称；同时修订「编译器不替未声明名字合成宿主」一段，改为
  「对象宿主不合成；无对象时用命名空间宿主」。
- `issues/selfhost/ct-ast-map-requires-instance.md`：状态改为已修复，记录最终方案。
- `issues/README.md`：SH-20 处置表行改为已修。

## 9. 非目标

- 不支持裸命名空间值（`Writer w = hal;`）。
- 不支持 `hal::Writer::hal` 这类带命名空间的 trait 限定名。
- 不允许命名空间宿主直绑。
- 不改变量宿主的任何既有行为。
- 不引入命名空间注册表，不对宿主命名空间的存在性做静态校验。
