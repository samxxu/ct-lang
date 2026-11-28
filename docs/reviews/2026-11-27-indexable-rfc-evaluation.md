# 评审记录：RFC-0000「结构化数据下标访问协议（Indexable）」评估

| 项 | 值 |
| --- | --- |
| 被评审对象 | 外部来稿《RFC-0000：结构化数据下标访问协议（Indexable Trait）》，2026-11-27 |
| 评审人 | REQ（主张人） |
| 结论 | **有条件接受为设计输入；不按原文立项**（约 55% 是现状、25% 与 Ct 取舍冲突、20% 是真增量） |
| 处置去向 | 语言侧增量：**I1 纳入 v1.2 的 S8a（可砍）**、**I2 不进 v1.2**（架构级，单独立项）；多格式统一层转为包提案，见 [ct-pkg-structured-data-access](../proposals/ct-pkg-structured-data-access.md)。所有者的既有裁定不变：不再单开 v1.3–v1.5/v2.0 规划 |
| 证据 | [spec §4.64](../language-spec.md)、[D-028](../decisions/D-028.md)、[D-029](../decisions/D-029.md)、[D-013](../decisions/D-013.md)、本文件 §6 的实机探针 |

## 1 事实核对：已有能力（不必重做）

| 来稿诉求 | Ct 现状（v1.2 S2 之后） |
| --- | --- |
| `o["k"]` → `get(k)`；`o["k"] = v` → `set(k,v)` | 已实现：固有 `impl` 的 `get` / `set`，见 [spec §4.64](../language-spec.md) |
| 链式 `o["a"]["b"]` | 已实现；`x[k].field`、`x[k].m()` 亦可（LANG-29 S3） |
| 键类型灵活 | 已实现：键=参数类型；同类型可并存 `get(int)` 与 `get(char *)`，C 符号自动去歧义 |
| 动态键 `o[var]` | 已实现（见 §6 探针：`int k` 与 `char *s` 两种变量键同时成立） |
| 无匹配时的候选诊断 | 已实现：`type 'X' has no subscript matching 'get(int)': candidates are 'char *get(char *)'` |
| 读写/借写三形态 | 已实现：`set` 缺失但 `get` 返回 `V *` 时走 `*get(k) = v` |
| `+=` / `++` / `&x[k]` | 已明确拒绝（二值化），包层写法是读回再 `set` |

来稿 P1（“定义 trait 与只读语法 + 1–2 个参考实现”）约 80% 已在 v1.2 落地。

## 2 与 Ct 取舍冲突（必须改）

| 来稿写法 | 冲突 | 建议 |
| --- | --- | --- |
| `trait Indexable { type Key; type Value; }` | Ct 明确不做关联类型 / `Self`（§4.55 边界） | 去掉关联类型；协议即固有 `get(K) -> V` / `set(K,V)` |
| 新增 `Indexable` / `IndexableMut` trait 名 | D-028 定死“只认固有 impl，trait 提供的 `get` 不算” | 不新增 trait 名；否则 `o[k]` 是否走 vtable 立刻变成 ABI 问题 |
| `obj.map(f)` 称“函子” | ① Ct 的“函子”指 D-029 的 `(A,B) => R` 签名糖；② `map` 是 Ct 关键字（`map trait … for type/instance`） | 必须换词，避免长期混淆 |
| “C 无原生 sum type，需三态” | Ct 有 ADT（S4）+ 内置 `Option<T>` / `Result<T,E>` | 缺失键返回 `Option`，不用 `NULL`/`0`/三态 flag |
| §7 要求 vtable 版本化 / ABI 标签 | 当前下标是固有方法直调，不经 vtable | 只有“接口值下标”（I2）才需要 vtable 契约 |
| “裸结构体自动实现 Indexable” | 与显式原则冲突，且字段名变字符串后重命名不报错 | 常量键必须在编译期解析到真实字段或显式映射；未知键硬错 |
| §5.6 要求规定 get 返回视图还是副本 | 已有答案：签名决定（`V` 值 / `V *` 视图）；字符串用 `Str` / `String`（D-013） | 引用现规范 |
| §9 要求“生成汇编与字段访问一致” | Ct 门禁是生成 C 逐字节 + 零告警 + goldens，无汇编基准设施 | 判据改为可验证的 C 形态：折叠后无 `get` 调用、无临时量 |

## 3 语言侧真增量（拆分）

