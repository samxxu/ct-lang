# 对《提案二：致 JSON 包（ct-json）项目组》的评审意见

> **评审对象**：DeepSeek 撰写的《提案二：致 JSON 包（ct-json）项目组》（提交方：Agent 内核 + Rill DSL 项目）。
> 只评「致 JSON 组」这一部分；提案一（致 CT 语言组）只在 J3/J4 的依赖处引用，不在此重评。
>
> **评审基线**：CT `v0.44.1`（tag `13db6cad`，二进制 `~/.local/bin/ct`），仓库 `b5797cbf`。
> `docs/proposals/ct-json-capability-blockers.md`（下称 **blockers**）与
> `docs/proposals/language-capability-gaps.md`（下称 **gaps**）为事实基线。
> 本文所有「当前行为」都是在新环境 `/tmp/ctgap2` 上**重新跑过**的，没有引用旧结论；探针清单见 §10。
>
> **给谁看**：提案方（用于修订提案）、ct-json 包组（用于判断 J1/J2 能否开工）。
> **不涉及**：不改 `DECISIONS.md`、`README.md`、ct-json 仓库里既有的三份评审。

---

## 0 结论先行

**方向可用，细节不可执行。**

分层（数据结构 → 访问 → 内存 → 错误 → 分阶段）是对的，`JsonRef` 统一 `Map`/`Vec` 元素类型的
思路也成立；但按原文照抄的 struct **无法编译**（两处语法错误），J1 的对象节点写法在 `ct build`
下**必炸**（生成头 `field has incomplete type`），J3/J4 的验收例在语言层**根本写不出来**
（下标结果不能作接收者；`?.` 是字段访问，而 JSON key 不是字段），J5 的 errdefer 清理**不会触发**
（errdefer 只在错误出口执行，`return 0` 不算）。

按本文 §8 的最小修订（具名 union、写全类型实参、元素改指针、导出 `json_free`、`json_obj`
返回句柄副本）可以**立即交付 J1/J2**；J3 除 L1 外还要改「临时接收者」规则；J4 需要把 `?.`
重新定义成 key 访问，或改成 `?[...]`；J5 需按 `defer + 成功标志` 或 `err:` 出口重写。

| 阶段 | 提案判定 | 评审判定 | 一句话 |
| --- | --- | --- | --- |
| J1 | 无依赖，可立即开工 | **需改后可开工** | 数据结构要改 3 处，否则 build 模式不编译 |
| J2 | 无依赖，可立即开工 | **可开工** | `json_get` / `json_set` 可行；`foreach` 需返回句柄副本 |
| J3 | 等 L1 | **不成立** | `v["server"]["port"]` 即使 L1 落地也编译不过（SH-73） |
| J4 | 等 `?.` | **不成立** | `data?.server` 是字段访问，JSON key 不是字段 |
| J5 | 等 errdefer（称已落地） | **需重设计** | errdefer 已落地，但语义与「返回 0 表失败」不兼容 |

---

## 1 核对口径

- **基线**：`v0.44.1` 的发布二进制。HEAD 上的四项修复（A-1、SH-72、SH-74、SH-75）本文不依赖；
  凡涉及处按 blockers/gaps 的既有标注引用。
- **环境**：把 `ct` 复制到 `/tmp/ctgap2/bin`，`CT_STD_DIR=<repo>/lib/std`。不设该变量时泛型声明会被
  误解析（blockers §5.3），所以全部探针固定该变量。
- **证据分级**：未标注 = 本次实测（命令与原文在 §10）；标 **来源：X** = 引用提交/夹具/规约原文。
- **判定用词**：**阻断**（照原文做会编译失败、语义不成立或验收无法通过）；**需改**（能落地，但
  API/实现要变）；**描述**（不影响能否落地，但会误导排期或评审）。

---

## 2 与 blockers / gaps 的冲突清单

共 **13 条**：7 条阻断、3 条需改、3 条描述/论证。

