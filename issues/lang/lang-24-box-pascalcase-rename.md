# LANG-24 · `box<T>` → `Box<T>`（v1.0 规范拼写 + 别名，v1.1 删除 `box`）

| 项 | 值 |
| --- | --- |
| 模块 | lang / 内置类型命名 |
| 定性 | bug（违反 [§5.1](../../docs/language-spec.md#51-源码命名约定语言--标准库--ct-pkg稳定契约) 命名契约） |
| 严重度 | Medium（语言表面改名；涉及生成符号与文档） |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [language-spec §5.1](../../docs/language-spec.md#51-源码命名约定语言--标准库--ct-pkg稳定契约)、[§4.71](../../docs/language-spec.md#471-box--new单对象句柄phase-81仅-ct-ast)、[D-016](../../docs/decisions/D-016.md)、[Box.h.ct](../../lib/core/Box.h.ct#L34)、[Expr.h.ct:2304](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2304-L2311) |
| 状态 | verified |
| 处置证据 | **accepted（2026-11-23 所有者放开：v1.0 入口优先；容量约束已解除，Stage A 即刻推进，负责人 DEV）** |

## 背景

`box<T>` 是内置泛型 struct，不是关键字：

- `lib/std/Box.h.ct` 声明 `pub struct box<T>`（[Box.h.ct:34](../../lib/core/Box.h.ct#L34-L37)）；
- [§5.1](../../docs/language-spec.md#51-源码命名约定语言--标准库--ct-pkg稳定契约) 的适用范围明确含「内置类型、`lib/std` 内置层」，
  判据 2 要求类型名匹配 `^[A-Z][A-Za-z0-9]*$`；`box` 是唯一破例（`String` / `Str` /
  `U16String` / `Vec` / `Map` / `Option` / `Result` 全部 PascalCase）；
- 无任何决策记录把 `box` 登记为例外。D-016 只裁定布局、复制协议与边界，未提命名；
  单元文件名反而已经是 `Box.h.ct`；
- 小写成因是解析器的上下文规则：`box` 只有后接 `<…>` 才当类型，否则当标识符，以保住
  `Box box;` 一类变量名（[Expr.h.ct:2304](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2304-L2311)）。
  这让它按关键字族书写，但它的实现身份是类型，命名规范没有跟上。

## 决定

1. **规范拼写 `Box<T>`**（v1.0 / `v1-PH-0` 起）。类型声明、`new`、`Box<T>::of`、
   字段/参数/返回/嵌套容器一律用 `Box`。
2. **`box<T>` 保留为别名**：v1.0 起可用，但每次使用打印一次
   `warning: 'box<T>' is deprecated; write 'Box<T>'`；其余语义与 `Box<T>` 完全相同。
3. **v1.1（`v1-PH-1`）删除 `box<T>` 别名**：改为硬错并要求改写为 `Box<T>`。
4. **裸 `box` 始终是普通标识符**：`int box;`、`r.box`、形参 `box` 不受影响；
   `box` 不进入关键字表。改名后 `Box` 成为内建模板名，隐式保留（与 `Vec` 同级）。
5. **内部一律不再用 `box` 指代该句柄**（2026-11-21 所有者追加：不允许内部继续使用 `box`）：
   模板 `Box`、实例符号 `Box_*`、头结构 `ct_Box_hdr`、解析/发射/扫描中的
   `tok_is("box")` / `tmpl == "box"` / `src_has_box_type` 全部随改；活跃文档、示例、
   测试与编辑器同步，不留「源码 `Box`、产物 `box_`」的特例。
   唯一例外：`box_to_iface` / `maybe_box` 等指「接口装箱 / 装箱动作」的既有动词，
   以及 L0/L1/L2 冻结层——它们与 `box<T>` 句柄无关，改名会动冻结种子，不在本卡范围。

## 需要改的地方

| 位置 | 改动 |
| --- | --- |
| `lib/std/Box.h.ct` | 模板声明 `pub struct box<T>` → `pub struct Box<T>`；`impl<T> box<T>` 同步；头结构 `ct_box_hdr` → `ct_Box_hdr`；文件内注释同步 |
| `frontend/parse/Expr.h.ct` | 类型读取处的 `tok_is("box")` 改为 `Box`，并保留 `box` 别名分支（v1.1 删）；`ttmpl`/`inst_make("box", …)` 改用 `Box` |
| `frontend/parse/Stmt.h.ct` | `new` 路径的 `tok_is("box")` 同步 |
| `frontend/parse/Parser.h.ct` | `is_decl_start` 的裸 `box` 判据改为 `Box`（仍需「后接 `<`」）；别名拼写同判 |
| `backend/emit/Emitter.h.ct` | `strcmp(ins[i].tmpl, "box")`、`strncmp(base, "box_", 4)` 改为 `"Box"` / `"Box_"`；`box_type_owns` 一类指代句柄的助手名改为 `Box_*` 或 `handle_*` 概念名，不得继续以 `box` 指代该句柄 |
| `frontend/module/Module.h.ct` | `strncmp(t, "box_", 4)` 与源码词扫描同步；旧别名仍能触发内置层加载 |
| `tool/driver/Driver.h.ct` | `src_has_box_type` 改名（如 `src_has_Box_type` / `src_has_handle_type`），同时认 `Box<` 与 `box<`（v1.1 只认 `Box`） |
| `docs/language-spec.md` | §4.71 全部示例与正文改 `Box<T>`，加一句「`box<T>` 为 v1.0 弃用别名，v1.1 删除」；§5.1 不再有破例 |
| `docs/guide-for-c-programmers.md`、`tutorial.md`、`patterns.md`、`memory-guide.md`、`README.md` | 规范拼写改 `Box<T>`；保留一处旧拼写迁移说明 |
| `editors/vscode` | `ct-box-type` 规则同时匹配 `Box`/`box`；snippet 默认 `Box`；`check-grammar.py` 加新旧拼写夹具 |
| `test/ast/p81_box*` | 夹具改 `Box`，新增 `box` 别名正例（v1.0 警告）与 v1.1 负例；预期 C 符号改 `Box_*` |
| `docs/phases/v0-PH-81/card.md`、证据文本 | 作为历史记录保留旧拼写，加「命名已由 LANG-24 修正」注记；不重写历史证据 |

**文档范围**：`docs/**` 的活跃文档（spec、两本指南、tutorial、patterns、memory-guide、
README、std-catalog、planning、reviews 的结论行）全部改为 `Box<T>`，迁移说明只保留一处；
`docs/history/**`、历史 phase 卡与评审判决作为快照保留旧拼写并加注记，不重写。

## 容量与窗口约束

- **入口判据 1（2026-11-21 追加；2026-11-23 解除）**：`MAX_FUNCS` 固定 512 已由 [SH-109](../selfhost/sh109-max-funcs-capacity.md) 改为动态增长（当前 pre 窗口），
  本卡不再受 501/512 或 ≤11 预算限制；别名分支仍应复用既有 `tok_is` / 类型读取路径，不引入不必要的顶层函数。
- **v1.0（`v1-PH-0`）**：Stage A 作为独立提交，不混进 seed cutover；不再设 ≤11 预算，
  但仍复用既有 `tok_is` / 类型读取路径，不引入无关顶层函数。
- **v1.1（`v1-PH-1`）**：Stage B 删除别名与旧拼写扫描，属独立提交，可单提交回滚。
- 引入版本必须 ≤ v1.0：v1.1 删除的兼容窗口正好一个 MINOR，与 `lib/core`、`CharStr`
  的「旧名一个 MINOR」口径一致。

## 验收

- v1.0：`Box<Record> b = new Record { … };` 编译通过；`box<Record>` 编译通过并打印
  弃用 warning；`int box;`、`r.box`、`Box box;` 全部合法（无关键字冲突）；
- `--emit-c` 中出现 `Box_Record__new` / `Box_Record__payload_release`，不再出现 `box_Record`；
- v1.1：`box<T>` 报硬错并提示 `write 'Box<T>'`；同一程序改 `Box` 后通过；
- 全量 `check-ast`、`check-goldens`、`check-docs` 绿；编辑器 `check-grammar` 夹具覆盖两种拼写；
- 活跃文档不再出现 `box<T>` 作为推荐写法（迁移说明与历史记录除外）；
- **内部无残留**：`grep -rn 'box' selfhost/ct-ast lib/std` 命中的只能是 `box_to_iface` /
  `maybe_box` 等装箱动词或迁移注记，不得再有 `box<T>` 类型、`box_*` 实例符号、`ct_box_hdr`。

## 非目标

- 不改 `box<T>` 的布局、复制协议、Drop、借用视图与 C 边界（D-016 全部保持）；
- 不改 `box_to_iface` / `maybe_box` 等「装箱动作」内部机制名（与句柄无关，且 L0/L1/L2 冻结）；
- 不引入泛型类型别名语法（`type Box<T> = …`）；别名只存在于类型名解析层；
- 不借机改 `Vec` / `Map` / `Option` / `Result` 的任何拼写。

## 回滚

- Stage A：单提交回滚，恢复 `box<T>` 规范拼写；`Box<T>` 随之消失；
- Stage B：单提交回滚，恢复 `box<T>` 别名（仍为弃用态），不回退 Stage A。

## 处置（REV/REQ，2026-11-22）

**结论：`deferred`，不是 `rejected`。** 本条不是「决定不改」：2026-11-21 所有者已裁定规范拼写
改为 `Box<T>`，`box<T>` 作为弃用别名保留到 v1.1 删除；D-016 只裁定布局 / 复制协议 / C 边界，
命名由本条决定承接。落地窗口已在 [v1-release-plan](../../docs/planning/v1-release-plan.md) 钉死：

- `v1-PH-0` Stage A：规范拼写 `Box<T>` + `box<T>` 弃用告警（独立提交，不混入 seed cutover）；
- `v1-PH-1` Stage B：删除 `box<T>` 别名，改为硬错并提示 `write 'Box<T>'`。

当前 HEAD（`38cd4ae4`）仍是旧拼写，代码与文档均未开始 Stage A：

```console
$ grep -n 'pub struct box' lib/std/Box.h.ct
34:pub struct box<T> {
$ grep -rn 'pub struct Box' lib/std/ | wc -l
0
```

**入口判据（2026-11-23 起）**：`MAX_FUNCS` 固定 512 已由 [SH-109](../selfhost/sh109-max-funcs-capacity.md)
改为动态增长；本卡不再设“预计增量 ≤ 余量”或 ≤11 的预算。别名分支仍复用既有 `tok_is` /
类型读取路径，不引入无关顶层函数。

**触发/负责人/优先级**：`v1-PH-0`（Stage A）与 `v1-PH-1`（Stage B）；负责人 DEV，REQ 复核入口
判据；优先级为 v1.0 命名清理（Medium）。本批不实现，因为它是语言表面改名，必须与 seed cutover 一起排。

## DEV 复核（2026-11-23）：本窗口不实现

本条按卡片自己的窗口约束仍停在 `deferred`：`v1-PH-0` Stage A（规范拼写
`Box<T>` + `box<T>` 弃用别名）与 `v1-PH-1` Stage B（删除别名）都必须独立提交，
不得混入 seed cutover；容量约束已于 2026-11-23 解除（SH-109 动态增长，不再有
501/512 或 ≤11 预算）。当前工作树 HEAD 是 v0.88.3 pre 窗口，`lib/core/Box.h.ct:35`
仍是 `pub struct box<T>`；本批不实现 Stage A，以免在 seed cutover 前改动内建层拼写/发射符号。`status` 字段未动。

最小复现（当前 HEAD 自举的 ct-ast）：

```console
$ cat > /tmp/boxcap.ct <<'CT'
struct R { int x; }
int main(void) { Box<R> b = new R { 1 }; return b.x; }
CT
$ ct-ast /tmp/boxcap.ct -o /tmp/boxcap.c
/tmp/boxcap.ct:2:21: error: use of an undeclared variable
rc=1
$ grep -n 'pub struct box' lib/core/Box.h.ct
35:pub struct box<T> {
```

小写拼写仍可用（`box<R> ...` 编译通过）。落地时需同步：`lib/core/Box.h.ct`
模板/头结构/助手名、`frontend/parse/{Expr,Stmt,Parser}.h.ct` 的类型读取与别名
warning、`backend/emit/Emitter.h.ct` 的 `Box_*` 符号与 `ct_Box_hdr`、
`frontend/module/Module.h.ct` / `tool/driver/Driver.h.ct` 的判活扫描、p81/p82
夹具与活跃文档。

状态：**2026-11-23 所有者放开为 `open`**。容量约束已解除，Stage A 立即推进；
Stage B（删除 `box` 别名）仍按 v1.1。

## 复核（REV，2026-11-23）

Stage A 落地（主干 `282bd371`，红 `c1ab0795`）：规范拼写 `Box<T>`，`box<T>` 每次使用
warning `'box<T>' is deprecated; write 'Box<T>'`；`int box;`/`r.box`/`Box box;` 合法；
`--emit-c` 为 `Box_Record__new`/`Box_Record__payload_release`，无 `box_Record`/`ct_box_hdr`；
`p81_box: OK`、check-grammar 181/0、check-ast 1595/0。
Stage B（v1.1 删除别名、硬错）未做，按卡片窗口保留。
