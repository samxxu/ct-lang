# ct-json 0.1.0 的 CT 能力阻塞清单

> **读者**：CT 语言与编译器的维护者。
> **用法**：本文可以独立阅读——每条都从「JSON 要做什么」出发，给出实测复现，再判断该不该由语言补。
> 七域总清单（按能力域组织）见 [language-capability-gaps.md](language-capability-gaps.md)，只作背景，不需要先读。
>
> **基线**：CT `v0.44.1`（tag `13db6cad`，二进制 `~/.local/bin/ct`）；仓库 `b5797cbf`。
> 探针全部在 `/tmp/ctgap/j`，不在仓库内。多单元探针需 `CT_STD_DIR=<repo>/lib/std`，否则泛型声明会被误解析（见 §5.3）。
>
> **纪律**：只新增本文；不改实现、不改规约、不改夹具、不 bump、不打 tag。

---

## 0 结论先行（可直接摘出）

**以 CT v0.44.1，ct-json 能做出一个正确的 JSON 解码/编码实现，但做不出一个「原生容器 + 值语义 + 键保真 + 自动释放」的包。**

具体边界：

| 能交付 | 交付不了 |
| --- | --- |
| 在**单个 `ct build` 工程内**用 `Vec<JsonRef>` 表示数组；用 `Map<char*, JsonRef *>` 表示对象；显式递归释放；自己写 encode；错误用返回码 | 「对象值按值存在 Map 里」（`Map<char*, JsonRef>` 在 build 模式下生成不可编译的头，J-1）；「含 `\0` 的键原样保留」（键只能是 `int`/`long`/`char*`，J-2）；「`delete doc` 自动递归释放」（跨单元 Drop 是空桩，J-3）；「`own doc = json_decode(...)`」（J-4） |

需要 CT 组判断的只有两件：**J-1（容器装用户 struct 的完整性）是生成器缺陷，改法明确**；
**J-2（键协议）是规范空白，要决定容器键要不要可扩展**。其余 4 条是「改交付形态就能过」，
本文按软阻塞列出，供排期参考。

---

## 1 判定口径

### 1.1 三种标签

| 标签 | 含义 |
| --- | --- |
| **硬阻塞** | 不补就必须改 ct-json 的**数据表示**，或必须牺牲正确性（键字节、存活期） |
| **软阻塞** | 不补就必须改**交付形态**：放弃自动化、放弃某个语法、放弃一条 API |
| **不构成阻塞** | 换个写法即可，功能不受影响（§3 单列） |

### 1.2 「规范还是实现」二选一

- **规范空白**：规约没有给出语义（含「明文排除」与「未定义但被实现固定」）。
- **实现缺陷**：规约已有要求或可推出，实现没做到（含静默产出错误 C）。

### 1.3 证据分级

- 未标注的「当前行为」= 本文作者在 v0.44.1 上**实测**，命令与原始输出见 §5。
- 标 **来源：X** 的 = 未在本机重跑，依据提交/夹具/规约原文，坐标一并给出。

---

## 2 阻塞清单

### J-1 对象节点：`Map<char *, JsonRef>` 在 `ct build` 下生成不可编译的头

| 项 | 值 |
| --- | --- |
| 阻塞的 JSON 功能 | 解码出对象节点、按 key 取值、遍历对象 |
| 定性 | **实现缺陷** |
| 级别 | **硬阻塞**（必须改数据表示） |
| 建议优先级 | **P0** |
| 版本状态 | v0.44.1 实测失败 |

**JSON 侧要什么**：

```c
struct JsonRef {
    int tag;
    double num;
}

struct JsonDoc {
    Map<char *, JsonRef> *obj;   /* 对象：键 → 值，值按值存在容器里 */
}
```

**CT 现在卡在哪**（实测，探针 `/tmp/ctgap/j/j10b`，工程里只有一个 `main.ct`）：

```text
$ ct build src/main.ct -o out
In file included from .ctbuild/Vec.c:3:
.ctbuild/Vec.h:31:20: error: field has incomplete type 'struct JsonRef'
   31 |     struct JsonRef value;
.ctbuild/Str.h:16:8: note: forward declaration of 'struct JsonRef'
$ echo $?
1
```

生成的头里，`Map` 的条目结构按值容纳用户类型，但该类型只有前向声明：

```c
/* .ctbuild/Vec.h:29-32 */
struct MapEntry_char_p_JsonRef {
    char* key;
    struct JsonRef value;      /* JsonRef 在这里只有 struct JsonRef; */
};
```