| # | 提案说法（定位） | 本次实测 | 等级 |
| --- | --- | --- | --- |
| C1 | §1 struct 里写裸 `Map *obj` / `Vec *arr` | `generic struct 'Map' needs type arguments in a type position`，rc=1 | **阻断** |
| C2 | §1 写 `union { … } v;`（匿名 union 带字段名） | `an anonymous record member cannot have a name; tag the record instead`，rc=1 | **阻断** |
| C3 | §4「J1 无依赖、可立即开工」，对象用 `Map<char*, JsonRef>` | `ct build` 下 `.ctbuild/Vec.h:32: field has incomplete type 'struct JsonRef'`，rc=1 | **阻断** |
| C4 | §2.1「`v["server"]["port"]` 展开为 `v.get("server").get("port")`」 | `method receiver must be a variable, an element, a call or a field chain`，rc=1 | **阻断** |
| C5 | §2.2「`data?.server?.port`」 | `?.` 展开是字段访问（提案一 §2 自述 `a?.b → a ? a->b : 0`）；JSON key 不是 struct 字段，写不出来 | **阻断** |
| C6 | §2.5 `Map *json_as_obj(...)` + §2.6 `foreach (obj)` | 返回类型裸泛型报错；`foreach` 收 `Map *` 报 `'mp' is not iterable` | **阻断** |
| C7 | §3.1 / §5「失败返回 0，errdefer 释放中间对象」 | errdefer 只在 `return err` 等错误出口执行；普通 `return 0` 丢弃 errdefer（实测 flag 保持 0） | **阻断** |
| C8 | §3.2「`Vec<char>` 做 builder，末尾 `push(0)` 补 NUL」 | `Vec` 没有 `data`/`c_str`；`v.data` 报 `no member named 'data'`；`push(0)` 也不会产生 `char *` | 需改 |
| C9 | §「不需要语言动的项」称「泛型 trait 未实现」 | `trait Show<T>` + `use Show<int>` + `impl Show<int> for A` 编译通过（Phase 35 已完成） | 描述（过时） |
| C10 | §3.3「JsonValue 树用 own + Drop，调用方 `delete`」 | 跨单元 `delete` 调的是消费单元的空桩，定义单元的 Drop 体不执行（只打印 `done`） | 需改 |
| C11 | §5 反问「JsonValue 作 Map 的 key」 | `Map does not support key type 'struct JsonValue' (use int, long or char *)`，rc=1 | 需改（需语言侧改） |
| C12 | §5 反问「JsonValue 的 `==` 重载」 | `ct` 放行，`cc` 报 `invalid operands to binary expression ('struct P' and 'struct P')` | 描述（需语言侧） |
| C13 | §1「JsonRef 包一层……解引用一次拿到 p」作为主要理由 | `Map<char*, JsonValue*>` 的 `get` 确实是 `JsonValue**`；但 `JsonRef { JsonValue *p; }` 同样要一次解引用，且每个节点多一次堆分配 | 描述（论证不成立） |

**7 条阻断**集中在两处：数据结构（C1/C2/C3）与访问语义（C4/C5/C6/C7）。下面按 §3–§5 展开。

---

## 3 数据结构判定

### 3.1 逐项核对

| 命题 | 结论 | 证据 |
| --- | --- | --- |
| 裸 `Map *` / `Vec *` 能放在 struct 里 | **不能** | §10 `v1_proposed_struct` |
| `union { … } v;` 能写 | **不能**（必须给 union 起名） | §10 `c1_anon_union` |
| `JsonValue` 与 `JsonRef` 互相引用，声明顺序如何 | **JsonRef 先声明**，成员写 `struct JsonValue *p;` 即可（C 的前向可见性）；反过来先声明 JsonValue、union 里写 `struct JsonRef *` 也可以，但 JsonRef 的定义必须在**使用其字段**之前 | §10 `v2_corrected`（单文件通过） |
| union 里放 `Map<…> *` / `Vec<…> *` | **可以**，访问写成 `self->v.obj`；但**不能**把 union 成员直接作方法接收者（`json.v.obj->get(...)` 报 `cannot resolve the method trait`），要先落到局部 | §10 `v2_corrected`、`v4_union_receiver` |
| `Map<char *, JsonRef>`（元素是用户 struct 值）进 `ct build` | **不能**：`.ctbuild/Vec.h` 的 `MapEntry` 按值声明 `struct JsonRef value;`，该处只有前向声明 | §10 `b1`（J1 原样） |
| 元素改指针 `Map<char *, JsonRef *>` | **可以**：单文件与 `ct build` 都通过 | §10 `b14` |
| `Map.get` 返回几层 | `V = JsonValue*` → `JsonValue**`；`V = JsonRef*` → `JsonRef**`；`V = JsonRef` → `JsonRef*` | §10 `b9`、`b14` |
| `Vec<JsonRef>` 的元素访问 | `get(i)` 返回 `JsonRef`（值），不是指针；要指针就用 `Vec<JsonRef *>`，此时 `get` 返回 `JsonRef *` | gaps C-2、§10 `b14` |