| # | 增量 | 价值 | 风险 / 门槛 | 建议 |
| --- | --- | --- | --- | --- |
| I1 | **常量键折叠**：`p["x"]` → `p.x` | 来稿的核心卖点；Ct 确实没有 | 只认字符串**字面量**键；必须在编译期解析到字段或显式映射，未知键硬错（保住“改名即报错”）；动态键一律走 `get` | **纳入 v1.2：S8a，可砍**（排在 S8 之后；窗口不足即降到 1.2 之后，不另立版本） |
| I2 | **接口值下标**：`o[k]` 走 trait 对象 | 来稿 §7 的 ABI 讨论这时才成立 | 要定义 vtable 槽与跨单元 ABI；Ct 现为“只认固有 impl”；与 S8 的 emitter 契约正面冲突 | **不进 v1.2**；单独立项评估 |
| I3 | 多格式统一访问层 | 来稿主要动机 | **不进语言**：包层工作，语言只提供 `get`/`set` + `Option`/`Result` + `Str` | 立即交 CTPKG，见包提案 |

### 3.1 I2 的四个待裁定问题（2026-11-28，所有者未裁）

> I2 未立项。以下四问决定它"做不做、怎么做"；在裁定前不写设计、不排期。
> 裁定结果回填本节，并由 REQ 转成需求池条目。

| # | 问题 | 选项 | 影响 |
| --- | --- | --- | --- |
| I2-Q1 | **要不要做** | (a) 立项做；(b) 永久不做，接口值一律显式 `o.get(k)`；(c) 只由包层 `Value` 视图覆盖（`ct/data`），语言不加 | 决定是否进入下一窗口；选 (b)/(c) 则本节关闭 |
| I2-Q2 | **路线 A 还是 B** | A：接口值的 trait 只要有 `get(K)`，`o[k]` 就自动成立；B：复用该 `get` 槽，但要求 trait/impl **显式 opt-in**（标记或清单），不新增 trait 名 | A 零声明、但给所有 `get` 意外加语法；B 多一步声明、但避免语法外溢 |
| I2-Q3 | **只读先行还是读写同批** | (a) 只读 `o[k]`；(b) 读写同批，`o[k] = v` 需 `set` 槽与借用/所有权语义 | 写形态会牵动接口值的可变性、Drop 与借用检查，风险显著高于读 |
| I2-Q4 | **是否承诺 vtable 槽 ABI** | (a) 定义稳定的槽位号/标签，跨单元与跨版本可用；(b) 只在单次编译内生效，不承诺 ABI | (a) 需要 ABI 版本化与 emitter 契约变更；(b) 实现小，但接口库不能预编译分发 |

**裁定进度（2026-11-28，所有者逐条定）**

| 问题 | 裁定 | 说明 |
| --- | --- | --- |
| I2-Q1 | **(a) 立项做** | 随 v1.2 交付（`E-V3-9e`），`v1.2.0` 的 tag 推迟到 I1/I2 落地后 |
| I2-Q2 | **方法级 `index`（合并，取消 `Indexable`）** | 只保留一个 trait；在其 `get` 签名后写 `index` 表示"该 get 就是 `[]`"。不新增 trait、不占 vtable 槽；`index` 是上下文修饰词，其它位置仍是普通标识符 |
| I2-Q3 | **分两阶段：阶段一只读，阶段二写入** | 两阶段同属 1.2 交付；阶段一 `o[k]` 只解析 `get`；阶段二再加 `set` 的 `index` 与写语义（只读实现、所有权、失败语义、ABI 一起定）。阶段一不阻塞阶段二，也不把写风险压进同一提交 |
| I2-Q4 | 待裁 | — |

### 3.1.1 Q2 定稿样例（2026-11-28）

```ct
trait Store {
    Str get(Str k) index;     // 这个 get 就是 []
    int get(int slot);        // 普通方法，不参与 []
}

Store s = open_json(path);
Str n = s["name"];            // ok   → get(Str)
int  x = s[7];                // 硬错：没有带 index 的 get(int)
int  y = s.get(7);            // ok   → 普通调用
```

```ct
trait Table {
    Str get(Str k) index;
    Str get(int row) index;   // 两个键类型都标：按键类型分派（与 D-028 一致）
}
Table t = open_table();
Str a = t["name"];            // → get(Str)
Str b = t[3];                 // → get(int)
```

```ct
struct JsonStore use Store { ... }
impl Store for JsonStore {
    Str get(Str k) { ... }    // 实现侧不重复写 index；标记属于 trait 声明
}
```

```ct
trait Env { Str get(Str k); }     // 未标 index
Env e = ...;
Str p = e["PATH"];                // error: trait 'Env' 的 get(Str) 未标 'index'
Str q = e.get("PATH");            // ok
```

