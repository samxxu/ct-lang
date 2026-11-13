# CT JSON 实现的生产可用性评估

> 评估对象：`examples/json/`（`json.ct` 2286 行 / 67,182 B，`README.md` 225 行，`DECISIONS.md` 131 行，`json.expected.out` 135 行）
> 评估日期：2026-11-12　代码基线：工作区当前状态（`CTC_VERSION` = 0.30.0；`examples/json/**` 未被任何会话改动）
> 评估方式：只读审查 + 在 `/tmp` 下编译实测（未改动、未提交仓库内任何被跟踪文件）

---

## 0 结论摘要

| 问题 | 结论 |
| --- | --- |
| 能否用于正式产品 | **分场景**：自家服务 + 可控输入 **可以**；对外暴露 + 不可信输入 **不建议直接上线**（解析器本身不崩，但语义缺口会让上层背债） |
| 能否替代 cJSON | **不能**。它是"校验器 + 只读视图 + 写入器"，cJSON 是"可变更 DOM + 多形态打印 + C ABI 库"；两者能力集几乎不重叠 |
| 是否放进 ct-pkg | **应进 ct-pkg，但不该进 `std`，也不该现在放**。建议补齐 P0/P1/P2 后，以独立包 `json` 发布（版本 0.x），与 `std` 解耦 |

三条最硬的反面证据（均为实测，非推断）：

1. `at()` 全量遍历 20,000 元素数组耗时 **1,240 ms**（1,000 → 2.7 ms，规模 ×20、耗时 ×459，确认 O(n²)）。
2. 13 个双精度字面量中只有 **7 个**与 `strtod` 逐位相等；`0.30000000000000004` 读成 `0.3000000000000001`。
3. `doc.depth_limit` 可被调用方调高，**110,000 层嵌套触发 SIGSEGV（退出码 139）**；默认 64 层是安全点，但不是硬上限。

---

## 1 实现定位

| 项 | 事实 | 证据 |
| --- | --- | --- |
| 形态 | 单文件 CT 程序（库 + demo + 自测同文件） | `json.ct:1`（`//@ct-requires: ct-ast`）、`README.md:29-30` |
| 读取模型 | 一次性全量校验 + `JsonView{start,len}` 只读切片，查找时重扫 | `json.ct:126-141`、`json.ct:1590-1623` |
| 写入模型 | 调用方给缓冲区，`JsonOut` 追写，深度栈在结构体内 | `json.ct:92-101`、`json.ct:690-704` |
| 分发 | 每种 kind 一个空 ops 结构体 + 泛型 `JsonValue` 接口值 | `json.ct:884-918`、`json.ct:1536-1585` |
| 分配 | 全文无 `malloc/free/realloc/calloc`（grep 零命中） | `json.ct` 全文 |
| 依赖 | 仅 `<stdio.h>` / `<string.h>` / `<float.h>` | `json.ct:28-30` |
| 测试形态 | 自测写在 `main` 里，门禁按 `examples/*/*.ct` 编译运行比对 golden | `json.ct:2275-2286`、`test/run.sh:193-236` |
| golden 规模 | **125 条 `ok` 断言** + **20 条错误用例**（逐条核对码/偏移/行/列） | `json.expected.out`、`json.ct:2070-2273` |

**实测门禁结果**（`ct-ast` 编译 → `cc -Wall -Wextra -std=c99 -O2` → 运行 → diff）：

```
COMPILE_OK 生成 C 2704 行
GOLDEN_MATCH
exit=0，all checks passed，grep -c '^ok ' = 125
```

**文档缺陷（顺带发现）**：`README.md:11` 写的构建命令是 `./ctc examples/json/json.ct`，实测被 L0 拒绝：

```
examples/json/json.ct:1:1: error: unsupported declaration of interface type 'JsonValue'
```

必须走 `ct-ast`（`test/run.sh:203-217` 的 `ensure_ast` + `ast_example_status` 路径）。README 的"零依赖、随便编"这一句是过时的。

---

## 2 能力对照表

支持度口径：**支持** = 该维度在实现里完整且实测通过；**部分支持** = 有实现但有明确缺口或需要在文档里声明前提；**不支持** = 无此能力。