### 3.2 `JsonRef` 那一层的理由要重写

提案的理由是「`Map.get` 返回 `V*`，`V` 是 `JsonValue*` 时得到 `JsonValue**`，多一层；包一层后
解引用一次拿到 `p`」。核下来：

- **层数并没有减少**：`(*slot)` 与 `r->p` 都是一次解引用；
- 真正的差别是**元素布局**：`Map<char *, JsonRef>` 把 `JsonRef` 内联进条目；若 `JsonRef` 里
  内联 `JsonValue`（`struct JsonRef { struct JsonValue v; }`），则每个节点**零额外分配**（实测
  `sizeof=16`，`b15`）；而提案写的 `JsonValue *p` 是**指针**，每个节点仍要单独 `malloc` 一次，
  等于「多一次分配 + 一次解引用」，比直接用 `Map<char *, JsonValue *>` 更差。

所以 `JsonRef` 设计要二选一：

1. **内联**（推荐，若不用 build 模式的 Map 值元素）：`struct JsonRef { struct JsonValue v; }`
   —— 元素零额外分配，但 `Map<char *, JsonRef>` 在 `ct build` 下不可编译（C3）。
2. **指针**（build 模式的可行解）：`struct JsonRef { struct JsonValue *p; }` + `Map<char *, JsonRef *>`
   —— 每个节点一次分配，`get` 返回 `JsonRef**`。此时「包一层」的收益只剩**统一元素类型**，
   不再省分配——理由要照实写。

### 3.3 能编译的最小形态（单文件与 build 都过）

```c
struct JsonRef {
    struct JsonValue *p;          /* JsonValue 尚未定义，用指针前向引用 */
}

union JsonPayload {               /* C2：union 必须有名字 */
    int    b;
    double n;
    char  *s;
    Map<char *, struct JsonRef *> *obj;   /* C1：写全实参；C3：元素用指针 */
    Vec<struct JsonRef *>         *arr;
}

pub struct JsonValue {
    int tag;                      /* 0 null, 1 bool, 2 num, 3 str, 4 obj, 5 arr */
    union JsonPayload v;
}
```

注意 `pub struct`：`JsonValue::get` 若要跨单元 `pub`，宿主必须是 `pub struct`，否则
`.h.ct` 报 `a pub method needs a pub struct in a .h.ct unit`（§10 `b5` 的第一版）。

---

## 4 API 逐条判定

