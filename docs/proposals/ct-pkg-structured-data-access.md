# 提案：`ct/data` —— 结构化数据统一访问层（投递 CTPKG）

| 项 | 值 |
| --- | --- |
| 提案人 | Ct 项目 REQ（主张人） |
| 日期 | 2026-11-27 |
| 状态 | **待 CTPKG 评估**（不在本仓实现；本仓只提供语言侧协议） |
| 目标仓 | CTPKG（外部包仓），建议包名 `ct/data`（官方 publisher `ct`） |
| 上游评审 | [RFC-0000 评估](../reviews/2026-11-27-indexable-rfc-evaluation.md)（语言侧结论：语法与协议已存在，统一访问层属包层） |
| 依据 | [spec §4.64](../language-spec.md)（自定义下标）、[D-028](../decisions/D-028.md)、[D-013](../decisions/D-013.md)、[spec §4.70](../language-spec.md)（`String` / `Str`） |

## 0 一句话

语言侧已经提供「按键访问」的语法与协议（`v["k"]` → 固有 `get`/`set`，按参数类型分派），
**统一访问层是包的工作**：定义一个只读的 `Value` 视图，让 JSON / 环境变量 / 命令行 / 后续的
YAML、TOML、DB 行共用同一套读取代码。本提案不要求任何新的语言语法。

## 1 动机与非目标

**动机**：外部来稿（RFC-0000）列出的五类痛点是真实的——每格式一套 API、调用方被格式绑定、
嵌套访问可读性差、跨语言绑定要手写胶水、AST 访问重复。语言侧不该内建 JSON 语义，但这些
痛点可以在一个包里收敛。

**非目标**：

- 不改 Ct 语法、不新增 trait、不要求 vtable 版本化（下标是固有方法直调）；
- 不做隐式类型转换、不做 JS 原型链 / `typeof`；
- 不替代解析库（cJSON / jansson）本身，只定义**访问层**与适配协议；
- 不做写回同一套 API（P1 只读；写回用各格式自己的 writer）。

## 2 与语言的分工

| 层 | 负责 | 现状 |
| --- | --- | --- |
| 语法 `v[k]` / `v[k] = x` | 语言（S2 / D-028） | 已实现：固有 `impl` 的 `get` / `set`；键=参数类型；只支持 `=`；`+=`/`&v[k]` 硬错 |
| 缺失 / 错误 | 语言提供 `Option` / `Result`；包决定返回哪个 | `Option` / `Result` 是内置泛型 struct（字段 `has`/`value`、`ok`/`err`） |
| 文本 | 语言提供 `Str`（借用视图）与 `String`（拥有） | 已实现（D-013） |
| 键类型 | 字面量 `"k"` 的静态类型是 `char *`；变量可以是 `Str` | 包要**同时**声明 `get(char *)` 与 `get(Str)` 两个重载（D-028 允许并存） |

## 3 API 草案（P1）

```ct
import data::json;

Result<Doc, ParseError> r = Json.parse(src);      // src: Str
if (!r.ok) { printf("%d:%d %s\n", r.err.line, r.err.col, r.err.msg.cstr()); return 1; }
Doc d = r.value;                                    // 拥有源缓冲
Value root = d.root();                              // 借用视图，零分配

Value port = root["port"];                          // char * 字面量 → get(char *)
if (port.kind == Kind.int) {
    printf("%d\n", port.as_int());
}

Str host = root["host"].as_str();                   // 借用，不复制
int n = root["list"].len();                         // 数组长度
Value first = root["list"].at(0);                   // 下标访问数组元素
```

### 3.1 `Value`

```ct
enum Kind { missing, null, bool, int, float, str, array, object }

pub struct Value {
    Kind kind;
    // 实现细节由包决定：视图指针 + 长度 / 数值载荷 / 子表偏移
}

impl Value {
    Value get(char *key);      // v["k"]
    Value get(Str key);        // v[k]（变量键）
    Value at(int i);           // 数组元素；越界返回 missing
    int   len();               // 数组/对象元素数；其它返回 0
    bool  has(char *key);
    int   as_int();            // 仅在 kind == int 时有定义
    double as_float();
    Str   as_str();            // 借用；非 str 返回空视图
    bool  as_bool();
}
```

- `kind == missing` 表示「键不存在 / 越界」；**不**用 `NULL`、`0` 或空字符串兼表；
- `null` 与 `missing` 分开（键存在但值为 null）；
- `as_*` 是**无检查**的取值，`kind` 判断由调用方做；需要错误通道时提供
  `Result<int, TypeError> try_int()` 一类（P2）；
- `Value` 是**值语义的小视图**（不拥有数据），可自由复制、比较 `kind`；
- 写形态（`v["k"] = x`）P1 不做。

### 3.2 所有权