关键对比（都实测）：

| 形态 | 单文件 `ct x.ct` | `ct build` |
| --- | --- | --- |
| `Vec<JsonRef>` | 通过 | **通过**（`.ctbuild/Vec.h` 只前向声明，实例在单元内） |
| `Map<char *, JsonRef *>` | 通过 | **通过** |
| `Map<char *, void *>` | 通过 | **通过** |
| `Map<char *, JsonRef>` | 通过 | **失败**（上面的 `incomplete type`） |

所以不是「泛型字段不能导出」——`Vec<JsonRef> *` 放进 `.h.ct` 也能过（探针 `j16`：build rc=0）。
**只有 `Map` 的条目结构把元素按值写进共享头**，而共享头不 include 元素定义所在的单元。

**这属于什么**：**实现缺陷**。语言对「容器元素类型」没有「必须是完整类型」的限制条款；
生成器把 `MapEntry` 放进共享头时，应当保证元素类型在该处完整（include 定义单元的头，或把
`MapEntry` 下沉到实例化的单元）。`Vec` 的实例已经这么做了，`Map` 的条目没有。

**最小期望**：`Map<K, UserStruct>` 在 `ct build` 下可编译——`MapEntry` 的 `value` 字段在
使用它的翻译单元里是完整类型。满足这一条就算解决，不要求改 `Map` 的 API。

**有没有绕法**：

| 绕法 | 现在怎么写 | 代价 |
| --- | --- | --- |
| 元素改成指针 | `Map<char *, JsonRef *>`；`get` 返回 `JsonRef **` | 每个对象值一次堆分配 + 一次指针跳转；释放要自己遍历；缓存局部性变差 |
| 元素擦成 `void *` | `Map<char *, void *>` + 强转 | 同上，且丢类型检查（本来也没有） |
| 换有序表 | `Vec<struct Pair>` + 线性查找 | 对象查找 O(n)，大对象不可接受 |
| 不用 build 模式 | 单文件 `ct json.ct -o json.c` | 不能作包交付（没有 `import`、没有多单元） |

**不补的话，ct-json 能不能降级交付**：**能，但要改数据表示**。对象值变成堆上的
`JsonRef *`，`get` 变成 `JsonRef **`，释放多一层遍历。丢的是**性能与所有权简单性**，
不丢功能与正确性。这条是「改起来明确」的实现缺陷，建议 CT 组优先修。

---

### J-2 键保真：`Map` 只收 `int` / `long` / `char *`，含 `\0` 的键写不出来

| 项 | 值 |
| --- | --- |
| 阻塞的 JSON 功能 | 对象键的字节保真（`"\u0000"` 也是合法键）、键的原样往返 |
| 定性 | **规范空白** |
| 级别 | **硬阻塞**（除非加一层键编解码） |
| 建议优先级 | **P1** |
| 版本状态 | v0.44.1 实测失败；规约未载该限制 |

**JSON 侧要什么**：

```c
Map<struct Str, JsonRef> obj;                 /* 想用长度前缀串作键，保住内嵌 \0 */
struct Str k = str_from_len("a\0b", 3);
obj.put(k, v);
```

**CT 现在卡在哪**（实测，探针 `/tmp/ctgap/j/e2b_str_key.ct`、`e2_nul_key.ct`）：

```text
$ ct e2b_str_key.ct -o e2b.c
e2b_str_key.ct:5:26: error: Map does not support key type 'struct Str' (use int, long or char *)
$ echo $?
1
```

退到 `char *` 作键，两个不同键会撞成一个：

```c
char a[] = "a\0b";   char c[] = "a\0c";
m.put(a, 1);         m.put(c, 2);
```

```text
len=1 v1=2 v2=2        /* 第二次 put 覆盖了第一次 */
```

顺带一个同族事实：`Str` 本身是**可用**的，值侧没问题（实测 `len=3 3 cmp=-1`，
`str_from_len("a\0b",3)` 保住了内嵌 NUL）；问题只在**键**。