| # | 维度 | 支持度 | 证据（文件:行） | 实测补充 |
| --- | --- | --- | --- | --- |
| 1 | RFC 8259 合规 | **部分支持** | 词法 `json.ct:193-314`；转义解码 `json.ct:448-527`；控制字符拒绝 `json.ct:206-208`；UTF-8 不校验 `README.md:105-107`、`DECISIONS.md:99-106` | 裸 `0xFF 0xFE` 被接受并原样输出；BOM 被拒（`JSON_ERR_CHAR`）；`\uXXXX`/代理对正确 |
| 2 | 数字 | **部分支持** | 词法 `json.ct:267-314`；`as_int` `json.ct:1234-1283`；`as_double` `json.ct:1284-1383`（19 位有效数字 1316-1321、指数钳 ±400 1358-1362、逐次 ×/÷10 1364-1377） | 7/13 字面量 bit-exact；`1.0`/`1e3` 不能取 int；`-0` → int 0 / double -0.0 |
| 3 | 结构 | **支持（有边界）** | 深度检查 `json.ct:324-326`、`370-372`；默认 64 `json.ct:68`；可调 `json.ct:443-445`；输出深度 64 `json.ct:69`、`694-697` | 64 层接受、65 层拒绝（`json.ct:1985-1996`、`2238-2250`）；`depth_limit=10^6` 时 110k 层 **SIGSEGV** |
| 4 | DOM 能力 | **不支持** | 只有 7 个 kind `json.ct:33-40`；`kind/count/member/at` 全是重扫 `json.ct:964-1114`；无 setter `DECISIONS.md:69-76`；无深拷贝（`emit` 是原字节搬运 `json.ct:929-937`） | 重复键 `count` 计 2 次、`member` 取最后（实测） |
| 5 | 序列化 | **部分支持** | 原子写 `json.ct:740-873`；转义 `json.ct:706-735`；`%.17g` `json.ct:817-831`；往返仅 `emit` 路径 `json.ct:2252-2269` | 紧凑输出可字节级往返；无缩进；`1e300` → `1.0000000000000001e+300`；`as_string` 结果含 NUL 时写入器截断 |
| 6 | 错误处理 | **部分支持** | 单码 + 偏移 `json.ct:1590-1623`；行列按需计算 `json.ct:1630-1653`；码表 `json.ct:43-53`；文案 `json.ct:1756-1783` | 列按**字节**计（`{"é":x}` 报 column=7）；出错后 `root()` 为 MISSING，无部分结果、无恢复 |
| 7 | 内存 | **支持（零分配）** | 无分配（grep）；视图借用调用方文本 `json.ct:137-141`；失败路径无资源 | ASAN/UBSAN 全量 golden 干净；60,000 次随机/变异 fuzz 无崩溃、无泄漏报告 |
| 8 | 性能量级 | **部分支持** | 解析单遍线性 `json.ct:317-431`；查找 O(n) `json.ct:997-1027`、`1084-1114`；写入按字节追加 `json.ct:644-656` | 解析 ≈ **1.9 GB/s**（38.9 MB / 21 ms）；`at()` 全量遍历 20k → 1.24 s；`member()` 20k 键 → 347 µs/次 |
| 9 | 工程面 | **部分支持** | demo/自测同文件 `json.ct:1785-2286`；门禁覆盖 `test/run.sh:193-236`；无 JSON 专属 fuzz（`test/fuzz/run.sh:3-8` 只跑编译器） | 无基准脚本；无 MSVC 验证；API 未版本化 |
| 10 | 与 C 互操作 | **不支持（C 侧）** | 生成符号全 `static`，定位为"复制进程序"而非可链接库 `README.md:29-30`；跨单元需 `pub` + 单元拆分（实测） | ct 侧跨单元消费**可行**（见 §4.10）；C 侧须等 Phase 39 `ct build --lib`（`docs/roadmap.md:54`） |

---

## 3 逐项详述

### 3.1 RFC 8259 合规（部分支持）

有实现且正确的部分：

- 字符串词法完整：8 个短转义 + `\uXXXX`，且**校验**代理对——高代理必须紧跟 `\uDC00-\uDFFF`，孤立高/低代理分别报 `JSON_ERR_SURROGATE`（`json.ct:232-261`）。负例逐条覆盖（`json.ct:2169-2191`）。
- 解码侧把码点编码成 1–4 字节 UTF-8，实测 `\u0041`/`\u00e9`/`\u20ac`/`\ud83d\ude00` 全部正确（`json.ct:1962-1975`）。
- 字符串内裸控制字节 `< 0x20` 拒绝（`json.ct:206-208`），错误码 `JSON_ERR_STRING`。
- 未知转义、坏十六进制分别报 `JSON_ERR_ESCAPE` / `JSON_ERR_UNICODE`（`json.ct:222-231`）。

缺口（都是**已声明**的选择，不是 bug）：

- **不校验输入 UTF-8**：`>= 0x80` 的字节原样透传（`json.ct:209-211`）。实测 `"<0xFF><0xFE>"` 解析成功且 `as_string` 原样吐出两个字节。对"自家服务、上游已保证 UTF-8"无碍；对"对外暴露"意味着**这个库不能承担 UTF-8 合法性判定**，下游若假定 UTF-8 会在别处炸。
- **不跳 BOM**：实测 `EF BB BF {}` 报 `JSON_ERR_CHAR`（offset 0）。调用方必须自己剥。
- 允许裸 `0x7F`（DEL）——这符合 RFC 8259（只禁 `< 0x20`），实测接受，不是缺陷。

### 3.2 数字（部分支持，精度是主要风险）

- 词法严格按 RFC 8259：`-? (0|[1-9][0-9]*) (. [0-9]+)? ([eE][+-]?[0-9]+)?`。前导零（`01`）、`1.`、`.5`、`+1`、`1e` 全部在**词法层**拒绝并有偏移断言（`json.ct:2133-2162`）。这一点比不少手写解析器严。
- `as_int` 只接受纯整数 token，`1.0` / `1e3` 报 `JSON_READ_INTEGER`，越界报 `JSON_READ_RANGE`，int64 两端精确（`json.ct:1234-1283`，测试 `1930-1941`）。
- `as_double`：取最多 19 位有效数字（`json.ct:1316-1321`），指数钳在 ±400（`1358-1362`），然后**逐次乘/除 10**（`1364-1377`）。溢出检测只在乘方向（`1368-1371`），下溢直接归零。
- 实测精度（对照 `strtod`，节选 8 个；完整语料 13 个中 7 个逐位相等）：

| 字面量 | 本实现 | strtod | 结果 |
| --- | --- | --- | --- |
| `0.1` | 0.10000000000000001 | 同 | 相等 |
| `3.141592653589793` | 3.1415926535897931 | 同 | 相等 |
| `9007199254740993` | 9007199254740992 | 同 | 相等（都丢末尾 1） |
| `1.234567890123456789` | 1.2345678901234565 | 1.2345678901234567 | **差 1 ULP** |
| `0.30000000000000004` | 0.3000000000000001 | 0.30000000000000004 | **不同** |
| `1.0000000000000002` | 1.0000000000000004 | 1.0000000000000002 | **不同** |
| `2.2250738585072014e-308` | 2.2250738585072029e-308 | 2.2250738585072014e-308 | **不同** |
| `1.7976931348623157e308` | 1.7976931348623145e+308 | 1.7976931348623157e+308 | **不同** |

  **13 个样本中 7 个逐位相等**。这不是"末位偶有差异"：`1.0000000000000002`（即 `0x1.0000000000001p+0`，`1.0` 的下一个可表示值）被读成 `1.0000000000000004`，**错 1 个 ULP**；`1.234567890123456789` 也差 1 个 ULP。凡是"用 JSON 传浮点再比对"的场景（配置哈希、金额、坐标、指数回测）都会踩。
