# 提案 · 容器下标可写与嵌套下标链（`m[k] = v` / `v[i] = x` / `m["a"]["b"]`）

| 项 | 值 |
| --- | --- |
| 状态 | **提案（待研判）**；不排 phase 卡、不改 `selfhost/**` |
| 来源 | 负责人判定为必须补的能力缺口：Map / Vec 只能读不能写，JSON 写回无法完成（2026-11-15） |
| 拟占 | **PH-62**；吸收 PH-61（`v[] = x` 作为其中一个切片），不另立两个 phase |
| 关联 | [PH-61 追加下标](ct-append-subscript-proposal.md)、LANG-13（三级链）、PH-53（`?.` / `?[`）、`Vec::get/set/at`、`Map::get/put` |
| 定性 | **语法糖（B）**：`m[k]`/`v[i]` 就是 `get`，`m[k]=v` 就是 `put`，`v[i]=x` 就是 `set`；不另造容器语义。`set` 在下标不存在时的旧 no-op 是底层函数自身要改的行为，不是语法糖另加的分支 |

## 1 要解决什么

让下面这段真实 JSON 写回代码成立：

```ct
doc["server"]["host"] = "192.168.0.6";
```

今天同时踩两条：

1. `m["server"] = x` 被前端拒绝：`a Map subscript is read-only; use put(k, v)`；
2. `m["server"]["host"]` 被发成 `Map_get(&m, "server")["host"]`，C 编译器报
   `array subscript is not an integer`。

目标口径：下标读写全部按底层函数展开，逐层套用；唯一需要正面解决的是
`Vec::set` 在 `i >= len` 时静默 no-op——它会让 `v[i] = x` 这条糖失去意义。

## 2 现状与证据（HEAD `v0.53.1` 重建）

### 2.1 单层写被拒

```ct
Map<char *, int> m; m.h = 0; m["a"] = 1;
// b.ct:1:-3788: error: a Map subscript is read-only; use put(k, v)

Vec<int> v = {1, 2}; v[0] = 9;
// c.ct:1:-3796: error: a Vec subscript is read-only; use set(i, v)
```

### 2.2 嵌套朴素写/读发出坏 C

```ct
Map<char *, Map<char *, char *> > doc; doc.h = 0;
doc["server"]["host"] = "192.168.0.6";
```

```text
a.ct:14:57: error: array subscript is not an integer
    Map_char_p_Map__char__p__char__p_get(&doc, "server")["host"] = "192.168.0.6";
                                                        ^~~~~~~
```

读也一样：

```ct
char **p = doc["server"]["host"];
// d.ct:14:70: error: array subscript is not an integer
//   char * * p = Map_..._get(&doc, "server")["host"];
```

`ct` 自身返回 0，只有 `cc` 报错——属于「静默坏 C」，按 D-005 是可单独止血的 A 类子项。

### 2.3 `?[` 不能写

```ct
doc["server"]?["host"] = "x";
// e.ct:1:-3755: error: optional chain/subscript is not an lvalue; it cannot be assigned or address-taken
```

可选链只解决读，不解决写；它继续只读。

### 2.4 底层取值形态与唯一冲突

