# I2 实施契约 · 接口值下标（DEV 落笔，2026-11-28）

> 中文。本文件是 I2（`D-034` / `I2-C1`）实现的**唯一契约**：实现形状、诊断落点、
> 夹具命名与偏差。语义权威仍是 [D-034](../decisions/D-034.md)；本文件只记录“代码
> 在哪、怎么改写、报在哪”。四片提交：`I2-1` `9b3e2034`+`cf7e0c5d`、`I2-2`
> `43bf79a0`+`e9ab4bbe`、`I2-3` `8e164c4b`+`deff490b`、`I2-4` `3f59ad63`+`f792da01`。

## 1 `index` 存哪

- `frontend/sym/Symbols.h.ct`：`struct MethodSig` 增 `int is_index`（与 `is_mut`
  同域）。只由动态 trait / `pub trait` 的声明置位；`.m.ct` 静态 map trait 不识别，
  也不置位。泛型 trait 的实例行按既有的 `MethodSig` 值拷贝带走该位。
- vtable 槽数、槽序、槽偏移不变：`is_index` 是编译期属性，不是槽。
- 解析入口：`frontend/parse/Parser.h.ct` 的 `parse_trait()`；标记识别点在
  `)`（及 `.m.ct` 的 `mut`）之后、`{`/`;` 之前，辅助函数 `trait_index_marker()`。
  前缀写 / 写在 `;` 后由成员循环入口检查；impl 侧（`parse_impl` /
  `parse_impl_inst`，含 `.h.ct` 与模板 impl）在签名前后各查一次。

## 2 `o[k]` 的改写形态

- 解析点：`frontend/parse/Expr.h.ct` 的 `parse_postfix()` `[` 分支，**在 D-028 的
  固有 struct 分支之前**判 `is_iface_type_text(bty, &trname)`（`bty` = `struct T_iface`）。
- 读：`o[k]` → 与显式 `o.get(k)` **同形**的 `N_MCALL`：`aux = 3`（接口值 vtable
  调用）、`text = trname`、`text2 = "get"`、`a = 接收者`、`b = 键`、`line/num = [` 位置；
  `suffix` = 选中槽的 `$…` 尾（唯一名为空）。TIR/LIR/发射器零新增分支。
- 写：语句 `o[k] = v` 在解析期**不解析 `get`**（`wop` 时跳过读探针），交给
  `frontend/parse/Stmt.h.ct` 的语句 `=` 分支；该层调 `iface_index_method(… "set",
  want=2, writable=1, call_node=e)`，成功则把 `rhs` 接到键节点 `next`、`text2 = "set"`、
  包 `N_EXPR`。值位置赋值、`+=`、`++`/`--`、`&o[k]` 保持 L52-8 / L52-6 / L52-7。
- 具体类型分流：`ExprStaticType.h.ct :: container_subscript_kind` 对 aux=3 的下标糖
  返回 **4**（3 是 D-028 固有下标），写/取址检查按 4 分派；D-028 分支不改。

## 3 诊断落点与顺序

`frontend/parse/ExprSubscript.h.ct :: iface_index_method()` 一次只报一条，位置一律
`[`（`line/col` 由调用方传入）：

1. 该名字没有任何 `is_index` 方法 → D034-1（读）/ D034-8（写）；
2. 有 indexed 但参数个数不符 → L52-4 文案（`type '<trait>' has no [writable] subscript: …`）；
3. 键静态类型推不出 → L52-3 / D028-3 文案；
4. 键 `type_key` 无匹配 → D034-2（候选 = 参数个数相符的 indexed 键类型，按声明顺序，
   单引号逗号空格；写侧 `'get'`→`'set'`）；
5. 同键命中 >1 → D034-5（声明期检查正常已拦，兜底用同一文案）。

声明期（`Parser.h.ct`）：D034-7 指 `index` 记号；D034-3 指 impl 的 `index` 记号；
D034-6 指 `set` 记号；D034-5 指**第二个**标记。D034-4（阶段一只读）由 I2-4 撤除，
v1.2 最终产物不再出现；阶段一探针的两条 `=`/`++` 断言随 I2-4 改口径（见 §5）。

**同键重复的展示**：重复判定用 `type_key`，D034-5 文案引用**声明拼写**（`'char *'`），
与 D-034 §2 的冻结样例一致（该节小字“按 type_key 展示”按“判定用 type_key”读）。

## 4 多键分派与槽名（I2-3）

- `frontend/parse/ExprTypeText.h.ct`：`ct_trait_slot_text(ti, mi)` /
  `ct_trait_slot_suffix(ti, mi)` / `ct_trait_impl_slot_text(ti, arena, mnode)`。
  唯一名返回裸方法名（既有产物逐字节不变）；同名 ≥2 时**每个**同名槽追加
  `$<enc(参数类型键)>`（`get$char_2a` / `get$int`，与 D-028 固有重载同一编码）。
- impl 侧按 **名字 + 参数类型键** 选 trait 行（与声明顺序无关），parser 记在
  `N_METHOD.d`（trait impl 原本不用该字段）；发射器据此拼
  `<Struct>_<Trait>_<slot>`（vtable 结构体、初始化器、默认体、模板实例、`.h.ct`
  公开头、TIR seam/cname 同步）。显式 `o.get(k)` 仍按 D-028 取第一个同名方法。
- 不新增槽、不改槽位布局；接口库仍源码分发（D-034 D9/D10）。

## 5 夹具与探针命名

| 类别 | 名称 |
| --- | --- |
| 正例 | `test/ast/i2_index_ident`（`index` 标识符）、`i2_index_read` / `i2_index_explicit`（A1 逐字节对）、`i2_index_read_keys`（A2 双键）、`i2_cross_unit`（`store.h.ct` + `mem.h.ct` + `prog.ct`，A3）、`i2_index_write` / `i2_index_write_explicit`（B1） |
| 负例 | `test/ast/errors/i2_index_{prefix,twice,after_semi,dup,set_nonvoid}`、`i2_impl_index`、`i2_no_index`、`i2_key_mismatch`、`i2_non_iface`、`i2_struct_key_mismatch`、`i2_no_index_set`、`i2_set_key_mismatch`、`i2_write_own`、`i2_write_compound`、`i2_write_incr` |
| 探针 | `test/ast/i2_index_syntax.sh`（I2-1）、`i2_index.sh`（I2-2/3，A1–A9）、`i2_index_write.sh`（I2-4，B1–B4）；三者挂在 `selfhost/check-ast.sh` 的 `i2/syntax`、`i2/index`、`i2/write` |

## 6 已知偏差与边界

- **重复名槽位改写**：D-034 §1 只写“不新增槽、槽数/序/偏移不变”，未规定同名槽的
  拼写。实现按“同名 ≥2 才加 `$…`”，因此既有唯一名 trait 的生成 C 逐字节不变；
  不加后缀的旧行为对同名 trait 会产出重复 C 成员（不可编译），故不构成回归。
- **B4 的“借用检查 / ASAN”**：以 L52-9（`own` / `borrow` 右值拒绝）与 L52-6（复合写）
  两条负例覆盖；未单列 ASAN 用例（无新增分配路径，写形态与显式调用同字节）。
- **阶段一产物稳定（B5）**：以 I2-3 编译器与 I2-4 编译器对 A1–A3 夹具的生成 C 逐字节
  对比证明，不放进探针（探针只拿一个二进制）。
- `examples/`、spec / glossary / tutorial / matrix 归 REQ（I2-5），DEV 不提交；
  `test/probes/p85_corpus_sha.tsv` 仅在新增 example 时重生成。