- 结论：**整数可信，实数不可信**。需要精确时只能靠 `offset_of`/`len_of` 拿原文自己转（`json.ct:1725-1740`，`README.md:101-104`）。
- 大整数（> int64）：`as_int` 报 `JSON_READ_RANGE`；`as_double` 走 19 位截断 + 指数近似。没有十进制/大整数类型。

### 3.3 结构（支持，但有栈溢出边界）

- 深度计数在 `{` / `[` 入口检查（`json.ct:324-326`、`370-372`），默认 64（`json.ct:68`），`doc.depth_limit` 可在 parse 前覆盖（`json.ct:443-445`、`README.md:94-95`）。
- 实测：64 层接受、65 层报 `JSON_ERR_DEPTH` 且 offset=64（与 golden 一致）。
- **风险**：`depth_limit` **没有任何上限钳制**，而解析是递归下降（`json.ct:351`、`378`）。实测在同一台 8 MB 栈机器上：

| depth | depth_limit | 结果 |
| --- | --- | --- |
| 1,000 | 1,000,000 | rc=1（接受） |
| 100,000 | 1,000,000 | rc=1（接受） |
| 110,000 | 1,000,000 | **SIGSEGV，退出码 139** |

  即：默认配置安全，但"为了兼容更大的文档"把 `depth_limit` 调高就会崩。若作为产品库，必须要么钳死上限，要么换成显式栈（`DECISIONS.md:90-97` 明确选了递归下降 + 上限，赌的就是调用方不调高）。
- 成员/元素数量没有独立上限，只受 `int` 长度与输入大小约束；`count` 返回 `int`，所以单容器 ≤ 2^31-1。`len` 是 `int`，**单文档上限 2 GB**（`json.ct:106`、`128`）。

### 3.4 DOM 能力（不支持）

- 只有 7 种 kind（`json.ct:33-40`）；`kind` 用首字节判定（`json.ct:940-962`）。
- 按 key 取值 `member`（`997-1027`，last-wins，必须扫完整个对象）、按索引 `at`（`1084-1114`，从头走到第 i 个）、`count`（`968-992`）——三者都是**重扫**。
- 没有迭代器句柄暴露给调用方：`JsonIter` 是文件内结构体（`json.ct:555-561`），只被内部使用；对外只能用 `count + at`，因此遍历天然 O(n²)。
- 没有原地修改、没有删除、没有插入、没有深拷贝（`DECISIONS.md:69-76`）。`emit` 只把已校验的**原始字节**搬进输出（`json.ct:929-937`），不是复制成新 DOM。
- 重复键：`count` 把重复键算两次（实测 `{"k":1,"k":2}` → count=2），`member` 返回最后一个。这与 JS/Python 一致，但与"键唯一"的严格校验预期不同。

### 3.5 序列化（部分支持）

- 紧凑输出正确：`{"name":"ct","n":42,"pi":3.5,...}` 逐字节匹配（`json.ct:2020-2024`）。
- `emit` 往返是**字节级**的：parse → emit root → 与原文 `strcmp` 相等（`json.ct:2252-2259`）。这是全库最可靠的往返路径。
- 转义完整：实测 0x01–0x1F 全部转义（`\b\t\n\f\r` 用短形式，其余 `\u00XX`），输出不含裸控制字节（`json.ct:2032-2037`；实现 `706-735`）。
- 浮点：`%.17g`（`json.ct:827`）。**输出不是最短表示**：`1e300` 输出 `1.0000000000000001e+300`，`3.5` 输出 `3.5`，`1.0` 输出 `1`。合法但不美观，且体积偏大。
- **没有缩进输出**（无 indent 分支、`README.md:108-109`），也没有"按深度美化"的入口。
- **写入器不接收长度**：`string(const char*)` 走到 NUL 为止（`json.ct:711`）。实测：`"\u0000a"` 经 `as_string` 得到 `len=1, strlen=0`，再 `string()` 输出 `""`——**数据静默丢失**；只有 `emit` 原字节路径能保住 `\u0000`。
- 输出缓冲不足时**静默截断成非法 JSON**：实测 `cap=8` 请求 21 字节，`finish()` 返回 21、缓冲区只剩 `{"abcde`（`json.ct:852-866`）。返回值语义正确（调用方可以检测），但没有任何 `JSON_EMIT_TRUNCATED` 错误码，容易漏判。

### 3.6 错误处理（部分支持）

- 模型：一个 sticky 码 + 一个字节偏移（`json.ct:1590-1623`），行列按需扫描（`1630-1653`），`json_message` 提供文案（`1756-1783`）。
- 列按**字节**：实测 `{"é":x}` 报 `column=7`（`é` 占 2 字节）。VS Code 等按 UTF-16/字符位置高亮会错位。README 已声明（`README.md:98-99`），但这是产品集成时最容易踩的一条。
- 无恢复：`parse` 失败后不保留任何部分结果，`root()` 直接返回 MISSING（`json.ct:1654-1659`），错误用例统一断言这一点（`2228-2233`）。一次只能报第一个错。
- 不区分"语法错"与"内存错"——因为没有分配，也没有 OOM 路径；11 个解析码 + 5 个读取码 + 4 个写入码（`json.ct:43-66`）。读取错误是**每次访问器调用重置**的（`json.ct:1583`），写入错误是 sticky 的（`870-872`），两套语义并存，调用方要分清。