| # | API / 用法 | 判定 | 理由与改法 |
| --- | --- | --- | --- |
| A1 | `get(char *key) → JsonValue*` | **采纳** | 与 `Map::get` 的 NULL 契约一致；把「缺键 = NULL、值为 null = TAG_NULL」写进头注释 |
| A2 | `get_idx(int i) → JsonValue*` | **采纳** | 与提案一的方案 A 自洽（`[]` 只绑一个 `get`）；越界返回 NULL |
| A3 | `type()` / `is_null()` | **采纳** | 名字建议 `json_type` 前缀或 `json_tag`，避免与 C++ 关键字观感冲突（非阻断） |
| A4 | `v["server"]` 单层 | **有条件采纳** | 依赖 L1；落地后展开为 `v.get("server")`。注意 `v` 是值还是指针要先定（`impl` 的 `self` 都是指针） |
| A5 | `v["server"]["port"]` | **驳回** | 实测 `root.get("a")->get("b")` 直接报 `method receiver must be a variable, an element, a call or a field chain`（SH-73）。不是「中间为 0 会崩」，是**编译期就过不去**；L1 只负责第一跳 |
| A6 | `data?.server?.port` | **驳回** | `?.` 的语义是字段访问；`JsonValue` 没有 `server` 字段。要支持这种写法，`?.` 必须定义成「对声明了 `get` 的类型展开为 `get("server")`」，那是另一套语义，提案一没提 |
| A7 | `items?[0]?.name` | **驳回** | 同 A6，`?.name` 仍是字段访问 |
| A8 | `json_get(root, "a.b.c")` | **采纳（过渡）** | 可行；但需定义 key 含 `.` / `[` 的转义（建议加 `json_get_seg(root, char **segs, int n)` 作为底层，路径字符串只是糖）；每次访问 O(段数 × 字符串解析)，要写明 |
| A9 | `json_set(root, path, val)` | **有条件采纳** | 「缺就建」需要看下一段决定建 OBJ 还是 ARR；失败码要细分（类型不符 / OOM / 根是标量）。不能覆盖「删除键」与「数组插入」，建议同期给 `json_unset` |
| A10 | `json_as_str/int/num/bool/obj/arr` | **需改** | `Map *` / `Vec *` 裸泛型不合法（C6），必须写全类型；返回默认值会把「类型不符」变成静默 0，建议 `json_as_int(v, int *out) → int`（返回 0/非 0）或先 `type()` 再取 |
| A11 | `foreach (obj)` | **需改** | `foreach` 只收**变量**，不收指针；`json_as_obj` 返回指针则无法遍历。改法：`Map<char *, struct JsonRef *> json_obj(JsonValue *v)` 返回**句柄副本**（借用语义，不要 `release`），实测 `foreach` 通过（§10 `b19`）；或给 `json_obj_len` / `json_obj_at(i)` |
| A12 | `JsonError` 出参 vs 全局 `last_error` | **需改** | 全局 `last_error` 不重入、线程不安全，且 `msg` 的所有权无处安放（谁 free？）。用出参 `json_decode(text, len, &err)`，`msg` 指向调用方提供的缓冲区或由 `json_error_free` 释放 |
| A13 | 「输出 `JsonValue*`（own，调用方 delete）」 | **需改表述** | `own` 不是返回类型（`own` 只能出现在函数体内的声明上；返回类型位置报 `'own' is only allowed inside a function body`）。实际写法是普通指针 + 调用方 `json_free`；且跨单元 `delete` 不跑 Drop（C10） |

A5/A6 是这份提案最需要改的两条：它们直接影响 J3/J4 的验收能否成立。

---

## 5 实现要点与坑

### 5.1 `\uXXXX`：`lib/std/utf8` 不存在

`lib/` 下只有 `std/`（`Option.h.ct`、`Result.h.ct`、`Str.h.ct`、`Vec.h.ct`），**没有 utf8 模块**；
全仓库 grep `utf8` 无命中。所以 `\uXXXX` 必须包内手写：

- 4 位 hex → 码点；`D800–DBFF` 与 `DC00–DFFF` 要合成代理对，单独出现按非法处理；
- 码点 → 1/2/3/4 字节 UTF-8；
- 反方向（encode 时是否需要转义非 ASCII）要定策略（原样输出 UTF-8 还是全转 `\u`）。

这不是难点，但是**工作量**，且与提案 §5 依赖表的「utf8 已落地」不符。

### 5.2 数字：全存 double 的代价

`9007199254740993` 存 double 变成 `9007199254740992`（blockers N-6 已实测）；`json_as_int` 把
`1e20` 转 `int` 时无诊断地饱和/截断（实测输出 `2147483647`，平台相关 UB）。

建议：`union` 里加 `long long i` + `int is_int`，decode 时按字面量形态分流；`json_as_int` 做范围检查
并返回失败。若坚持全 double，至少把「超过 2^53 的整数会失真」写进 API 文档，并在
`json_as_int` 里判 `(double)(int)x == x`。

### 5.3 键：不复制、不能含 `\0`、`strdup` 可移植性

- `Map` **不复制键**（blockers E-4；`bindings-and-patterns.md` §1 原文：「key 不复制，必须比 map
  活得久」）。`strdup` 的对，但释放责任在 `json_free`，不在 `Map::release`（后者只释放槽位与值，
  不碰 key，`Vec.h.ct:517-537`）。
- JSON 允许 `"\u0000"` 作键，而 `Map<char*,…>` 按 `strcmp` 比较，`"a\0b"` 与 `"a\0c"` 会撞成一个
  （blockers J-2 实测 `len=1`）。v0.1 可以接受，但要在文档里写「键按 C 串比较，含 NUL 的键不支持」。
- `strdup` 在 macOS 直接可用；Linux + `-std=c99` 需要 `_POSIX_C_SOURCE` 或自己写
  `malloc+memcpy`。建议包内写 `json_strdup`，别依赖 libc 的声明开关。

