# LANG-12 · 自定义类型没有属性访问协议（`doc.server.host` 落到 C 字段规则）

| 项 | 值 |
| --- | --- |
| 模块 | lang（表达式 / 成员访问协议） |
| 严重度 | Medium |
| 优先级 | **P2** —— ct-json 的可读性诉求；有库层绕法，不挡 0.1.0 |
| 状态 | rejected |
| 处置证据 | **rejected**（2026-11-15 重排：与 PH-56 同判。缺键时点访问是空指针解引用，无法安全定义；安全形态 `m["k"]` / `m["k"]?.c` 已可用） |
| 锚点 | `v0.53.1`（`3337ac7a`） |
| 类型 | **从未支持（需求）** |

## 现状

对自定义类型写 `doc.server.host`（`doc` 是 `struct JsonRef` 或动态 JSON 句柄）时，
CT 按 C 的字段规则原样发射，**不检查字段是否存在**；`cc` 报：

```text
a.ct:12:14: error: no member named 'server' in 'struct JsonRef'
   12 |     return r.server.host;
1 error generated.
```

CT 本身 rc=0（成员存在性属 `Z5` 的 opt-in 类型检查范围之外），所以用户看到的是
「编译器放行、C 编译器拒绝」，而不是一条语言级诊断。

## 为什么不是 bug

- 仓库没有「属性访问协议」条款；bindings 的基线写法是 `union` + `int tag`，
  访问写 `p->tag` / `(*p).v.i`：[bindings-and-patterns.md:10-47](../../docs/bindings-and-patterns.md#L10-L47)。
- `?.` 只做**字段**访问（[language-spec.md:2652-2667](../../docs/language-spec.md#L2652-L2667)）；
  `into` 只做块内字段赋值（[:2375-2390](../../docs/language-spec.md#L2375-L2390)）。
- 规约没有把 `doc.<key>` 定义成 `get("<key>")` 的糖；PH-52 只做 `[]`，且只按「名 + 参数个数」
  匹配（[:2628-2630](../../docs/language-spec.md#L2628-L2630)）。

所以这是新需求：要么在语言层加「属性 → get」协议，要么明确「JSON 访问只用 `[]` / `get`」。

## 需求场景

```ct
struct JsonRef { int tag; /* ... */ }
/* 期望 */
int port = doc.server.port;
```

今天可写的等价形态（逐跳落变量，规避 SH-73 与 LANG-5）：

```ct
JsonRef server = doc["server"];
JsonRef port = server["port"];
int n = port.as_int();
```

或库层 `json_get(doc, "server.port")`。

## 可选修法

### A. 语言层属性协议（中）

- 只有声明了固有 `get(char *)` 的类型，才把 `.name` 脱糖为 `get("name")`；
- 真实字段优先：字段存在时仍走字段，避免与 C 布局冲突；
- 逐跳 `a.b.c` 需要与 J-6 的临时值物化共用 `__ct_tmpN`；
- 需要 `ct` 侧保留「类型 → 是否有 get」的符号信息；
- 回归：`doc.server.host` 编译并返回预期值；`doc.kind`（真实字段）仍走字段；
  无 `get` 的类型报错并提示声明 `get`。

### B. 库层路径函数（小，推荐先做）

- `json_get(root, "server.port")` / `json_get_seg(root, segs, n)`；
- 不动编译器；需要定义 `.` / `[` 的转义；
- 回归：路径含 `.` 的 key 走转义；缺键返回 0/NULL；逐段访问无递归崩溃。

## 不做什么

- 不把 `?.` 改写成 key 访问：`?.` 的语义是字段访问，JSON key 不是字段
  （[ct-json-proposal-review.md:145](../../docs/review/ct-json-proposal-review.md#L145)）。
- 不引入隐式 `Str` / `char *` 转换（见 LANG 能力缺口 J-9）。
- 不改 C 字段访问的语义；属性协议只能是「字段不存在时的回退」。

## 与其他条目的关系

- 多级 `doc["a"]["b"]` 仍受 PH-52 单层限制（`REQ-JSACCESS-1` / `REQ-INDEX-1`）；
- `doc["server"].has(k)` 仍受 SH-73 的接收者形态限制（[sh73:59-69](../selfhost/sh73-temp-receiver-dynamic-dispatch.md#L59-L69)）；
- `doc["server"].v`（下标结果取字段）是 LANG-5 的静默坏 C，与本条不同：那条是**已有字段**的访问守卫，
  本条是**不存在的 key 当字段**的新协议。

## 回归用例应断言

- 若走 A：`doc.server.host` 编译、运行返回预期字符串；真实字段零回归；
  无 `get` 的类型给「declare 'V get(char *)' in impl X」类提示；
- 若走 B：`json_get(doc, "server.port")` 返回预期值；缺键返回 0；`.` 转义用例通过。