### 3.7 内存（支持，且是它最强的维度）

- 全文零分配（`grep -n "malloc|free|realloc|calloc"` 零命中）；文档明确"零分配、无所有权"（`README.md:93-95`）。
- 谁释放：**没有人需要释放**。`JsonView` 是 `{start,len}`（`json.ct:137-141`），生命周期 = 调用方文本的生命周期；文本可以是只读字面量（`json.ct:1787-1794` 的 `k_demo_text` 就是）。
- 失败路径泄漏：**不可能**——没有资源可泄漏。依据：代码审查（无分配）+ ASAN/UBSAN 跑完整 golden（干净）+ 60,000 次 fuzz（无泄漏报告）。
- OOM 处理：无需；但输出缓冲不足会静默截断（见 §3.5），这是"无分配"模型的必然代价。
- 碎片：无。分配次数：0。换成 arena / 自定义分配器：**不适用**（没有分配点）；唯一"分配"是调用方给的输出缓冲区。
- 一个被低估的并发问题：`JsonDoc` 在**读取时也写状态**——`read_err` 被每个访问器重置/设置（`json.ct:976`、`1024`、`1583` 等）。所以"同一个 `JsonDoc` 多线程只读"是数据竞争。要么每线程各自 `parse`，要么把 `read_err` 改成返回值。这个在单线程 demo 里看不见，进库就会暴露。

### 3.8 性能量级（解析强、查找弱）

实测（`cc -O2`，macOS，单线程，3 次取最快）：

| 场景 | 数据 | 耗时 | 折算 |
| --- | --- | --- | --- |
| parse 1k 元素 | 3.9 KB | 0.004 ms | 973 MB/s |
| parse 100k 元素 | 589 KB | 0.366 ms | 1,609 MB/s |
| parse 1M 元素 | 6.9 MB | 3.53 ms | 1,954 MB/s |
| parse 5M 元素 | 38.9 MB | 21.0 ms | 1,850 MB/s |
| count 1M 元素 | 6.9 MB | 6.3 ms | 单遍扫描 |
| **`at()` 全量遍历 1k** | 3.9 KB | 2.7 ms | — |
| **`at()` 全量遍历 5k** | 22 KB | 79.7 ms | 30× |
| **`at()` 全量遍历 10k** | 45 KB | 303.6 ms | 114× |
| **`at()` 全量遍历 20k** | 92 KB | 1,240 ms | 459× |
| `member()` ×100（1k 键） | 12 KB | 1.39 ms | 13.9 µs/次 |
| `member()` ×100（5k 键） | 66 KB | 7.79 ms | 77.9 µs/次 |
| `member()` ×100（20k 键） | 277 KB | 34.74 ms | **347 µs/次** |
| `as_string` 1 MB | — | 1.89 ms | 线性 |
| writer 写 1 MB 字符串 | — | 0.64 ms | 线性 |

- 解析是**一遍线性扫描**，无逐字符 realloc（零分配），1.9 GB/s 对 JSON 属于正常偏快。
- 查找是**线性重扫**：规模 ×20 → 耗时 ×459（理论 ×400），确认 O(n²)。
- 对配置/协议报文（几十个键、几次查找）完全够用；对"大数组逐元素处理"或"大对象热查找"是灾难。`README.md:96-97` 已如实声明，但 API 没有给调用方任何"一次扫描拿全部"的入口（没有对外迭代器、没有索引）。
- 仓库内**没有 JSON 基准**（`find -iname '*bench*'` 无结果），以上数字是本次在 `/tmp` 自建 harness 测的，不可回归。

### 3.9 工程面（部分支持）

- 测试：125 条断言 + 20 条错误用例，覆盖空输入、截断、尾逗号、缺冒号、坏字面量、前导零、`1.`、`.5`、`+1`、控制字符、坏转义、坏 `\u`、孤立代理、尾随数据、65 层深度（`DECISIONS.md:125-131`）。**质量高于一般示例**。
- 但它**不是可复用的测试套件**：断言写在 `main` 里（`json.ct:2275-2286`），跟着 demo 输出走 golden。想把它用作库，测试必须重写或提取。
- fuzz：`test/fuzz/run.sh` 明确是"AST compiler 的确定性 fuzz"（`test/fuzz/run.sh:3-8`），**不覆盖 JSON reader**。本次自建 60k 轮 fuzz（随机字节 + 种子变异 + 成功后递归遍历）在 ASAN/UBSAN 下零崩溃，但这只是一次性取证，不是门禁。
- 跨平台：只用了 C99 + `stdio/string/float`，理论上 MSVC 可行，但**本机只有 clang 验证过，Windows/MSVC 未验证**；`long long` + `%lld` 需要 VS2015+。
- API 稳定性：无版本、无兼容承诺、符号全 `static`（`README.md:29-30`），文件定位是"复制进程序"，不是库。
- 文档：`README.md` + `DECISIONS.md` 质量很好（每个取舍都写了选项与代价），但 `README.md:11` 的构建命令已失效（见 §1）。

### 3.10 与 C 互操作（C 侧不支持，ct 侧可用但需改造）

- 生成的 C 全部 `static`（`README.md:29-30`，实测 `nm` 层面不可链接），C 调用方无法 `#include` + 链接；要导出得等 Phase 39 的 `ct build --lib`（`docs/roadmap.md:54`）。与 cJSON 的"`-lcjson` 即用"完全不是一个接入成本。
- **ct 侧跨单元消费，实测可行**（本次在 `/tmp` 验证）：把 `json.ct` 前 1783 行（到 `impl Json` 结束 + `json_message`）拆成 `JsonDoc.h.ct`，给 trait/struct 加 `pub`，消费者 `import JsonDoc;` 后 `struct JsonDoc doc;` 直接可用：

