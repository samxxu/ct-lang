# 第三十批：`.h.ct` 规则落地（2026-10-31）

> 锚点：`d4061f4`（第二十九批收口），工作树干净。
> 实测缺口：`is_hdr` 只写不读（`Unit.h.ct` / `Module.h.ct`），`build` 对每个单元无条件
> `write_unit_header`，每个 `.c` 无条件 `#include "<base>.h"`，`Cache::hit` 也要求 `.h`
> 存在。于是 v0.13 的实际行为是「每个单元都产 `.h`」，与 roadmap「只有 `.h.ct` 才产 `.h`、
> `foo.ct` 不对外暴露接口」的约定不符（roadmap 的「落地说明」当时记录了这半未落地、推迟
> 到 Phase 5，Phase 5 之后再未回头）。

## 1. 现状与取舍

- `.h` 是 ct 的**接口产物**：`pub` 类型、`pub` 原型、`extern` 全局与 vtable 声明都写在里面，
  导入方的 `.c` 靠 `#include "<dep>.h"` 拿到声明。
- 因此「普通 `.ct` 不产 `.h`」不能只删一行写文件：`import` 一个普通 `.ct` 的单元就没有
  可包含的接口。两个自洽方向：
  - **严格**：只有 `.h.ct` 发布接口，普通 `.ct` 是入口 / 实现文件，**不可被 import**；
  - 产物式：普通 `.ct` 不落 `.h`，但声明由导入方 `.c` 内联（需去重守卫，发射器大改）。
- 用户 2026-10-31 拍板选**严格**方向：这条规则本来就是「文件名决定生成行为」，
  被 import 的单元应当显式命名为 `.h.ct`。

## 2. 决策

- **D-1 只有 `.h.ct` 写 `.h`**：`build` 里 `write_unit_header` 只在 `units[u].is_hdr` 时调用；
  `compile` 模式没有单元表，按输入路径后缀判断（`Module::write_header`）。两种模式一致。
- **D-2 `import` 只解析 `.h.ct`**：先在所有根（导入方目录，再 `-I` 根，命令行顺序）找
  `<rel>.h.ct`；一个都没有时再找 `<rel>.ct`，命中就报具名错误
  `only a .h.ct unit can be imported: rename 'x.ct' to 'x.h.ct'`（仍按 local-first）。
  找不到任何候选仍是原来的 `cannot resolve import 'x'`。
- **D-3 实现单元的 `.c` 自包含**：不再 `#include` 自己的头；`pub` 类型改为在 `.c` 里发射
  （原来 `d == 1` 就跳过，因为声明在头里）。函数原型本来就对每个函数发射，不需要改。
- **D-4 缓存命中按 `need_h`**：`Cache::hit(outc, key, need_h)`，实现单元不再要求 `.h` 在盘上；
  `.c` 仍然必须存在，键仍是纯函数（与 L2 逐字节一致，缓存键关卡不变）。
- **D-5 被导入单元改名 `.h.ct`**：`test/modules/**`、`bindings/mock-hal/uart.ct` 以及 ct-ast
  自身的 `tool/{diag/diag,driver/driver,pkg/pkg}.ct`。`import` 行不用改（路径解析按基名）。
- **D-6 `hdr` / `hdr_prologue` 的入口改为 `main.h.ct`**：这两个 fixture 断言的是「头文件前言
  复制 `#include`、不复制 `#define`」，只有在入口是头单元时才成立；语义不变，改名即可。
- **D-7 L2 保持附加式**：`l2/**` 冻结，`test/archive/**` 逐字节比对 `foo.ct` 的 `.h`，
  因此这是 **ct-ast 与 L2 的已知分叉**，登记在 language-spec 顶部的「有意拒绝」表。
- **D-8 L2 designed goldens 只重生成路径变化的 8 个单元**：`test/modules/{inc,ns_dir,ns_funcs,
  ns_qual,precedence,split,hdr}` 的 `*.expected.{c,h}`；diff 只有 banner 与 `#line` 的源路径
  （版本由 `same_modulo_version` 归一化）。

## 3. 影响面

- 改：`frontend/module/Module.h.ct`（`resolve_import` 两遍搜索、条件写头、`write_header`
  后缀判断、缓存调用）、`frontend/module/Unit.h.ct`（字段注释）、
  `backend/emit/Emitter.h.ct`（条件自包含 + `pub` 类型本地发射）、
  `tool/cache/Cache.h.ct`（`hit` 增加 `need_h`）。
- 改名：ct-ast 3 个单元、bindings 1 个、`test/modules/**` 27 个（含 `inc_missing`、`hdr`、
  `hdr_prologue` 的入口）。
- 关卡：`check-ast.sh`（split 产物断言、hdr/hdr_prologue/ns_dir 路径、corpus 的「无 `.h`」
  断言、compile 模式两条契约断言、新负例 `import_plain_ct`、dup_impl 的 `a.h.ct` 断言）、
  `check-warnings.sh`（入口可为 `main.h.ct`）、`ct-tour.sh`（缓存演示的产物断言）、
  `test/pkg/run.sh`（包的单元改为 `util.h.ct`）。
- 不动：类型层 / 解析层 / `l2/**` / `test/archive/**` / `CTC_VERSION`。

## 4. 验证

- 新增负例（inline）：`import` 普通 `.ct` 报具名错误，且提示改名；`split` 断言
  `shapes.h` / `impl_dog.h` 存在、`main.h` 不存在；compile 模式分别断言 `.ct` 无头、
  `.h.ct` 有头且 `.c` 不包含它。
- ct-ast 自编不动点仍成立（自身 3 个单元改名后，`ct-ast2` 逐字节复现 `ct-ast` 的产物）。
- 关卡：`check-ast.sh` → 290 passed；`check-warnings.sh` → 143 ok；
  `check-all.sh` → 9 hard gates green（含 `test/pkg` 与 `ct-tour`）。
