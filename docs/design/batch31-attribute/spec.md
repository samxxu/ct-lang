# 第三十一批：GNU `__attribute__((…))`（2026-10-31）

> 锚点：`5d8b339`（第三十批收口），工作树干净。
> 实测缺口：`static void f(void) __attribute__((unused));` 在 ct-ast 下报
> `unexpected token`（L0 / L2 是透传，不受影响）。这是 language-spec §4 里最后一处
> 明确标为「未实现」的 C 形式。

## 1. 现状

- 属性出现在**声明符之后**：函数参数表之后、形参名之后、字段名之后、全局名之后、
  `typedef` 别名之后、`struct` / `union` / `enum` 定义体的 `}` 之后。ct 对它们没有语义，
  只需要「原样放到同一位置」。
- 这些位置分散在：`parse_func`（原型 / 定义 / 全局）、`parse_params`、`parse_field_def`、
  `parse_typedef`、`parse_record_def`、`parse_enum_def`。
- 节点没有现成的空槽位：`text3` 在字段/全局/形参上表示「数组维度」，判空有语义
  （`text3[0]` 决定是否按数组处理、是否补 vptr），不能借来存属性。

## 2. 决策

- **D-1 捕获整段原文**：新增 `ParseOps::attr_pool(int *out)`，把
  `__attribute__((…))`（含嵌套实参与连续多个组）按 token 原文写进 arena 字符串池，
  返回池内偏移；`out` 为 `-1` 表示「当前不是属性」。数字 token 用 `toknum`（词法层不给
  整数保留拼写），其余用 `toktext`。
- **D-2 Node 增加一个偏移字段**：`Node.attr`（`int`，`-1` = 无；否则池内偏移），
  `Arena::alloc` 置 `-1`。比在 Node 里放 160 字节字符串省内存（64 KiB 节点 × 4 字节）。
  函数**原型**不在节点里，`Fn` 同样增加 `int attr`，`add_func` 新建行时清为 `-1`，
  原型与定义先后出现时「非空才写」，后写的定义不会抹掉原型上的属性。
- **D-3 形参属性随 `pdim` 走**：`add_func` 把形参节点上的属性拼到 `pdim`（“名字+维度”
  的发射槽，只被 `emit_proto` 读取），因此原型与定义拼写一致。
- **D-4 发射位置**：
  - 函数定义：`) ` 之后、函数体之前；原型：`)` 之后、`;` 之前；
  - 形参：类型名/维度之后；字段：维度之后（位域则在宽度之后）；全局：声明符之后、
    `= ` 之前；`typedef`：别名之后；
  - `struct` / `union` / `enum`：`}` 之后；typedef 记录类型**统一放在别名之前**
    （`} __attribute__((packed)) Alias;`）——这是 clang 与 GCC 对 `packed` / `aligned`
    都生效的位置，源里写在别名之后也会被挪到这里。
- **D-5 诊断**：未闭合 → `unterminated __attribute__`；同一声明在两个捕获位置都写 →
  `duplicate __attribute__ on one declaration`。
- **D-6 边界（写进 §4.36）**：声明符**之前**的属性、局部变量、`impl` / trait 方法上的
  属性不在子集内；生成的 `.c` 保留原文，由 C 编译器解释。

## 3. 影响面

- 改：`frontend/parse/Parser.h.ct`（`attr_pool` + 六个调用点）、
  `frontend/parse/ParseSupport.h.ct`（`add_func` 拼 `pdim`、新行清 `attr`）、
  `frontend/sym/Symbols.h.ct`（`Fn.attr`）、`runtime/arena/Arena.h.ct`（`Node.attr`）、
  `backend/emit/Emitter.h.ct`（原型 / 定义 / 形参 / 字段 / 全局 / `typedef` / 记录与枚举尾部）。
- **impl 方法预算**：新增 1 个（`ParseOps::attr_pool`）；构建未触发 `MAX_MAP_IMPLS`（256），
  但余量已极少，下一批若再加方法需先扩该上限（需用户授权改 `l2/**`）。
- 不动：节点编号、L0 / L1 / L2、`CTC_VERSION`、既有 golden（新 fixture 之外零改动）。

## 4. 验证

- 新增 `test/ast/54_attribute`：全局 `aligned(16)`（地址取模 0）、字段 `aligned(8)`、
  `struct {...} __attribute__((packed))`（`sizeof` = 5）、typedef struct 的 `packed`、
  `typedef int word __attribute__((aligned(8)))`（`_Alignof` ≥ 8）、enum 后的属性、
  原型与定义分别带 `unused` / `format(printf, 1, 2)` / 连续两组属性、形参 `unused`。
- 负例：`attribute_unterminated.ct`、`attribute_duplicate.ct`（`check-ast.sh` 精确断言）。
- clang 与 GNU GCC 16 都零告警构建生成物，输出一致。
- 关卡：`check-ast.sh` → 295 passed；`check-warnings.sh` → 如实记录；
  `check-all.sh` → 九关全绿。