```
n=2 s=hi kind=1   （消费者读 {"a":[1,2],"s":"hi"} 成功）
```

  过程中撞到**两个真实的打包障碍**（都会挡在 ct-pkg 门口）：
  1. `#define JSON_OUT_DEPTH 64`（`json.ct:69`）用在了**导出结构体的字段宽度**上（`json.ct:99-100`），而生成的头文件**不带宏**，消费方编译直接报 `use of undeclared identifier 'JSON_OUT_DEPTH'`。跨单元包里，宏不能出现在公开布局里。
  2. 几乎所有函数是 `static`，`json_message` 也是（`json.ct:1756`），消费者拿不到错误文案；必须逐个标 `pub`，并决定导出面（实测生成的头文件把 7 个 `JsonObjectOps` / `JsonArrayOps` … 全部导出了，这属于实现细节泄漏）。
- 迁移成本：cJSON 的调用形如 `cJSON_Parse` → `cJSON_GetObjectItem` → `cJSON_Delete`；这里是 `doc.parse` → `doc.member` → 无释放。语义映射简单，但**每一处调用点都要改**（返回类型、错误处理、字符串拷贝语义都不同），没有兼容垫片。

---

## 4 判定 A：能否用于正式产品

### 4.1 场景一：自家服务、可控输入（配置、内部协议、日志、测试夹具）

**可以用。** 理由：

- 解析线性、零分配、深度默认有界，不会因为输入大小产生内存放大；1.9 GB/s 足够。
- 整数精确、错误定位到字节偏移 + 行列，排障体验优于"返回 NULL"。
- 无所有权、无 free，接入成本极低，不会引入泄漏面。

必须写进接入规范的前提（否则会出事故）：

1. 输入必须已保证 UTF-8（本库不校验）。BOM 必须先剥。
2. 实数一律**不要**直接 `as_double` 做等值/哈希判断；需要精确就用 `offset_of/len_of` 取原文。
3. 查找次数要控制：不要在大数组/大对象上 `count + at` 循环（O(n²)）；把"遍历一次"的活挪到解析前的字符串层，或等库补索引。
4. 不要调高 `depth_limit`（>10 万层会崩）。
5. 同一 `JsonDoc` 不要跨线程共享（`read_err` 是写状态）。
6. 输出缓冲要按 `finish()` 返回值判断是否截断，不能只看 NUL。

### 4.2 场景二：对外暴露、不可信输入（公共 API、上传文件、第三方 webhook）

**不建议直接上线。** 注意：**解析器本身是安全的**——深度默认 64、线性、零分配、60k fuzz 无崩溃，不存在"恶意 JSON 打崩进程"的已知路径。问题在语义层：

| 风险 | 后果 | 依据 |
| --- | --- | --- |
| 非 UTF-8 透传 | 下游以为拿到合法 UTF-8，入库/渲染时炸 | §3.1 实测 |
| 浮点不精确 | 签名/对账/幂等键因 1 ULP 不一致而误判 | §3.2 实测 |
| O(n) 查找 | 上层若按"取第 i 个"实现业务，单请求 CPU 可被放大到秒级 | §3.8 实测 |
| 无 schema/类型强校验 | 业务层要写大量 `kind` 判断 | `json.ct:964-1114` |
| 无恢复、单错误 | 用户拿到第一个错就结束，体验差 | §3.6 |
| 静默截断 | 若漏判 `finish()` 返回值，会返回半截 JSON 给客户端 | §3.5 实测 |
| `depth_limit` 可调 | 一旦有人"临时调大"就变崩溃点 | §3.3 实测 |

结论：**作为"解析并校验"的底层组件可用；作为"面向不可信输入的 JSON 服务层"不可用**，缺的是 UTF-8 校验、数值正确性、索引/DOM 与产品级诊断，不是缺性能。

---

## 5 判定 B：能否替代 cJSON

**不能替代。** 两者解决的问题不同：cJSON 是"可变更 DOM + 打印器 + C 库"，本实现是"校验器 + 只读视图 + 写入器"。

### 5.1 cJSON 有、它没有（按 cJSON 1.7.19 公开头文件核对，`cJSON.h` 行号见括号）

| 能力 | cJSON | 本实现 |
| --- | --- | --- |
| 建树 / 增删改 | `cJSON_CreateObject/Array/String/Number/Bool/Null`（164-186）、`AddItemToObject`（189）、`Detach/DeleteItem`（198-204）、`InsertItemInArray`（206）、`ReplaceItem*`（207-210） | 全无（`DECISIONS.md:69-76`） |
| 深拷贝 / 比较 | `cJSON_Duplicate`（212）、`cJSON_Compare`（218） | 无（`emit` 只搬字节） |
| 多形态打印 | `Print`（带缩进，129）、`PrintUnformatted`（131）、`PrintBuffered`（133）、`PrintPreallocated`（136） | 只有紧凑追写（`json.ct:740-873`）；`begin(buf,cap)` 对 `PrintPreallocated` 部分对等，但无缩进、无缓冲预分配策略 |
| 解析变体 | `ParseWithLength`（123）、`ParseWithOpts`（126，可要求 NUL 结尾 / 返回解析终点） | `parse(text,len)`（`json.ct:106`）对等 `ParseWithLength`；无"要求 NUL 结尾"与"返回解析终点"选项 |
| 错误定位 | `cJSON_GetErrorPtr`（148，全局） | 更好：码 + 偏移 + 行列（`json.ct:1624-1653`） |
| 自定义分配器 | `cJSON_InitHooks`（119） | 不适用（零分配） |
| 引用节点 / raw | `CreateStringReference`（176）、`CreateRaw`（171） | 无 |
| 类型谓词 | `cJSON_Is*`（153-162） | 有 `kind()`（等价，`json.ct:1660-1667`） |
| C ABI | 编译成 `.a/.so` 直接链接 | `static`，不可链接（`README.md:29-30`） |
| 批量数组 / 便捷 Add | `CreateIntArray` 等（183-186）、`AddNumberToObject`（229） | 无 |