**这属于什么**：**规范空白**。限制由编译器发出
（[selfhost/ct-ast/frontend/parse/Expr.h.ct:2174](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2174)），
负例固定在 [selfhost/check-ast.sh:6964](../../selfhost/check-ast.sh#L6964) / [:7128](../../selfhost/check-ast.sh#L7128)，
但 `language-spec.md` 里搜不到这条限制。**规约从没定义「容器的键要满足什么」**，所以是空白，不是偏离。

**最小期望**：`Map` 的键类型可以由类型自身提供「比较 + 所有权」，或至少接受长度前缀的字节串。
满足「两个只在 `\0` 之后不同的键不会碰撞」就算够用。

**有没有绕法**：

| 绕法 | 现在怎么写 | 代价 / 牺牲什么 |
| --- | --- | --- |
| 键转义编码 | 把 `\0` 编成 `\u0000` 之类的文本再作 `char *` 键；API 出口再解回 | 编解码成本；密钥长度膨胀；**若出口不解回，键的字节就不保真** |
| 换有序表 | `Vec<struct { Str key; JsonRef v; }>` + 线性比较 | O(n) 查找；`Map` 的 API 全部自写 |
| 双结构 | 键存 `Str` 数组，值存 `Vec`，索引用临时 `char *` | 两套结构、同步维护、所有权更复杂 |

**不补的话，ct-json 能不能降级交付**：**能，但「键原样往返」这条要么加一层编解码，要么放弃**。
降级后丢的是**字节保真**（如果出口不解码）或**性能**（如果加编解码层）。这是本文唯一
「语言侧改不动、包侧只能加层」的项。

---

### J-3 自动递归释放：跨单元 `Drop` 是空桩，指针字段胶水还会读错

| 项 | 值 |
| --- | --- |
| 阻塞的 JSON 功能 | `delete doc` 自动递归释放整棵树 |
| 定性 | **实现缺陷** |
| 级别 | **软阻塞**（写显式 `json_free` 即可；但若误用 Drop 会静默出错） |
| 建议优先级 | **P1** |
| 版本状态 | v0.44.1 实测失败 |

**JSON 侧要什么**：

```c
/* 树形结构，希望 delete 一次就干净 */
delete doc;
```

**CT 现在卡在哪**（实测，探针 `/tmp/ctgap/j/../m/d4`）：

```c
/* cfg.h.ct */
pub struct Res { int id; } use Drop;
impl Drop for Res { void drop(void) { printf("res drop %d\n", self->id); } }

/* main.ct */
import cfg::cfg;
struct Res *r = malloc(sizeof(struct Res));
r->id = 7;
delete r;
```

```text
$ ct build src/main.ct -o out && ./out
done                 /* 期望多一行 "res drop 7" */
$ echo $?
0
```

生成的消费单元里是空桩，而且调用了它：

```c
static void __attribute__((unused)) Res_Drop_drop(void *self) {
    struct Res *_self = (struct Res *)self;
    (void)_self;
}
...
if (r) { Res_Drop_drop(r); free(r); r = 0; }
```

真实体在定义单元的 `.c` 里，但符号是 `static`，消费单元链接不到也看不见。

同族第二处：**指针字段的自动胶水把 `T**` 当 `T*`**（实测，探针 `g8`）：

```c
static void Node_Drop_drop(void *self) {
    struct Node *_self = (struct Node *)self;
    Leaf_Drop_drop(&_self->leaf);        /* 传 struct Leaf **，形参是 void * */
}
```

```text
$ ./g8.bin
leaf drop 22792752     /* 期望 "leaf drop 2"：id 读成了指针低 32 位 */
done
```

`ct`、`cc`、运行全部 rc=0，无诊断。所以「有指针子节点的树」即使在同一单元，自动胶水也是错的。

**这属于什么**：**实现缺陷**。规约 §4.56 明说 `delete p` 调用 `<S>_Drop_drop(p)`，且「无显式
impl 时按字段声明顺序递归生成释放胶水」（[language-spec.md:2325](../language-spec.md#L2325)）。
空桩与「对指针槽取地址」都不满足这两句。另有一句承认跨单元限制（[:1569](../language-spec.md#L1569)），
但**没有**说「跨单元 delete 变成空操作」。

**最小期望**：`delete p` 调用的 Drop 体来自**定义 impl 的单元**；指针字段的胶水对子对象调用
（`delete _self->f` 或 `_f(...)`），而不是对指针槽取地址。满足其一即解决当前错误；两者都要有。

**有没有绕法**：

| 绕法 | 现在怎么写 | 代价 / 牺牲什么 |
| --- | --- | --- |
| 显式递归释放 | `json_free(JsonRef *r)`：按 tag 递归 `Map::release` / `Vec::release` / `free`；树类型**不要** `use Drop` | 每个结构手写一遍；忘记调用就泄漏（但不会误释放） |
| 只用单单元 | 把树与释放都放在一个 `.ct` 里 | 不能作多单元包 |
| 父类型写显式 `impl Drop` | 每个父类型手写 `delete self->leaf` | 仍受跨单元空桩影响；只在单单元有效 |

**不补的话，ct-json 能不能降级交付**：**能**。丢的是**自动化**（必须显式 `json_free`），
不丢正确性。但必须在包文档里写死「不要依赖 Drop 自动释放」——因为误用的后果是**静默不释放**，
比报错难查。

---

### J-4 解码入口的所有权：`own` 不能接工厂返回值

| 项 | 值 |
| --- | --- |
| 阻塞的 JSON 功能 | `own JsonDoc *doc = json_decode(text);` 这种「构造即托管」的入口 |
| 定性 | **规范空白** |
| 级别 | **软阻塞**（改成普通指针 + 显式 `json_free`） |
| 建议优先级 | **P2** |
| 版本状态 | v0.44.1 实测失败 |

**JSON 侧要什么**：

```c
own struct JsonDoc *doc = json_decode(text);   /* 期望离开作用域自动释放 */
```

**CT 现在卡在哪**（实测，探针 `g2_own_return.ct`、`g6_own_in_sig.ct`）：

```text
$ ct g2_own_return.ct -o g2.c
g2_own_return.ct:15:1: error: 'own' requires a malloc or calloc initialiser
$ echo $?
1
```

把 `own` 写进返回类型（`own struct JsonDoc *json_decode(...)`）在 v0.44.1 上是编译期硬错
（修正了旧材料「会生成非法 C」的说法）：

```text
g6_own_in_sig.ct:7:1: error: 'own' is only allowed inside a function body
$ echo $?
1
```

**这属于什么**：**规范空白**。规约把 `own` 的初始化式限定为 `malloc` / `calloc`
（[language-spec.md:397](../language-spec.md#L397)），返回类型位置没有任何条款（既不允许也没禁止，
实现直接按「只能在函数体内」拒）。

**最小期望**：`own p = factory(...)` 可写，或明确「`own` 只接受 `malloc`/`calloc`」并给出可操作诊断。
前者需要定义「返回值所有权转移 + 失败时怎么记账」，后者只需一句条款。

**有没有绕法**：

| 绕法 | 现在怎么写 | 代价 / 牺牲什么 |
| --- | --- | --- |
| 普通指针 + 显式释放 | `JsonDoc *d = json_decode(text); ... json_free(d);` | 丢自动释放；错误路径要自己清理 |
| 调用方分配 | `void json_decode_into(JsonDoc *d, ...)` + `own JsonDoc *d = malloc(...)` | 构造点两段式；失败语义要自己定 |

**不补的话，ct-json 能不能降级交付**：**能**。丢的是「构造即托管」的便利，不丢功能。

---

### J-5 `doc["a"]["b"]` 形态：自定义下标未立项

| 项 | 值 |
| --- | --- |
| 阻塞的 JSON 功能 | 按下标链取值（`doc["a"]["b"]`）这一种语法 |
| 定性 | **规范空白**（提案自述未立项） |
| 级别 | **软阻塞**（换访问器方法） |
| 建议优先级 | **P2** |
| 版本状态 | v0.44.1：用户类型下标原样发射 C，`cc` 才报错 |

**JSON 侧要什么**：

```c
int n = doc["host"]["port"];        /* 逐层取 */
```

**CT 现在卡在哪**（实测，探针 `f1b_inherent_subscript.ct`）：

```c
struct Box { int x; }
impl Box {
    int get(int i) { return self->x + i; }
}
int main(void) { Box b; b.x = 5; return b[0]; }
```

```text
$ ct f1b_inherent_subscript.ct -o f1b.c
$ echo $?                     # ct 放行
0
$ cc -std=c99 f1b.c -o f1b.bin
f1b_inherent_subscript.c:170:13: error: subscripted value is not an array, pointer, or vector
  170 |     return b[0];
```

补充两条实测边界：

- `Vec` / `Map` 的内建下标是**可用**的：`v[0]` 展开为 `Vec_int_get(&v, 0)`，`m["k"]` 展开为
  `Map_char_p_int_get(&m, "k")`（探针 `j4`，`ct`+`cc` 均过）。
- 写形态是硬错，文案可操作：`v[0] = 2;` → `error: a Vec subscript is read-only; use set(i, v)`（探针 `j8`）。

所以 `doc["a"]` 断在第一跳，是因为 `doc` 是**用户类型**，没有下标协议；不是因为容器不支持下标。

**这属于什么**：**规范空白**。`REQ-L1` 在需求池里 `status = open`；
[custom-index-protocol.md](custom-index-protocol.md) 首行自述「提案 / 未立项 / 未过分析，不作数」，
并明确「不做指针接收者」。规约现状是「`Vec` / `Map` 有糖，其余原样发射」。

**最小期望**：类型在 `impl` 里声明签名匹配的 `get` 后，`obj[k]` 展开为调用；未声明时编译期硬错
并指名类型。不要求运算符重载，不要求指针接收者。

**有没有绕法**：

| 绕法 | 现在怎么写 | 代价 / 牺牲什么 |
| --- | --- | --- |
| 访问器 | `doc.obj->get("host")->obj->get("port")`（`Map::get` 返回指针，可一路 `->`） | 写法啰嗦；`doc["a"]["b"]` 这条产品要求不成立 |
| 逐跳落局部 | `JsonRef *a = doc.obj->get("a"); ... a->obj->get("b")` | 多行；好处是不踩 J-6 的字段链边界 |

**不补的话，ct-json 能不能降级交付**：**能**。丢的是**语法糖**，不丢功能。若「必须支持
`doc["a"]["b"]`」是硬需求，那它才是阻塞；否则只是体验。

---

### J-6 encode 入口消歧：无重载，CT 只告警、错误留到 `cc`

| 项 | 值 |
| --- | --- |
| 阻塞的 JSON 功能 | 三个同名 `json_encode`（map / vec / scalar）共存的入口设计 |
| 定性 | **实现缺陷** |
| 级别 | **软阻塞**（改名即可） |
| 建议优先级 | **P2** |
| 版本状态 | v0.44.1 实测：`ct` 只发 warning，`cc` 报 `conflicting types` |

**JSON 侧要什么**：

```c
int json_encode(JsonDoc *d, char *buf, int cap);
int json_encode(JsonRef *v, char *buf, int cap);
int json_encode(double x, char *buf, int cap);
```

**CT 现在卡在哪**（实测，探针 `g1_overload.ct`）：

```text
$ ct build g1_overload.ct -o g1b
g1_overload.ct:12:13: warning: type mismatch: 'encode' argument 1: expected 'char *', got 'int'
g1_overload.ct:13:5: error: conflicting types for 'encode'
$ echo $?
1
```

`ct` 在**调用点**按先看到的签名发一条 warning 并继续生成 C；两处定义到 `cc` 才失败。单文件模式
没有 `#line`，错误指向生成的 `.c`。

**这属于什么**：**实现缺陷**。规约没有「允许重载」的条款，C 也不允许两个同名同链接性的定义；
「同单元同名两次定义」应当在定义处就报硬错，而不是调用点 warning + 后段 `cc` 错误。

**最小期望**：同一单元内同名函数在定义处报硬错（不要求支持重载）。

**有没有绕法**：改成 `json_encode_doc` / `json_encode_value` / `json_encode_num`。
代价只是 API 名字变长。**不补也能降级交付**：不丢功能，丢的是 API 美观。

---

## 3 不构成阻塞（换写法即可）

下面每一条都在输入材料里被当成阻塞候选，但 v0.44.1 上换写法可解，**不应混进阻塞清单**。
每条给「换个什么写法」与「丢什么」。

| 编号 | 候选阻塞点 | v0.44.1 实测 / 来源 | 换个写法 | 丢什么 |
| --- | --- | --- | --- | --- |
| N-1 | 匿名 `union` 成员不可命名（`union { … } v;`） | `a1_anon_union.ct:6:7: error: an anonymous record member cannot have a name; tag the record instead`，rc=1 | 先命名 union 类型：`union JsonVal { … }` + `union JsonVal v;` | 多一个类型名；访问多一层。实测 `sizeof(JsonRef)=16`、`sizeof(union)=8` |
| N-2 | 裸泛型类型名（`Map *` / `Vec *`） | `a2_bare_generic.ct:3:9: error: generic struct 'Map' needs type arguments in a type position`，rc=1 | 写全类型实参；要做类型擦除就 `Map<char *, void *>` | 无（裸泛型在 C 里也没有意义） |
| N-3 | 带泛型字段的 struct 不能进 `.h.ct` | **部分不成立**：`Vec<int>` 与 `Vec<JsonRef> *` 都能导出（`a3b`/`j16` build rc=0）；只有 `Map<char*, 用户 struct>` 失败——那是 J-1，不是导出问题 | 见 J-1 | 见 J-1 |
| N-4 | `#define` 不进生成头 | `d1`：`use of undeclared identifier 'JSON_TAG_NUM'`，rc=1 | `.h.ct` 里用 `pub enum JsonTag { Num = 2 }`，消费方用裸名 `Num`（`d2b` build rc=0） | 只能整数常量；不能放字符串/浮点 |
| N-5 | `pub enum` 不能放 `.m.ct` | `jsonx.m.ct:3:5: error: a .m.ct unit cannot declare a type`，rc=1 | 把 enum 放 `.h.ct`，`.m.ct` 只放映射 | 包布局多一个文件 |
| N-6 | 只有 `double`：`9007199254740993` 掉精度、`1e400` 变 `inf` | **不成立**：`union` 里放 `long long` 可原样保存 `9007199254740993`（`j5`：`ll=9007199254740993`，转 double 才是 `…992`）；`1e400 → inf` 是 C/libc 行为（`e1`） | 值用 `union { long long i; double n; }`；encode 前 `isfinite` / 范围检查 | 无（这是包的类型选择，不是语言缺口） |
| N-7 | 没有带长度的字符串/字节值 | **部分不成立**：`Str` 存在且保住内嵌 NUL（`j6`：`len=3 3 cmp=-1`） | 值用 `Str`；`str_from_len` / `str_compare` 已够 | 键不能用 `Str`——那是 J-2 |
| N-8 | 容器取元素返回的不是指针（`JsonRef *item = arr->get(i)`） | `b6`：`cc` 报 `initializing 'struct P *' with an expression of incompatible type 'struct P'` | 按值取：`JsonRef item = arr->get(i);`；要改元素就 `set(i, v)` | 取到的是拷贝；就地修改要写回 |
| N-9 | 字段访问结果不能作接收者（`doc->root.v.obj->get(...)`） | **只有跨 union 成员时失败**：`j7` 报 `cannot resolve the method trait (unknown receiver type)`；同样深度但全是 struct 的 `j9` 通过；`j1` 的 `o.obj->get(...)` 也通过 | 先落局部：`Map<…> *obj = doc.root.v.obj; obj->get("k")`（`j17` 通过，输出 7） | 每个取值点多一行；不改语义 |
| N-10 | 接口值作为返回值装箱 | 0.44.1：`Resp res = q.send();` → `cannot infer the type to box`（`b1`）；`return <局部>` 生成 `(void *)&r`，运行 `1 200`（`b4`）；`return self` 生成 `&_self`（`b3`）。**HEAD 均已修**（`5ff69ac3`/`d6e82e25`/`b5797cbf`，来源：提交与夹具，未重跑） | 树式 API 不用接口；若要用，别从函数返回接口值（用出参或全局对象） | 接口式 API 在 0.44.1 上不可用；树式 API 不受影响 |
| N-11 | `.m.ct` 不能 import `.h.ct` | v0.44.1：`a .m.ct unit can only import another .m.ct unit`（`m1`）；**HEAD `fb55985c` 已放开**（来源：提交 + 夹具 `test/modules/sh71_map_import_hdr`，未重跑） | 不写 `"text".parse()` 这种字符串起手；用 `.h.ct` 自由函数 `json_decode_ex(...)` | 丢一个可选 API 形态，不丢功能 |
| N-12 | 无自动类型转换语法糖（`char *s = ref;`） | `f3`：`ct` rc=0，`cc` 只有 warning，运行把结构体地址当字符串 | 写显式函数 `json_ref_to_str(v)` | 调用点啰嗦；反而更安全 |
| N-13 | 容器不复制键/值（值按值拷、键存指针） | `e5`：`put(buf,"key1")` 后改 `buf`，`get("key1")` 返回 `0x0` | 键自己 `strdup` 并自己 `free`（容器无释放钩子） | 每个键一次分配；漏释放就泄漏 |

其中 N-9 与 N-10 值得 CT 组单独看一眼：N-9 是「union 成员打断了方法接收者的类型解析」，
根因与 N-10 的装箱推断相邻，但影响面小（落局部即可）；N-10 已修，**发版即可关闭**。

---

## 4 汇总表

| 编号 | 阻塞的 JSON 功能 | 规范 / 实现 | 不补的后果 | 建议优先级 |
| --- | --- | --- | --- | --- |
| **J-1** | 对象节点：`Map<char*, JsonRef>` 在 build 模式可编译 | **实现缺陷** | 必须把对象值改成堆指针（`JsonRef *`），每个值一次分配，`get` 变 `JsonRef **` | **P0** |
| **J-2** | 键保真（含 `\0` 的键） | **规范空白** | 必须加键转义层（丢字节保真）或换有序表（丢 O(1) 查找） | **P1** |
| **J-3** | `delete` 自动递归释放 | **实现缺陷** | 必须手写 `json_free`；误用 Drop 会静默不释放 | **P1** |
| **J-4** | `own doc = json_decode(...)` | **规范空白** | 必须普通指针 + 显式释放（丢自动释放） | P2 |
| **J-5** | `doc["a"]["b"]` 下标链 | **规范空白** | 必须用访问器 / 逐跳落局部（丢语法糖） | P2 |
| **J-6** | 三个同名 `json_encode` | **实现缺陷** | 必须改名（丢 API 美观，且错误信息指向生成 C） | P2 |
| N-1 | 匿名 union 具名成员 | 规范空白（明文拒绝） | 命名 union 类型（多一个类型名） | P3 |
| N-2 | 裸泛型类型名 | 规范空白 | 写全实参（无损失） | P3 |
| N-3 | 泛型字段进导出头 | 部分不成立（见 J-1） | — | — |
| N-4 | `#define` 常量导出 | 规范空白 | 改 `pub enum`（只能整数） | P3 |
| N-5 | `pub enum` 不能放 `.m.ct` | 规范空白 | enum 放 `.h.ct` | P3 |
| N-6 | 只有 `double` | **不成立**（`long long` 可用） | 用 `union` 存整数 | — |
| N-7 | 无长度前缀字符串 | **部分不成立**（`Str` 可用） | 值用 `Str`；键另见 J-2 | — |
| N-8 | 容器 `get` 返回形态 | 规范空白 | 按值取 + `set` 写回 | P3 |
| N-9 | 跨 union 成员字段链 | **实现缺陷** | 落局部（多一行） | P2 |
| N-10 | 接口值返回装箱 | **实现缺陷** | 不用接口式 API；HEAD 已修待发版 | P1（发版） |
| N-11 | `.m.ct` import `.h.ct` | 规范空白 | 用自由函数入口；HEAD 已修待发版 | P2（发版） |
| N-12 | 无转换语法糖 | 规范空白 | 显式函数 | P3 |
| N-13 | 容器不复制键/值 | 规范空白 | 自己 `strdup` / 自己 `free` | P2 |

**计数**：19 条覆盖点；硬阻塞 2（J-1、J-2），软阻塞 4（J-3–J-6），不构成阻塞 13（N-1–N-13，
其中 N-3/N-6/N-7 是「旧结论部分或全部不成立」）。
按定性：实现缺陷 5（J-1、J-3、J-6、N-9、N-10），规范空白 11，另有 3 条为「不成立/部分不成立」不计。

---

## 5 复现附录

### 5.1 单文件探针（`/tmp/ctgap`，`CT_STD_DIR=<repo>/lib/std`）

| 探针 | 命令 | 原始结果 |
| --- | --- | --- |
| `j5_int64` | `ct` + `cc` + run | `ll=9007199254740993`、`as_double=9007199254740992` |
| `j6_str_nul` | 同上 | `len=3 3 cmp=-1`、`cstr_len_ok=1` |
| `j7_union_chain` | `ct j7.ct -o j7.c` | `j7_union_chain.ct:32:1: error: cannot resolve the method trait (unknown receiver type)`，rc=1 |
| `j9_struct_chain` | `ct` + `cc` + run | rc 全 0；输出 `7`（同样深度、全 struct） |
| `j17_local_bind` | 同上 | rc 全 0；输出 `7`（落局部后通过） |
| `j4_builtin_subscript` | 同上 | rc 全 0；生成 `Vec_int_get(&v, 0)`、`Map_char_p_int_get(&m, "k")` |
| `j8_vec_write` | `ct j8.ct -o j8.c` | `j8_vec_write.ct:4:6: error: a Vec subscript is read-only; use set(i, v)`，rc=1 |
| `j10_tree_local` | `ct` + `cc` + run | rc 全 0；`1 2 2`（单文件模式树可用） |
| `e2b_str_key` | `ct` | `Map does not support key type 'struct Str' (use int, long or char *)`，rc=1 |
| `e2_nul_key` | `ct` + `cc` + run | `len=1 v1=2 v2=2` |
| `e5_key_copy` | 同上 | `key1=0x0 key2=0x1017d6fd8` |
| `g1_overload` | `ct build` | warning `type mismatch` + `error: conflicting types for 'encode'`，rc=1 |
| `g2_own_return` | `ct` | `'own' requires a malloc or calloc initialiser`，rc=1 |
| `g6_own_in_sig` | `ct` | `'own' is only allowed inside a function body`，rc=1 |
| `g8_ptr_field_glue` | `ct` + `cc` + run | `leaf drop 22792752`、`done`；生成 `Leaf_Drop_drop(&_self->leaf);` |
| `a1_anon_union` | `ct` | `an anonymous record member cannot have a name; tag the record instead`，rc=1 |
| `a2_bare_generic` | `ct` | `generic struct 'Map' needs type arguments in a type position`，rc=1 |
| `b1_iface_ret` | `ct` | `cannot infer the type to box`，rc=1 |
| `b3_self_ret` | `ct` + `grep &_self` | 生成 `return (struct HttpRequest_iface){ (void *)&_self, … };` |
| `b4_local_ret` | `ct` + `cc` + run | `1 200`（期望 `0 201`）；生成 `(void *)&r` |
| `f1b_inherent_subscript` | `ct` rc=0；`cc` | `subscripted value is not an array, pointer, or vector` |
| `f3_convert` | `ct` rc=0；`cc` | warning `incompatible pointer types initializing 'char *' …` |

### 5.2 多单元探针（`/tmp/ctgap/j/<id>/`）

| 探针 | 命令 | 原始结果 |
| --- | --- | --- |
| `j10b`（树在 build 模式） | `ct build src/main.ct -o out` | `Vec.h:31:20: error: field has incomplete type 'struct JsonRef'`，rc=1 |
| `j2`（树类型进 `.h.ct`） | 同上 | 同上（同一根因） |
| `j16`（`Vec<JsonRef> *` 进 `.h.ct`） | 同上 | rc=0；run rc=0（Vec 侧可导出） |
| `j12b`（`Vec<JsonRef *>`） | 同上 | rc=0；`1 2` |
| `j13b`（`Vec<JsonRef>`） | 同上 | rc=0；`1 2` |
| `j14b`（`Map<char*, JsonRef *>`） | 同上 | rc=0；`1 2` |
| `j15b`（`Map<char*, void *>`） | 同上 | rc=0；`1 2` |
| `d4`（跨单元 Drop） | 同上 + run | rc=0；只输出 `done` |
| `m1`（`.m.ct` import `.h.ct`） | 同上 `[-I src]` | `cannot resolve import 'http/http'` / `a .m.ct unit can only import another .m.ct unit`，rc=1 |
| `j3`（`pub enum` 进 `.m.ct`） | 同上 | `a .m.ct unit cannot declare a type`，rc=1 |
| `d1`（`#define` 不进头） | 同上 | `use of undeclared identifier 'JSON_TAG_NUM'`，rc=1 |
| `d2b`（`pub enum` 进 `.h.ct`） | 同上 | rc=0（裸名可用） |

### 5.3 环境注意

把 `ct` 复制出安装布局后，单文件模式可能找不到 `lib/std`：此时 `Map *m;` 会**静默放行**并发射
`Map * obj;`（`cc` 才报 `unknown type name`），`Vec<int> v;` 报 `use of an undeclared variable`。
设 `CT_STD_DIR=<repo>/lib/std` 后恢复正常诊断。同一份代码在不同环境下会得出相反结论——这是
ct-json 两席评审分歧（D-2）的来源，也是本文所有多单元探针都固定该变量的原因。

---

## 6 与七域总清单的对应

| 本文 | 七域清单 | 差异 |
| --- | --- | --- |
| J-1 | C 域新增（见总清单 C-4） | 总清单写作后才定位到「`Map` 条目结构」这个根因；总清单已同步 |
| J-2 | E-2 | 同一事实；本文补了「`Str` 值可用、只有键不行」 |
| J-3 | G-2 + G-4 | 本文把「跨单元空桩」与「指针字段胶水」合并成一条交付判断 |
| J-4 | G-3 | 同一事实；本文补了「返回类型位置是硬错」 |
| J-5 | F-1 | 同一事实；本文补了「内建 `Vec`/`Map` 下标可用、写形态文案」 |
| J-6 | G-1 | 同一事实 |
| N-6 / N-7 | E-1 / E-2 的反面 | 总清单按能力域把「数值」「文本」单列；本文核实后判为包的选择，不是语言缺口 |
| N-9 | 无（总清单 G 域只记了「字段链可用」） | 本文定位到「跨 union 成员」这一精确条件，建议回填总清单 |
| N-10 | B-1 / B-3 / B-4 | 同一组；本文只关心它是否阻塞 ct-json，结论是不阻塞（树式 API） |