```ct
struct Config { Str name; int port; }
Config c = load();
Str n = c["name"];                // I1：字面量 + struct → 折叠成 c.name（无需标记）

Store s = open_json();
Str m = s["name"];                // I2：接口值 → vtable 的 get(Str)
```

**必须先钉住的边界（D-028 的"只认固有 impl"）**：`impl Store for JsonStore` 是 trait impl，
因此具体类型 `JsonStore j; j["x"]` 今天不成立（它只认固有 `impl JsonStore { get }`）。
ADR（`D-034`）必须在两个口径里选一个：

- (i) 保持分裂：具体类型只认固有 impl，接口值只认 trait 的 `index`；
- (ii) 统一：具体类型先找固有 `get`，没有再找 trait 里标 `index` 的 `get`（扩展 D-028，需负例）。

## 4 来稿 §13 八问的 Ct 侧答复

| 问题 | 答复 |
| --- | --- |
| Q1 拆分 | 已分离；但“函子/`map`”两个词已被占用，来稿需换名 |
| Q2 键类型 | 已定：键=参数类型，整数/字符串/枚举可并存，不做隐式转换 |
| Q3 动态键 | 已支持；静态折叠只认字面量键，动态表达式走运行期 `get` |
| Q4 缺失语义 | 不用三态；返回 `Option<T>`（S6 后可升级为泛型 ADT）或 `Result` |
| Q5 所有权默认 | 签名决定；字符串视图 `Str`、拥有 `String`（D-013） |
| Q6 ABI | 当前设计不需要；I2 落地前不承诺跨版本 ABI |
| Q7 约束交集 | Ct 只支持单 bound；表达“可索引且可映射”需先扩多 bound，另立特性 |
| Q8 命名 | 不新增 trait 名，沿用固有 `get`/`set`；若必须命名，避开 `map` / `Functor` |

## 5 处置建议

1. **不按原文立项**。语言侧只接受 I1，按 [lang31-const-key-fold-construction](../design/lang31-const-key-fold-construction.md) 的施工卡排进 v1.2 的 **S8a**（可砍）；I2 不进 1.2；
2. **优先级**：I3（包，立即）> I1（v1.2 S8a，可砍）> I2（不进 1.2，单独立项）；
3. 术语与拼写：`Functor`/`map` 让开；全文用 **Ct**（DOC-94）；
4. 正式流程走本仓 `issues/` + `docs/proposals/` + ADR，不用自带 `RFC-` 编号体系（I1 已立 [LANG-31](../../issues/lang/lang-31-const-key-fold.md)）。

## 6 证据：动态键与重载探针（2026-11-27）

```ct
struct Bag { int n; }
impl Bag {
    int get(int k) { return k + self->n; }
    void set(int k, int v) { self->n = v; }
    int get(char *k) { return k[0] + self->n; }
}
int main(void) {
    Bag b = { 1 };
    int k = 2;
    char *s = "A";
    b[k] = 5;
    printf("%d %d %d\n", b[k], b["Z"], b[s]);
    return 0;
}
```

实测输出 `7 95 70`：变量整数键、字面量字符串键、变量字符串键同时可用，且按静态类型选中各自的重载。
（种子编译器构建方式见 [selfhost/README](../../selfhost/README.md)。）

## 7 风险补充（来稿 §14 之外）

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| R5 字段重命名失效 | 字符串键把字段名变成“数据”，重命名不再报错 | I1 的常量键必须在编译期解析到字段，未知键硬错 |
| R6 动态路径成本 | 走 vtable 后 `o[k]` 变成间接调用，“零开销”只对 I1 成立 | I2 单独立项时重写性能预算 |
| R7 与 `Option`/ADT 时序 | I3 先落地会把 `Option` 用户面固定；S6 若改 ADT 需同步 | 包接口按“`Option` 或显式查询”写，不假设底层布局 |

## 8 关联

- [ct-pkg-structured-data-access](../proposals/ct-pkg-structured-data-access.md)（I3 的包提案，交 CTPKG）
- [spec §4.64](../language-spec.md)（自定义下标协议）
- [D-028](../decisions/D-028.md)（下标协议 ADR）、[D-029](../decisions/D-029.md)（函子签名糖）
- [adt-patterns §10.5](../design/adt-patterns.md)（`Option` / `Result` 的命名未决）
- [feature-examples-matrix §1](../planning/feature-examples-matrix.md)（下标与函子的样例现状）