### 5.2 它有、cJSON 没有（在 ct 生态里的真实优势）

1. **零分配、零所有权**：cJSON 每个节点一次 `malloc`，`cJSON_Delete` 递归释放；本实现解析 38.9 MB 文档分配 0 次。对 ct"显式生命周期、无 GC"的模型是天然契合。
2. **可直接指向只读字面量**：`k_demo_text` 是 `static const char*`（`json.ct:1787`），解析后视图仍指向它。cJSON 必须先复制/建树。
3. **整数用 `long long` 精确**：cJSON 只有一个 `double valuedouble` + `int valueint`（`cJSON.h:92` 注释也提到 `valueint` 已弃用），>2^53 的整数必然丢精度；本实现 int64 两端精确（实测）。
4. **默认深度 64 且可调**：对外入口的默认值比常见 C JSON 库更保守（cJSON 的 `CJSON_NESTING_LIMIT` 具体值本次**未验证**，见 §8）。注意这只是默认值，调高即失去这层保护（§3.3）。
5. **严格 RFC 数字词法**：前导零、`.5`、`1.`、`+1` 都在词法层拒绝并给偏移。
6. **错误模型可编程**：码 + 偏移 + 行列，而不是全局 `GetErrorPtr`（后者在线程/嵌套调用下很难用）。

### 5.3 结论

- 若目标是"把现有 cJSON 调用点换掉"：**不可行**，缺 DOM 与打印形态，等于重写业务代码，且 C 侧不可链接。
- 若目标是"在 ct 项目里解析配置/报文"：**比 cJSON 更合适**，前提是接受"只读视图 + 不精确实数"。
- 两者应**并存**：ct 项目内部用本实现；需要 DOM/美化输出/给 C 调用方时用 cJSON binding。

---

## 6 ct-pkg 归属判断

### 6.1 先纠正一个前提

现有 ct 提案**明确反对**在 std 里重写 JSON：

- `docs/proposals/ct-pkg-agent-runtime.md:120`：「JSON/SSE 的拼接先用 `StrBuilder`；解析仍建议走 **cJSON 这类成熟 C 库，不在 std 里重写**。」
- 同文件 `:162`：「**不在 std 里重写 JSON/HTTP**；继续用 cJSON/libcurl 这类 C 库。」

所以"放进 ct-pkg 标准库"这个提法本身要拆成两件事：**进 ct-pkg 生态（对）** vs **进 `std` 包（与既有决策冲突，需先改提案）**。

### 6.2 我的意见

**进 ct-pkg，但不进 `std`，且不在当前状态下发布。**

- 建议包名：`json`（独立包，`ct get json`），而不是 `std/json`。
- 版本从 `0.1.0` 起，README 显式声明"API 未冻结，1.0 前可变"，避免撞 Z6 的 1.0 兼容冻结。
- `std` 只保留 `str/io/math`（`lib/std/README.md:8`、`:26-29`），不新增 JSON 章节。

### 6.3 放进去之前必须补齐什么（按优先级）

**P0 — 语义正确性（不补就等于把缺陷固化成 API）**

1. **实数解码正确舍入**，或把"原文 API"定为唯一数值入口并在类型上强制。
   判据：10^6 个随机 double 的 `%.17g` 文本，`as_double` 与 `strtod` **逐位相等率 100%**；当前 13 个样本只有 7 个（§3.2）。
2. **深度上限钳制**：`depth_limit` 设硬上限（如 1024），或改显式栈。
   判据：`depth_limit` 任意取值下，10^6 层输入都**不崩**（当前 110k 崩，§3.3）。
3. **UTF-8 校验开关**（默认关，包一层 `parse_strict`）。
   判据：非法 UTF-8 在 strict 模式被拒；非 strict 行为与今天一致。

**P1 — API 边界（决定别人能不能用）**

4. **消除 O(n²) 遍历**：给 `JsonView` 附元素边界索引（一次扫描建 `int` 数组，仍零 malloc，由调用方给缓冲），或提供 DOM 层。
   判据：20k 数组全量遍历 < 10 ms（当前 1,240 ms）。
5. **writer 长度化**：`string_len(const char*, int)`，修掉 `\u0000` 截断（§3.5 实测）。
   判据：含 `\u0000` 的字符串 `parse → as_string → write → parse` 语义保持。
6. **可选缩进输出**（产品日志/调试必需）。
7. **截断变成显式错误码**（现在是返回长度 + 静默截断）。

**P2 — 包工程（不做就装不进 ct-pkg）**

8. **单元拆分**：`JsonDoc`（reader）/ `JsonOut`（writer）/ `JsonValue`（ops）拆成符合"一单元一主类型"的 `.h.ct`（`docs/package-guide.md:25-31`）。
9. **去宏**：`JSON_OUT_DEPTH` 等不得出现在公开布局（实测会挡消费方）。
10. **收敛导出面**：7 个 ops 结构体不应进生成头；只导出 `JsonDoc` / `JsonView` / `JsonOut` 与 `json_message`。
11. **测试迁出 `main`**：现在断言绑在 golden 上（`json.ct:2275-2286`），包需要独立测试单元。
12. **fuzz + 基准入 CI**：现在 `test/fuzz` 只管编译器（`test/fuzz/run.sh:3-8`）。

**P3 — 生态（可以后置）**

13. 与 `std/string`（Phase 34/36，`docs/roadmap.md:51`）衔接：`as_string` 增加"返回 `Str` 所有权"的重载；writer 接受 `Str`。
14. C ABI 导出（Phase 39，`docs/roadmap.md:54`）——只有需要给 C 调用方才做。