### 5.4 内存：三条事实决定了方案必须改

| 事实 | 实测 | 后果 |
| --- | --- | --- |
| 容器 `release` 不跑元素 Drop | `Vec<L>`（`L use Drop`）`release()` 后没有 `L drop`；生成的 `Vec_L__elem_release` 是 `(void)e;` | 提案「显式遍历释放」是**必要**的，写对了 |
| 跨单元 `delete` 调空桩 | `cfg.h.ct` 定义 `impl Drop` + `pub struct`，消费单元 `delete` 只打印 `done` | `JsonValue::Drop` 在包外**不会执行**；必须导出 `pub void json_free(JsonValue *)` 并让调用方调它 |
| 指针字段自动胶水把 `T**` 当 `T*` | `Leaf_Drop_drop(&_self->leaf)` → `leaf drop 22792752` | 即使单单元，也别依赖自动胶水；`JsonValue` 必须写**显式** `impl Drop`（或干脆不 `use Drop`，只用 `json_free`） |

因此最小方案是：

```c
pub void json_free(JsonValue *v);      /* 唯一的释放入口；递归 obj/arr/str，释放 strdup 的 key */
```

`json_free` 内部怎么遍历 `Map`：`foreach` 只收变量，所以要先把句柄拷出来
（`Map<char *, struct JsonRef *> o = *v->v.obj; foreach (o) { … }`）。这个副本是**借用**
（不增加 `refs`），**不要**对它 `release()`，否则 double free。

### 5.5 encode 的 `Vec<char>` builder 少了最后一步

`Vec<char>` 没有 `data`、没有 `c_str`，`push(0)` 只是把 0 放进缓冲区；拿不到 `char *`
（实测 `no member named 'data' in 'struct Vec_char'`）。`bindings-and-patterns.md` §5 的基线做法
是**再 malloc 一份并逐字节拷贝**：

```c
Vec<char> b = {};
/* … push 字节 … */
char *out = malloc((size_t)b.len() + 1);
int k;
for (k = 0; k < b.len(); k++) out[k] = b.get(k);
out[b.len()] = 0;
b.release();
```

这意味着 encode 至少两次拷贝。更省的做法是自己维护 `char *buf + int len + int cap`（`realloc`），
或直接用 `Str` 累积。提案要写明选了哪条，别只写「push(0) 补 NUL」。

### 5.6 errdefer 与「int 返回码」不兼容