- `Vec<T>::get(int) -> T`：下标不存在（`i < 0` 或 `i >= len`）返回零值（D50-1）；
  `at(i) -> T*` 未命中返回 0；`set(i, v)` 当前在 `i >= len` 时 **静默 no-op**
  （[Vec.h.ct:97](../../lib/std/Vec.h.ct#L97)、[Vec.h.ct:121](../../lib/std/Vec.h.ct#L121)、
  [Vec.h.ct:132](../../lib/std/Vec.h.ct#L132)）。
- `Map<K,V>::get(K) -> V*`：缺键 0；`put(K,V)` 插入/覆盖；`char *` 键借用，`Str` 键深拷贝。

`m[k]` / `v[i]` 的读语义已经统一为「取不到就是空/零值」，**读侧不存在「越界」这个概念**。
唯一冲突是 `set` 在写侧不遵守同一模型：`v[5] = x` 而 `len == 2` 时静默不写。

嵌套写 `Map<char *, Vec<int> > m; m["a"][0] = 1;` 当前生成：

```c
Map_char_p_Vec__int_get(&m, "a")[0] = 1;
// error: assigning to 'struct Vec_int' from incompatible type 'int'
```

即 `Map_get` 返回的是 `Vec<int> *`，`[0]` 落到指针上得到 `Vec<int>` 值，不是 `int` 槽位。
嵌套物化必须按「Map 步取指针、Vec 步取槽指针」展开，不能照抄 C 的下标链。

## 3 定性

| 子项 | 定性 | 理由 |
| --- | --- | --- |
| `m[k]` / `v[i]` 读 | 既有 `get` 的糖 | 缺键/下标不存在 → 0 / 零值，没有「越界」 |
| `m[k] = v` | 既有 `put` 的糖 | 缺键插入、已有键覆盖；不新增语义 |
| `v[i] = x` | 既有 `set` 的糖 | 行为必须由 `set` 承担；`set` 要改成「补齐再写」 |
| 嵌套读 `m["a"]["b"]` | **A 子项**（可独立止血） | ct 放行、发出坏 C；完整修复在 PH-62 |
| 嵌套写 `m["a"]["b"] = v` | 语法糖 | 逐层按 get/put/set 展开；中间层按容器规则补齐 |
| `?[` 写 | 保持拒绝 | PH-53 明确可选链只读 |
| `v[] = x`（PH-61） | 语法糖，并入本 phase | 与可写下标共用语法/发射路径 |

## 4 候选与取舍

### 4.1 总体写法

| 方案 | 做法 | 优点 | 代价 / 风险 | 结论 |
| --- | --- | --- | --- | --- |
| **A 下标可写 + 嵌套链**（推荐） | `m[k] = v`、`v[i] = x`、`m["a"]["b"] = v` 统一按底层函数展开 | 满足 JSON 写回；读写形态对称；不改变读表达式类型 | 解析/类型检查/发射都要改；嵌套物化与所有权复杂 | **推荐** |
| B 只加方法/辅助函数 | 保留只读下标，新增 `Map::at` / `Vec::at` + `put`/`set` 组合 | 零语法风险 | `doc["server"]["host"] = ...` 仍写不出来 | 兜底 |
| C 把下标读改成真 lvalue | `m[k]` 读类型从 `V*` 改为 `V`，`v[i]` 为 `T` 左值 | C 式写法自然 | 破坏 `*m["a"]`、`m["a"] == 0`、`get` 指针契约 | 不采纳 |

### 4.2 `set` 在下标不存在时的语义（唯一冲突）

| 方案 | 语义 | 取舍 |
| --- | --- | --- |
| **S1 补齐再写**（负责人已拍板） | `i >= len` 时先补到 `len = i + 1`，`[old_len, i)` 填零值，再把 `x` 写到 `v[i]`；`len = max(len, i+1)` | 与 `get` 的「取不到是零值」同一模型；`v[5]=x` 后 `len == 6`；洞是零值元素，不是未定义 |
| S2 保持 no-op | 静默不写 | 糖失去意义；负责人明确要改 | 不采纳 |
| S3 硬错 / abort | 下标不存在就报错 | 重新引入「越界」概念，与读侧零值模型冲突 | 不采纳 |

**显式条款（写死）**：对 `i >= 0`，

```text
v[i] = x   ⇒   len' = max(len, i + 1)
```

- `i >= len`：补齐到 `i + 1`；`[len, i)` 的中间位置是**零值元素**；`i` 位写 `x`。
- `i < len`：只覆盖，`len` 不变。
- 同一位置连续写：`v[5]=a; v[5]=b;` → `len` 仍 6，`v[5]` 为 `b`。
- 往回写：`v[1]=c` → `len` 不变。
- 空 Vec：`v[0]=d` → `len == 1`。
- 中间洞：读出来是零值，`has(i)` 为真——它确实是元素，不是缺失。

`i < 0` **报错**（负责人裁定，仅写路径）：

- 编译期能算出的负数（字面量、常量折叠结果）→ 直接编译错误，文案说明「下标不能为负」
  并给出位置；不落 `.c`。
- 运行期才得到的负数 → `abort`，消息带上下标值与容器长度，与其它运行期硬错同形态。
- 不退化为 no-op，也不「不写但继续」；`len` 不变、不分配。
- 读路径 `v[-1]` 仍是 `get` 的糖，返回零值，不报错；本裁定只约束写。

### 4.3 嵌套读的缺席语义

| 方案 | 语义 | 取舍 |
| --- | --- | --- |
| **R1 零值传播**（推荐） | 任一层缺键/下标不存在 → 最终结果为零值（`V*` 为 0）；不崩溃 | 与单层 `Map::get` / `Vec::get` 一致 |
| R2 硬错 | 任一层缺失 → abort，提示用 `?[` | 与单层读返回零值不一致 |
| R3 读时自动创建 | 缺键就建空 Map | 读操作产生副作用，拒绝 |

推荐 **R1**：嵌套读只是把既有的「取不到 → 零值」传播到链上；写才补齐。

### 4.4 嵌套写的中间缺失

| 方案 | 语义 | 取舍 |
| --- | --- | --- |
| **W1 按容器规则补齐**（推荐） | 中间是 `Map` 且缺键 → 建空 Map、`put` 进上层；中间是 `Vec` 且下标不存在 → 按 `set` 的补齐规则扩到 `i+1`（洞为零值），继续写 | 与 `m[k]=v` / `v[i]=x` 的糖语义完全一致；`doc["server"]["host"]`、`vv[2][0]` 都成立 |
| W2 硬错 | 中间缺失 → abort，要求先显式建 | 与糖语义不一致，且 JSON 写回样板多 |
| W3 只自动建 Map、Vec 仍 abort | 两套缺失规则 | 与「`set` 补齐再写」冲突；不采纳 |

推荐 **W1**：`Map` 建空、`Vec` 按 `set` 补零；两者都是各自底层函数的既有/修正后行为。

## 5 推荐语义（组合后）

### 5.1 展开规则

| 写法 | 展开 |
| --- | --- |
| `m[k]`（读） | `Map_get(&m, k)`；缺键 0 |
| `v[i]`（读） | `Vec_get(&v, i)`；下标不存在零值 |
| `m[k] = v` | `Map_put(&m, k, v)` |
| `v[i] = x` | `Vec_set(&v, i, x)`；`set` 负责补齐 |
| `m["a"]["b"] = v` | 逐层：`Map_get` 得到内层 `Map*`，缺键建空 Map，最终 `Map_put` |
| `v[i][j] = x` | 逐层：外层 `set` 补齐到 `i+1`，取槽指针，内层 `set` 补齐到 `j+1` |
| `m["a"][i] = x` | `Map_get` 得到 `Vec*`（缺键建空 Vec），内层 `Vec_set` |

### 5.2 语句形态与 lvalue

- 写形态都是**语句级赋值**，返回 `void`；不能出现在表达式里，不能取地址，不做 `+=` / `++`。
- Map 写就是创建：缺键正常插入，不要求先有值；`put` 返回 0 只有分配失败（abort）或 NULL 键（常量编译错误 / 运行期 abort）两种失败。
- `m[k]` 的**读**类型仍是 `V*`；`v[i]` 的读类型仍是 `T`。既有 `*m["a"]`、`v[0]` 不变。
- `&m["a"]`、`m["a"] += 1`、`v[0] += 1`、`(m["a"] = 1) + 1` 全部硬错。
- RHS 按普通表达式类型求值，**不做隐式解引用**：`m["a"] = m["b"]` 不成立（`m["b"]` 是 `V*`），
  要复制值写 `*m["b"]`；`v[0] = v[1]` 是值拷贝。
- `?[` / `?.` 仍只读；赋值报既有的 `optional chain/subscript is not an lvalue`。

### 5.3 `Vec::set` 的补齐算法（底层先改）

```c
/* 写路径：i < 0 → 编译期常量报错 / 运行期 abort；i >= 0 → len = max(len, i+1) */
if (i < 0) {
    fprintf(stderr, "Vec: negative subscript %d (len %d)\n", i, len);
    abort();
}
if (h == 0) allocate header;
if (i >= len) {
    ensure capacity >= i + 1;      /* 现有翻倍规则 */
    memset(data + len, 0, (i - len) * sizeof(T));
    len = i + 1;
}
retain(&x);
release(&data[i]);
data[i] = x;
/* malloc(header) 失败 → abort("Vec: set: header allocation failed (len %d)") */
/* realloc(data) 失败 → abort("Vec: set: growth allocation failed (requested cap %d, len %d)") */
```

- 常量负下标在类型检查阶段直接报错（文案含「下标不能为负」，带位置），不进入运行期检查；
  动态负下标走上面的运行时 abort；两者都不得退化为 no-op。
- `len` 唯一由 `max(len, i+1)` 推进；不存在第二种长度来源。
- 容量按现有 `push` 的翻倍规则；中间洞占内存，不引入 bitmap / 稀疏表示。
- 洞是**零值元素**，不是未定义内存：`get` 读零值，`has(i)` 为真，`at(i)` 返回该槽指针，
  `foreach` 会访问到它。
- 洞跳过只在 `__ct_elem_release` 做一次：`Vec`/`Map` 判 `h==0`，`Str` 判 `data==0`；值类型直接释放，
  **不做全零判断**；自持结构按字段生成谓词；`Vec.release`/`Map.release` 只调入口。
- 补齐跨度 > `CT_VEC_GROW_WARN_SPAN`（默认 1024，可 `-D` 覆盖，**非语义契约**）时警告：常量可判编译期给，
  否则 `set` 运行时 stderr；继续执行，不 abort/拒绝/截断；分配失败仍 abort。
- `set` 签名仍为 `void`；分配失败 abort，消息区分 header / growth，带 requested cap 与 len，不改成返回状态。

### 5.4 物化与所有权

- Map 步：`V *p = Map_get(parent, k)`；读时 `p == 0` → 零值；写时缺键建空 Map 后重取。
  Vec 步：读用 `Vec_get`；写先用 `set` 补齐保证 `i` 存在，再 `Vec_at` 取槽指针。
- 嵌套写必须用槽指针（`Vec_at` / `Map_get`），不能用值拷贝，否则会写副本。
- 求值顺序：先算 RHS，再逐层补齐并写入；自动创建的 Map 临时句柄在写入后 `release`。
- `Map<char *, V>` 键仍借用；`Map<Str, V>` 键由 `put` 深拷贝。
- `Vec<T>` 元素按 `set` 的 retain/release 规则；洞跳过 release。
- 嵌套写 `m["a"]["b"] = m["x"]["y"]` 这类别名场景：先读完 RHS，再开始写入。

## 6 代价与风险

| 项 | 估计 |
| --- | --- |
| 实现 | 解析器 + 类型检查 + 代码生成（Map/Vec 物化、补齐、临时句柄 release、诊断），约 **M–L** |
| `Vec::set` | 补齐 + 零填充 + 洞释放跳过，约 **S–M** |
| 测试 | 正例 10 + 负例 6 + ASan/引用计数夹具 + golden，约 **M** |
| 风险 1 | **既有 `set` 越界调用改义**（`test/ast/142` 依赖 no-op，需改夹具）；洞释放若不走统一入口会 abort |
| 风险 2 | 巨大下标（`v[1000000]=x`）按语义分配大量零值内存 → 只给 warning，不设硬上限 |
| 风险 3 | 物化用错（`get` vs `at`）导致改副本 / 类型错 → 用 `m["a"][0] = 1` 夹住 |
| 风险 4 | 自动创建中间 Map 的临时句柄泄漏 → ASan 夹具；位置诊断已有负数行号（`1:-3788`）→ 建议单独 patch |

## 7 非目标

- 不做 `+=` / `++`、稀疏表示 / bitmap（洞就是零值元素）、`insert` / `remove` / `resize`；
- 不改 `Map::get -> V*`、`Vec::get -> T`、`put` / `set` 的签名；
- 不做 `Map` 点访问、`?.` / `?[` 改写、`Vec` 元素 struct 字段写、JSON 专用语义。

## 8 ABI / 兼容性

- **零 ABI**：降级为既有 `Map_get` / `Map_put` / `Vec_get` / `Vec_set` / `Vec_at` 调用；
  辅助函数只进生成的 `.c`（`static`），不改 `.h` / `.abi.h`。
- **`set` 行为变更**：`set` 签名不变；`i >= len` 从 no-op 改为补齐再写。有效下标调用不变；
  仓库内唯一依赖 no-op 的夹具是 `test/ast/142_vec_api`（`v.set(9, 1)` 后断言 `len == 2`），
  必须同步改为 `len == 10` 并补洞断言；该夹具后续的 `shared` / `clear` 断言也会随 `len`
  变化，需一并更新；外部调用者若依赖 no-op 会改义，需在 release notes 写明。
- `get` 读语义、`m[k]` / `v[i]` 读类型不变；`*m["a"]` 等既有写法不变；洞的 `has(i)` 为真，
  `foreach` 会访问；与 D50-1 的「取不到零值」一致，但 `has` 语义需在文档写明。需一条 D 记录
  废止 `set` 的 no-op 契约；`lib/std/Vec.h.ct` 注释、`language-spec` §4.51 同步更新。

## 9 验收判据草案

| ID | 判据 |
| --- | --- |
| W1 | `Map<char*,int> m; m["a"]=1;` → `*m["a"]==1`；重复写覆盖；缺键插入 |
| W2 | `Vec<int> v={1,2}; v[0]=9;` → `v[0]==9`，`len==2` |
| W3 | `v[5]=9`（len=2）→ `len==6`；`v[2]==v[3]==v[4]==0`；`v[5]==9` |
| W4 | `v[5]=a; v[5]=b;` → `len==6`，`v[5]==b` |
| W5 | `v[1]=c`（len=6）→ `len==6`，`v[1]==c` |
| W6 | 空 Vec `v[0]=d` → `len==1`，`v[0]==d` |
| W7 | 洞位 `get` 读零值、`has(i)==1`、`at(i)!=0`、`foreach` 访问到 |
| W8 | `doc["server"]["host"]="192.168.0.6";` → 中间 Map 自动创建，`*doc["server"]["host"]` 为原串 |
| W9 | `Vec<Vec<int>> vv; vv[2][0]=1;` → 外层 `len==3`，`vv[0]`/`vv[1]` 为零值洞，内层 `len==1` |
| W10 | `Map<char*,Vec<int>> m; m["a"][0]=1;` → 缺键建空 Vec，`Vec_set` 后 `len==1`；不出现 `struct Vec_int` 赋值错误 |
| W11 | 嵌套读缺键/下标不存在 → 零值（R1），不崩溃 |
| W12 | `?[` / `?.` 赋值仍报 `optional chain/subscript is not an lvalue` |
| W13 | `m["a"]` 读仍为 `V*`，`v[0]` 读仍为 `T`；`&m["a"]`、`m["a"]+=1`、`v[0]+=1` 硬错 |
| W14 | `test/ast/142_vec_api` 更新后通过：`set(9,1)` 后 `len==10`、`get(9)==1`；其余有效下标 `set` 行为不变 |
| W15 | `Vec<Vec<int>>` 带洞释放不 abort、无泄漏（ASan/引用计数夹具） |
| W16 | 无新语法程序 `.c` / `.h` / `.abi.h` 零变化（golden） |
| W17 | 负下标（写）：常量 `v[-1]=x` → 编译错误（说明「下标不能为负」并带位置，不落 `.c`）；动态 `i=-1` → abort，消息含 `-1` 与 `len`；读 `v[-1]` 仍零值 |
| W18 | `m["new"]=1` 缺键正常创建；`has` 为真、`*m["new"]==1`；不得要求目标先存在 |
| W19 | NULL 键：常量 `m[(char *)0]=1` → 编译错误（说明键为空 + 位置，不落 `.c`）；动态 `char *k=0; m[k]=1;` → abort，消息含 NULL key；都不得插入 |
| W20 | 分配失败有夹具/注入方式：测试分配器在 header / growth / put 处返回 0，断言 abort 且消息含 requested cap 与 len；不只靠代码评审 |
| W21 | 生成代码检查：值类型 helper（如 `Vec_int__elem_release`）无零值判断；句柄 helper（如 `Vec_Vec_int__elem_release`）恰有一处 `if (e->h == 0) return;`；所有容器 `release` 只调 `<inst>__elem_release`，无第二处零值/memcmp 跳过 |
| W22 | 大下标写入：常量与运行期各一，`v[5000]=7` 写入且 `len==5001`、洞为零；warning 出现（常量编译期 / 运行期 stderr）；调阈值后结果与 stdout 不变 |

## 10 排位与 PH-61 的关系

- **拟占 PH-62**，接替 PH-61 的排位；PH-61 的 `v[] = x` 作为 PH-62 的 **S1 切片**，
  不再单独占号。理由：PH-61 的非目标（不放开 `v[i] = x`）与本需求直接冲突，若先发 PH-61
  再改同一处语法/发射，会产生返工和自相矛盾的中间态；PH-61 的「仅 Vec、语句级、失败即 abort」保留。
- 依赖：无语言依赖；与 PH-53 / PH-59 / PH-60 无依赖；改 `Expr` / TypeCheck / Emitter / `Vec::set`，与 TypeCheck/Expr 族**串行**。
  切片：S0 读物化 + 诊断；S1 `v[]=x`；S2 `set` 补齐 + 洞释放；S3 单层写；S4 嵌套读/写；S5 所有权/ASan/golden。
- `set` 必须先改，否则 `v[i]=x` 展开没有意义（负责人口径）；本轮只到提案 + 研判，
  不排 phase 卡；嵌套读的止血补丁可另开 patch。

## 11 开放问题（需拍板，按原顺序）

1. 是否顺手修 `1:-3788` 负行号诊断（建议单独 patch）。