### 6.4 包边界怎么划

| 包/单元 | 内容 | 是否本期 |
| --- | --- | --- |
| `json` / `JsonDoc.h.ct` | 词法 + 校验 + 只读视图 + 错误定位（**唯一 RFC 8259 词法实现**） | 必做 |
| `json` / `JsonOut.h.ct` | 追写器 + 转义 + 数值格式化 | 必做 |
| `json` / `JsonValue.h.ct` | ops 分发（**不导出**，包内私有） | 必做 |
| `json-dom`（独立包） | 可变 DOM，依赖 `json`，节点用调用方 arena 分配 | P1 之后，可独立版本 |
| `json-stream` | 增量/SAX | **本期不主张**：语义未定义（无回调契约、无错误恢复），cJSON 也没有；仓促做会变成第二个不兼容实现 |

理由：词法与转义必须只有一份，否则 DOM 包与视图包会各自漂移（`DECISIONS.md:48-56` 已经用同样的理由拒绝过"两套打印"）。DOM 是纯增量层，独立版本代价最小。流式是真需求但真没设计，不主张比假装支持好。

### 6.5 与已规划 `std/string` 的依赖

- **硬依赖：无。** reader 全程零分配，`as_string` 只要调用方缓冲；writer 接受 `const char*`。没有 `std/string` 也能完整工作。
- **软依赖（增强）：有。** ① `as_string` 的"截断 + 返回所需长度"语义在有了 `Str` 之后可以变成"返回 `Str`"，消除调用方两趟调用；② writer 接受 `Str` 可避免 `strlen`；③ 含 `\u0000` 的字符串只有长度化 `Str` 能无损表达。
- 结论：**`std/string` 不构成排期阻塞**，但 P1 的"长度化字符串"最好按 `std/string` 的契约设计，避免届时改签名两次。

### 6.6 "现在放" vs "补齐后再放"的代价

| 方案 | 代价 |
| --- | --- |
| **现在放**（直接 0.1.0 发布） | ① 立刻背上 §3.2/§3.8 的语义债，用户第一次遍历大数组或比对浮点就会撞；② 与 `ct-pkg-agent-runtime.md:120/162` 直接冲突，得同时改提案；③ 实测的两个打包硬坑（宏进公开布局、static-only）会让第一批消费者编不过；④ 测试绑在 `main` 上，包内没有可运行的验收；⑤ 一旦有人依赖，P0 修正都是破坏性变更 |
| **补齐后放**（P0+P1+P2） | ① 短期没有"ct 写的库"样板；② 需要把 `examples/json` 当临时范例（它已经是很好的范例，`README`+`DECISIONS` 都在）；③ 工作量集中但可控 |

**推荐：补齐后再放。** 并且**先发布为独立包 `json`，不进 `std`**。

### 6.7 反方理由为什么不成立

| 反方说法 | 为什么不成立 |
| --- | --- |
| "DeepSeek 建议放进 ct-pkg，所以应该放" | 方向对（进 ct-pkg），但"放进 std 作为标准库"与仓库既有决策冲突（`ct-pkg-agent-runtime.md:120/162`），且标准库的隐含承诺是**稳定 API**；当前 API 的 O(n²) 遍历与浮点不精确是**语义缺口**，不是实现细节，冻结后无法在不破坏兼容的前提下修 |
| "零分配、无泄漏，天生适合标准库" | 零分配确实是最大优点（§3.7），但标准库用户要的是"能安全地遍历、能拿到准确数字、能美化输出"；这三点它现在都不给。零分配解决的是"不会泄漏"，不是"能不能用" |
| "示例质量这么高，直接提包就行" | 示例质量高在**文档与负例覆盖**，低在**可复用性**：测试写在 `main`、符号全 `static`、宏进公开布局、ops 结构体会被导出。这些是"程序"与"包"的差别，不是靠加 `pub` 能补的（已实测两处编译失败） |
| "先放进去，后面再改" | 0.x 可以改，但 ct-pkg 的消费者会 `ct get` 并锁 commit（`docs/package-guide.md:97-106`）；一旦有人锁了版本，P0 修正（舍入、深度上限、UTF-8 严格模式）就是破坏性升级，成本高于现在补齐 |
| "cJSON 已经够用，干脆别做" | 也成立了一半：需要 DOM/美化/给 C 调用方时应该用 cJSON binding。但"ct 原生、零分配、可指向只读字面量、int64 精确"这四项 cJSON 给不了，值得有第二个包，只是不该急于冻结 |

---

## 7 离生产还差什么（排序清单）

按"不修就会导致错误结果 > 不修会导致崩溃 > 不修会导致误用 > 不修会难以维护"排序：