规约原文：「条目带 `on_error`，只在错误出口执行。普通 `return` / `break` / `continue` / 落出只跑
`defer`，丢弃 `errdefer`」（[language-spec.md:2345](../language-spec.md#L2345)）。实测：
`errdefer { flag = 1; }` 后 `return 7`，flag 仍为 0。

所以 `json_decode` 若「失败返回 0」，errdefer **一条都不会跑**。三种可行改法：

1. **`defer` + 成功标志**：`JsonValue *root = 0; int ok = 0; defer { if (!ok) json_free(root); }`；
   成功路径置 `ok = 1`。最贴近现有代码。
2. **改用 `return err`**：函数返回 `Result<JsonValue *, int>` 一类，失败走 `return err code`，
   errdefer 与 `?` 才会接管；但这会改 API 形态。
3. **goto 清理**：显式 `goto fail;`，不依赖 errdefer。

提案 §3.1 写「int 返回码 + errdefer 释放中间对象」，这三者只能选 1 或 3；选 2 就得改签名。

---

## 6 分阶段落地判定

| 阶段 | 提案依赖 | 实际依赖 | 判定 | 可测验收（替代提案的验收） |
| --- | --- | --- | --- | --- |
| **J1** | 无 | **C3**（对象节点必须用指针元素）、C1/C2（语法）、C10（`json_free` 而不是 `delete`） | **需改后可开工** | 新增 `test/json/j1_decode.sh`：固定 5 份输入（空对象、嵌套对象、数组、含 `\uXXXX` 的串、含大整数），断言 decode→encode 往返字节相等（大整数用例单独标「精度已知损失」） |
| **J2** | 无 | A8/A9/A11（路径助手、set、foreach 句柄副本） | **可开工** | 新增 `test/json/j2_path.sh`：对同一棵树断言 `json_get(root,"a.b")`、`json_get(root,"a[0].b")`、`json_set` 后回读；再断言 `json_obj` 的 `foreach` 计数等于 `len` |
| **J3** | L1 | **L1 + SH-73（临时接收者）** | **不成立** | 改为「单层 `v["k"]` 可写」；多层要么接受 `json_get`，要么等 SH-73 改判据。验收：`v["k"]` 编译并返回正确节点，`v[0]` 是硬错（方案 A） |
| **J4** | `?.` | `?.` 的语义要改成 key 访问，或改 `?[...]`；且仍受 SH-73 限制 | **不成立** | 若定义成 `?[...]`：`data?["a"]?["b"]` 在中间缺失时返回 0；若坚持 `.key` 形态，需先改提案一的 `?.` 语义 |
| **J5** | errdefer（称已落地） | errdefer 已落地但语义不同（§5.6） | **需重设计** | 用 `defer + ok` 重写；验收：构造第 3 层失败（非法 token），断言无泄漏（ASAN/leak 检查）且错误码/行列号正确 |

**J1 的「无依赖」不成立**：不是语言依赖，而是**生成器缺陷**（C3）逼着改数据表示。改完后 J1 可以
立即开工，这一点提案的判断是对的。

**J2 的验收里 `data.choices[0].delta` 不可测**：它不是路径字符串，也不是 CT 表达式（没有这些
字段）。要么写成 `json_get(root, "choices[0].delta")`，要么给出真实的 SSE 响应 fixture。

**`examples/json` 不存在**：`ls examples | grep -i json` 无结果。J1 的「与 examples/json 的只读
视图对照」没有对照物，需替换成上面的夹具。

---

## 7 回答提案的三个反问 + 依赖表逐行

### 7.1 三个反问

| 反问 | 结论 | 理由 |
| --- | --- | --- |
| JsonValue 作为 Map 的 key | **要提给 CT 组，但优先级低于键协议本身** | 实测 `Map does not support key type 'struct JsonValue'`，键白名单是编译器硬限制（`Expr.h.ct:2174`）。要做得先有「键协议」（比较 + 哈希 + 所有权），否则只能扩白名单，不够通用 |
| `==` 重载 | **不作为近期需求** | CT 没有运算符重载，`a == b` 在 `cc` 层才报 `invalid operands`。包层写 `json_eq(a, b)` 即可，语义（深比较 / 指针比较）也更清楚 |
| JsonValue 直接 `foreach` | **不提** | `foreach` 只认内置 `Vec`/`Map`（D29-13，`phase29.md:739`），开放给用户类型会误伤同名 `len/get`；包层给 `json_iter`/`foreach (json_obj(v))` 就够 |

### 7.2 §5 依赖表逐行确认

| 提案项 | 提案说法 | 实测/规约 | 结论 |
| --- | --- | --- | --- |
| L1 `v["key"]` | 待落地；引「`phase40-draft.md` 的 D40-1–D40-9」 | **引用错了**：`docs/design/phase40-draft.md` 是 `errdefer` 的卡（文件首行「Phase 40 — `errdefer` 与显式错误出口」，D40-* 是它的决策编号）；L1 的草案是 `docs/proposals/custom-index-protocol.md`（RL1-D1–D7，首行自述「未立项 / 未过分析，不作数」） | **未落地** |
| `?.` | 待落地 | 无 `?.` token；Phase 44 是后缀 `?`（`q_suffix_ahead`） | **未落地** |
| errdefer | 「Phase 40 已落地，直接用」 | Phase 40 ✅（`roadmap:56`）；但只在错误出口执行（`:2345`） | **已落地，语义不同** |
| own / Drop | 已落地 | 是；但 `own` 不接工厂返回、不写返回类型；跨单元 Drop 空桩 | **有条件成立** |
| Map / Vec | 已落地 | 是；`Map<char*, 用户struct>` 在 build 下不编译；容器 release 不跑元素 Drop | **有条件成立** |
| foreach | D29-13 已落地 | 是；只收变量，不收指针 | **有条件成立** |
| utf8 encode/decode | 已落地 | **不存在**：`lib/std` 无 utf8，全仓无命中 | **未落地** |
| pub 方法 | Phase 42 已落地 | 是；但要求宿主是 `pub struct` | **已落地，有条件** |
| 泛型 trait | 「未实现」 | Phase 35 ✅；`trait Show<T>` 实测通过 | **提案描述过时** |

---

## 8 最小可行修订版

### 8.1 数据结构

```c
struct JsonRef {
    struct JsonValue *p;
}

union JsonPayload {
    int    b;
    double n;
    long long i;                  /* 可选的整数通道，见 §5.2 */
    char  *s;
    Map<char *, struct JsonRef *> *obj;
    Vec<struct JsonRef *>         *arr;
}

pub struct JsonValue {
    int tag;
    union JsonPayload v;
}
```

### 8.2 访问与生命周期

```c
impl JsonValue {
    pub JsonValue *get(char *key) {
        Map<char *, struct JsonRef *> *o = self->v.obj;
        struct JsonRef **slot;
        if (o == 0) return 0;
        slot = o->get(key);               /* V* → JsonRef** */
        return slot == 0 ? 0 : (*slot)->p;
    }

    pub JsonValue *get_idx(int i) {
        Vec<struct JsonRef *> *a = self->v.arr;
        struct JsonRef *r;
        if (a == 0 || i < 0 || i >= a->len()) return 0;
        r = a->get(i);                    /* Vec<T>::get → T，即 JsonRef* */
        return r == 0 ? 0 : r->p;
    }

    pub int type(void) { return self->tag; }
    pub int is_null(void) { return self->tag == 0; }
}

/* 唯一的释放入口：不要依赖 delete / Drop 跨单元 */
pub void json_free(JsonValue *v);

/* 遍历：返回句柄副本（借用，不要 release） */
pub Map<char *, struct JsonRef *> json_obj(JsonValue *v);
pub Vec<struct JsonRef *>         json_arr(JsonValue *v);

/* 路径助手：段数组是底层，字符串路径是糖 */
pub JsonValue *json_get_seg(JsonValue *root, char **segs, int n);
pub JsonValue *json_get(JsonValue *root, char *path);
pub int        json_set(JsonValue *root, char *path, JsonValue *val);

/* 错误：出参优先，msg 由调用方缓冲区承载 */
pub int json_decode(char *text, int len, JsonValue **out, JsonError *err);
```

### 8.3 与原文的差异（逐条对应）

1. union 起名 `JsonPayload`（C2）；
2. 所有泛型写全实参（C1）；
3. 对象/数组元素改 `JsonRef *`，`get` 返回 `JsonRef**` 并在内部解一次（C3）；
4. 去掉「`v["a"]["b"]` 可用」的承诺，改成单层 + `json_get` / `json_get_seg`（C4）；
5. 去掉 `data?.server?.port`，改成 `json_get` 或等 `?[...]`（C5）；
6. `json_obj` / `json_arr` 返回句柄副本，`foreach` 才能用（C6）；
7. 错误清理用 `defer + ok` 或 `err:`，不用「return 0 + errdefer」（C7）；
8. encode 明确「两次拷贝」或自管缓冲区（C8）；
9. 释放统一走 `json_free`，不承诺跨单元 `delete`（C10）。

---

## 9 回给提案方的确认问题清单

1. `JsonRef` 到底选**内联**（`struct JsonRef { struct JsonValue v; }`，零额外分配但 Map 值元素在
   build 下不可用）还是**指针**（`JsonValue *p`，可用但每节点一次分配）？两种的 API 返回值不同。
2. 对象节点用 `Map<char *, JsonRef *>` 意味着 `get` 要处理 `JsonRef**`；你接受这个内部形状，
   还是希望包内再封一层 `json_at(v, key)` 把它藏掉？
3. `v["a"]["b"]` 若在 L1 下确实编译不过（本文实测），J3 的验收改成「单层下标」是否可接受？
   还是要求 CT 组同时改 SH-73（临时接收者）？
4. `?.` 若保持「字段访问」语义，对 JSON 没有用；你是否同意把它改成 `?[...]`（key 下标短路），
   或改成「对声明了 `get` 的类型展开」？这需要提案一先定。
5. 失败路径的清理选哪种：`defer + ok`、`return err`（改签名）、还是 `goto fail`？
6. `json_as_*` 是保留「默认值」契约，还是改成 `int json_as_int(v, int *out)`？前者不可诊断，
   后者调用点变长。
7. `JsonError` 用出参还是全局？`msg` 由谁释放？如果是全局，如何应对并发/重入？
8. 大整数是否接受「全 double、>2^53 失真」？若不接受，是否同意在 union 里加
   `long long i` + `is_int`？
9. `strdup` 是否允许用在 Linux（`-std=c99` 下需要特性宏）？还是包内统一
   `json_strdup = malloc + memcpy`？
10. J1 的验收能否换成具体夹具（当前 `examples/json` 不存在）？请给 5 份输入样例。

---

## 10 复现附录

新环境 `/tmp/ctgap2`（`ct` 副本 + `CT_STD_DIR=<repo>/lib/std`）。`v*` / `b*` / `c*` 为单文件探针，
`b1`、`b5`、`b11`、`b14`、`b19` 为 `ct build` 工程。

| 探针 | 命令 | 原始结果 |
| --- | --- | --- |
| `v1_proposed_struct` | `ct v1.ct -o v1.c` | `v1.ct:7:13: error: generic struct 'Map' needs type arguments in a type position`，rc=1 |
| `c1_anon_union` | `ct c1.ct -o c1.c` | `c1.ct:10:7: error: an anonymous record member cannot have a name; tag the record instead`，rc=1 |
| `v2_corrected` | `ct` + `cc` | rc=0（具名 union + 全实参 + `JsonRef` 前向声明的单文件形态） |
| `v3_chain_call` | `ct v3.ct -o v3.c` | `v3_chain_call.ct:27:1: error: method receiver must be a variable, an element, a call or a field chain`，rc=1 |
| `v4_union_receiver` | 同上 | `v4_union_receiver.ct:18:1: error: cannot resolve the method trait (unknown receiver type)`，rc=1 |
| `b1`（J1 原样） | `ct build src/main.ct -o out` | `.ctbuild/Vec.h:32:20: error: field has incomplete type 'struct JsonRef'`，rc=1 |
| `b14`（元素改指针） | 同上 | rc=0；run rc=0 |
| `b9_strdup_get` | `ct` + `cc` + run | `1 3`（`Map<char*,JsonValue*>` 的 `get` 是 `JsonValue**`；`strdup` 可用） |
| `b2_foreach_ptr` | `ct` | `error: foreach needs an array or a Vec/Map; 'mp' is not iterable`，rc=1 |
| `b12_foreach_copy` | `ct` | `foreach (copy)` 通过；`foreach (*mp)` 报 `foreach needs a plain array variable` |
| `b19`（`json_obj` 句柄副本） | `ct build` + run | rc=0；输出 `1` |
| `b3_errdefer` | `ct` + `cc` + run | `after_normal_return=0`（errdefer 未执行） |
| `b4_vec_builder` | `ct` rc=0；`cc` | `error: no member named 'data' in 'struct Vec_char'` |
| `b7_json_key` | `ct` | `Map does not support key type 'struct JsonValue' (use int, long or char *)`，rc=1 |
| `b8_eq` | `ct` rc=0；`cc` | `invalid operands to binary expression ('struct P' and 'struct P')` |
| `b10_ptr_field_drop` | `ct` + `cc` + run | `leaf drop 58236000`、`done`；生成 `Leaf_Drop_drop(&_self->leaf);` |
| `b11`（跨单元 Drop） | `ct build` + run | rc=0；只输出 `done` |
| `b18_container_drop` | `ct` + `cc` + run | 只输出 `done`；`Vec_L__elem_release` 为 `(void)e;` |
| `b15_embed_ref` | `ct` + `cc` + run | `2 1.5 sizeof=16`（内联 `JsonValue` 零额外分配） |
| `b17_int_overflow` | `ct` + `cc` + run | `2147483647`（`(int)1e20`，无诊断） |
| `b5`（pub 方法） | `ct build` | 非 `pub struct` 报 `a pub method needs a pub struct in a .h.ct unit`；改 `pub struct` 后 `j.get(1)` 跨单元可用 |
| `b6_generic_trait` | `ct` + `cc` | rc=0（`trait Show<T>` 可用） |
| `c2_as_bare` | `ct` | `error: generic struct 'Map' needs type arguments in a type position`，rc=1 |

**环境提醒**：不设 `CT_STD_DIR` 时，`Map *` 会被静默放行并生成 `Map * obj;`（`cc` 才报错），
`Vec<int>` 报 `use of an undeclared variable`。本文所有探针都在设该变量的环境下执行。