| 对象 | 所有权 | 说明 |
| --- | --- | --- |
| `Doc` | 拥有源缓冲（`String` 或 `Vec<u8>`） | 解析时复制或接管输入 |
| `Value` | 借用 `Doc` | 不能比 `Doc` 活得久；`Doc` 释放后 `Value` 悬垂——文档必须写明，P2 可评估生命周期标注 |
| `Str`（`as_str`） | 借用 `Doc` | 与 `Value` 同寿命 |
| 解析错误 | `Result` 载荷 | 行 / 列 / 消息；消息用 `Str` 借用源 |

## 4 性能预算（可验证）

| 场景 | 要求 | 判据 |
| --- | --- | --- |
| 读取 | 零分配（除 `Doc` 解析本身） | 生成 C 里读取路径无 `malloc` |
| 对象查找 | O(1) 哈希（小对象可线性，阈值写进文档） | 基准：1k 键查找 |
| 链式访问 | 不产生中间对象 | `Value` 是视图，天然满足 |
| 数字精度 | 整数 64 位；浮点按 `double`，精度损失文档写明 | 解析/回写往返夹具 |

## 5 格式适配与路线

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| **P1** | `ct/data` + `value` + `json`（只读）+ `env`（`Str` 环境变量）+ `cli`（`--key=value`） | 同一段读取代码跑通 JSON / env / CLI 三源；`Value` 接口不变 |
| P2 | 错误通道（`try_*`）、写回（各格式自己的 writer）、cJSON / jansson 适配（`.m.ct` / shim） | 适配层不把 `FILE*` 泄进公开接口 |
| P3 | YAML / TOML（可选）、DB 行（`row["col"]`） | 只新增后端，不改 `Value` |
| P4 | AST 场景样板（用 `ct/data` 的 `Value` 读 `--emit-model` 输出） | 与 `ct-model` 的字段名对齐 |

**严格边界**：包源码最好做到 `ct.pkg` `c-boundary = strict`；适配 cJSON/jansson 的单元用
`.m.ct` / shim 显式声明，不靠 `allow` 整包放行（与 Ct S9 的方向一致）。

## 6 CTPKG 侧交付物

| 项 | 要求 |
| --- | --- |
| 包名 | `ct/data`（官方 publisher；若 CTPKG 更偏好 `ct/conf`，只影响命名） |
| 模块 | `data::value`、`data::json`、`data::env`、`data::cli`（P1） |
| `ct.pkg` | `name`、`version`（semver）、`c-boundary` 键、`leaks = error` |
| 测试 | 解析 / 缺失 / 空值 / 越界 / 重复键 / 数字精度 / 非法输入（`Result.err`） |
| 文档 | 包 README：三源同码示例、零分配说明、`Value` 生存期边界、与 C 适配层的关系 |
| 发布 | tag `ct/data/v<x.y.z>`、索引条目、digest；**不**在本仓或 Ct 编译器内建加载 |

**验收命令（Ct 侧可复现）**：

```sh
ct get ct/data
ct build examples/data_read.ct -o /tmp/data_read && /tmp/data_read
```

## 7 与语言侧的关系（不阻塞）

| 语言侧事项 | 状态 | 对包的影响 |
| --- | --- | --- |
| `v[k]` / `v[k]=v` 协议 | 已实现（S2） | 包直接可用 |
| 常量键折叠 `p["x"]`（I1） | v1.3 候选 | 只影响静态 struct 场景，不影响 `Value` |
| 接口值下标（I2） | v1.3+ 候选 | 若做，`Value` 可以不改；包不依赖 |
| `Option`/`Result` 升级为泛型 ADT（S6） | 设计中，命名未决 | 包按字段（`ok`/`err`/`has`/`value`）使用；升级需一次性迁移，已在 S6 评估 |
| `Str.print()`（LANG-30） | v1.2 必做 | 包 README 的示例输出会因此更简洁，不阻塞 |

## 8 开放问题（CTPKG 裁定）

1. 包名 `ct/data` vs `ct/conf`；`Value` 是否公开（建议公开，便于用户写自己的后端）。
2. 重复键：首个 / 末个 / 报错？（建议报错，`Result` 可表达）
3. 对象键序：插入序（建议）还是哈希序；影响 `foreach` 输出稳定性。
4. 数字：整数溢出与浮点精度策略；是否提供 `as_i64`。
5. 适配层：cJSON / jansson 是 P2 还是先做自有解析器（建议自有解析器先行，避免 ABI 绑定）。
6. 生命周期：`Value` 借用的生存期是否需要在文档用「显式约定」写死，还是等语言将来提供标注。

## 9 关联

- [RFC-0000 评估](../reviews/2026-11-27-indexable-rfc-evaluation.md)
- [spec §4.64](../language-spec.md)（自定义下标协议）、[D-028](../decisions/D-028.md)
- [spec §4.70](../language-spec.md)（`String` / `Str`）、[D-013](../decisions/D-013.md)
- [ct-pkg-index-proposal](ct-pkg-index-proposal.md)、[ct-pkg-package-maintainer-rules](ct-pkg-package-maintainer-rules.md)（发布与索引规则）
- [feature-examples-matrix](../planning/feature-examples-matrix.md)（`Map` / 下标样例现状）