| 序 | 缺口 | 现状证据 | 验收判据 |
| --- | --- | --- | --- |
| 1 | 实数解码不保证正确舍入 | 13 样本 7 个 bit-exact；`0.30000000000000004` → `…001`（§3.2） | 10^6 随机 double 文本 100% 与 `strtod` 逐位相等 |
| 2 | `at()`/`member()` 线性重扫 → O(n²) 遍历 | 20k 数组全量遍历 1,240 ms（§3.8） | 20k 全量遍历 < 10 ms，且内存仍由调用方持有 |
| 3 | `depth_limit` 无上限 → 栈溢出 | 110k 层 SIGSEGV(139)（§3.3） | 任意 `depth_limit` 下 10^6 层不崩（钳制或显式栈） |
| 4 | 输入 UTF-8 不校验 | `0xFF 0xFE` 被接受（§3.1） | strict 模式拒绝非法 UTF-8，错误码可区分 |
| 5 | 写入器不接收长度 → `\u0000` 静默丢失 | `as_string` 后写回得 `""`（§3.5） | 长度化 API，`\u0000` 往返无损 |
| 6 | 输出截断无错误码 | 请求 21 字节、`cap=8`，只返回长度（§3.5） | `finish()` 返回 `JSON_EMIT_TRUNCATED` 或等价可判定状态 |
| 7 | 无缩进输出 | `json.ct:740-873` 无 indent 分支 | 提供 `begin(buf,cap,indent)` 或独立 pretty 入口 |
| 8 | `read_err` 使只读并发不安全 | 访问器写 `doc->read_err`（§3.7） | 访问器改为返回值携带错误，或文档明示单线程契约 |
| 9 | 包化未做（单元/宏/导出面/测试） | 拆包实测两处编译失败（§3.10） | `ct build -I` 消费方可编可跑；头文件不含宏与 ops 结构体 |
| 10 | 无 JSON fuzz / 基准 / MSVC CI | `test/fuzz` 只覆盖编译器（§3.9） | reader 的确定性 fuzz + 基准入 CI；Windows 至少编译通过 |
| 11 | 诊断列按字节而非字符 | `{"é":x}` → column=7（§3.6） | 可选"按码点计列"模式，或文档/插件侧明确换算 |
| 12 | README 构建命令失效 | `./ctc` 被拒（§1） | 改为 `ct-ast` 路径，或注明需要 AST 编译器 |

---

## 8 未验证项与取证方式

以下结论**本次未取得直接证据**，报告中已按"未验证"标注，不应作为决策依据：

| 项 | 状态 | 建议取证方式 |
| --- | --- | --- |
| cJSON `CJSON_NESTING_LIMIT` 的具体值 | 未验证（源码抓取被截断） | `curl cJSON.c | grep NESTING_LIMIT` |
| cJSON `print_number` 的 `%.15g/%.17g` 双尝试策略 | 未验证 | 同上，看 `print_number` 全文 |
| Windows/MSVC 下 `long long` + `%lld` + `int` 宽度 | 未验证 | VS2019+ 编译 `json.c` 并跑 golden |
| 32 位平台（`int`=32、指针 32 位）的边界 | 未验证 | `-m32` 构建并跑 golden |
| `JsonDoc` 堆分配（非栈）时 vtable 初始化 | 未验证 | 观察生成 C：栈声明会自动注入 `.__json_vptr`；`malloc` 不会，需手工设置 |
| 超 2 GB 输入 | 不支持（`int len`，代码可证） | 无需验证，属设计边界 |

---

## 附录 A 复现命令（全部在 `/tmp`，未改仓库）

```sh
# 1. 构建 AST 编译器链（约 1 分钟）
cd <repo>
./ctc selfhost/l1/ctc.ct -o /tmp/json-probe/ast/ast-l1.c
cc -O2 -std=c99 /tmp/json-probe/ast/ast-l1.c -o /tmp/json-probe/ast/ast-l1
/tmp/json-probe/ast/ast-l1 build selfhost/l2/driver.ct -o /tmp/json-probe/ast/l2src
cc -O2 -std=c99 /tmp/json-probe/ast/l2src/*.c -o /tmp/json-probe/ast/ast-l2
/tmp/json-probe/ast/ast-l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/json-probe/ast/astsrc
cc -O2 -std=c99 /tmp/json-probe/ast/astsrc/*.c -o /tmp/json-probe/ast/ct-ast

# 2. 生成 + 编译 + 跑 golden
/tmp/json-probe/ast/ct-ast examples/json/json.ct -o /tmp/json-probe/json.c
cc -Wall -Wextra -std=c99 -O2 /tmp/json-probe/json.c -o /tmp/json-probe/json
/tmp/json-probe/json > /tmp/json-probe/run.out
diff -u examples/json/json.expected.out /tmp/json-probe/run.out   # GOLDEN_MATCH

# 3. 消毒器
cc -std=c99 -O1 -g -fsanitize=address,undefined /tmp/json-probe/json.c -o /tmp/json-probe/json_asan
/tmp/json-probe/json_asan        # exit 0，无 ASAN/UBSAN 报告

# 4. 自定义探针（本次编写，位于 /tmp/json-probe/）
#    probe.c   —— 编码/精度/性能/fuzz（deep、fuzz 子命令）
#    probe2.c  —— 重复键、kind 错、转义、截断、跨文档视图
#    probe3.c  —— \u0000 往返丢失
#    perf.c    —— 解析/遍历/查找/字符串/写入的规模曲线
/tmp/json-probe/probe_asan fuzz 60000        # 60,000 输入，1,204 个解析成功，无崩溃
/tmp/json-probe/probe deep 100000 1000000    # rc=1（接受）
/tmp/json-probe/probe deep 110000 1000000    # SIGSEGV（139）
```

## 附录 B 关键行号索引

| 主题 | 行号 |
| --- | --- |
| 常量与错误码 | `json.ct:33-69` |
| `JsonWrite` / `JsonOut` | `json.ct:76-101` |
| `Json` / `JsonDoc` / `JsonView` | `json.ct:105-141` |
| 词法：空白 / 十六进制 / 字符串 | `json.ct:145-264` |
| 词法：数字 | `json.ct:267-314` |
| 词法：结构与字面量 | `json.ct:317-431` |
| 视图校验 / 深度 | `json.ct:433-445` |
| 转义解码 / key 比较 | `json.ct:448-551` |
| 迭代器 | `json.ct:555-640` |
| 写入核心（含转义） | `json.ct:644-735` |
| `impl JsonWrite for JsonOut` | `json.ct:739-873` |
| `JsonValue` 与 7 种 ops | `json.ct:884-1533` |
| `impl Json for JsonDoc` | `json.ct:1589-1752` |
| 错误文案 | `json.ct:1756-1783` |
| demo / 测试 / main | `json.ct:1785-2286` |
