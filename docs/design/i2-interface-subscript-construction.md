# I2 施工卡 · 接口值下标（方法级 `index`，两阶段）

> 中文。REQ 起草 2026-11-28，卡号 `I2-C1`，锚点 `e0a67b8e`。
> 依据：所有者 2026-11-28 四问裁定（[RFC 评估 §3.1](../reviews/2026-11-27-indexable-rfc-evaluation.md#31-i2-的四个待裁定问题2026-11-28所有者未裁)）、
> [卡 E-V3-9e / E-V3-9f](../phases/v1-PH-2/card.md)、[REQ-I2-1](../planning/requirements-pool.md)、
> [D-028](../decisions/D-028.md)、[REQ-INDEXFOLD-1](../planning/requirements-pool.md)（I1，共用解析表）。
> **写者：DEV（A 轨道）**；ARCH 先出 `D-034`、EDITOR 签收、REQ 排期；REV 只评审与复核。

## 1 已定口径（不得在实施中改动）

| # | 口径 | 来源 |
| --- | --- | --- |
| 1 | 单 trait，无 `Indexable`、无 trait 继承 | Q2 裁定 |
| 2 | 标记写在方法上：`Str get(Str k) index;`；`index` 是**上下文修饰词**，其它位置仍是普通标识符 | Q2 裁定 |
| 3 | 不新增 vtable 槽；`index` 只是给已有 `get` 槽加"可作为 `[]`"的属性 | Q2 裁定 |
| 4 | 阶段一只读；阶段二写入（`set(K,V) index`）；两阶段同属 1.2 | Q3 裁定 |
| 5 | 不承诺 vtable 槽 ABI；只保证同一次构建内一致 | Q4 裁定 |
| 6 | 具体类型仍走 D-028 的固有 impl；接口值走 trait 的 `index get`；(i)/(ii) 口径由 `D-034` 选定 | D-028 + ADR 输入 |
| 7 | I1 只管 struct + 字面量键；`s["x"]`（s 为接口值）不受 I1 影响 | I1/I2 分工 |

## 2 前置（开工前必须）

1. ARCH 出 **`D-034`**：`index` 的语法位与词法规则、接口值解析、与 D-028 的 (i) 分裂 / (ii) 统一、两阶段边界、诊断文案；起草输入已备：[i2-d034-drafting-input](i2-d034-drafting-input.md)（D1–D10 待 ARCH 定）；
2. **EDITOR 签收** `D-034`（非作者席位）——**已完成（2026-11-28，`accepted`）**，由 REQ 排期；
   签收口径已对齐（T-8 `f0ce1746`、AGENTS §0.7 + 规范矩阵 `b4f3a568`）；
3. `D-034` 签收并合入后才动代码；未签不得实施。

## 3 切片

### I2-1 语法位：`index` 上下文修饰词

- `trait` 声明里，方法签名之后、`;` 之前的 `index` 被识别为标记；
- `.h.ct` 的 `pub trait` 同样可用；`impl` 侧**不写**、写了报错（避免两处声明不一致）；
- `index` 不作保留字：`int index`、`c.index`、结构体字段 `index` 全部保持原义；
- 判据：`test/ast` 正例（trait 声明、`.h.ct`、跨单元）+ 负例（impl 里写 `index`、位置错误）；
- 报告：`index` 作为标识符的既有用例零回归。

### I2-2 解析与检查：接口值只读下标

- `o[k]` 且 `o` 的静态类型是接口值 → 在 trait 的 `index` 方法里按**键的实参类型**匹配；
- 无 `index` 方法 → 硬错：`trait 'T' declares no indexed get; 'o[k]' is not available`；
- 键类型不匹配 → 硬错并列出该 trait 的 `index` 方法键类型；
- 诊断文案与诊断码口径以 [D-034 §2](../decisions/D-034.md) 为准：用其冻结文案，**不新增 `E-` 码**
  （registry 要求源码字面量与表行同集合，跨席位分提交会红）；DEV 若要编码，须同一提交补 `codes.md`；
- 多个 `index` 方法（不同键类型）按键分派，与 D-028 一致；
- **不折叠**：接口值的键即使是字面量也不做 I1 折叠（那是 struct 的路径）；
- 判据：正例（单/多键）、负例（未标、键不匹配、对非接口值误用）；`check-ast` 0 失败。

### I2-3 发射与跨单元

- 生成 C：`o[k]` → vtable 的 `get` 槽调用，形态与显式 `o.get(k)` 逐字节一致（同一次构建）；
- 跨单元：trait 在 `.h.ct` 声明、实现在他单元、调用在第三单元，三者一致；
- 固有 impl 路径（D-028）生成物零变化；
- 判据：用户语料 25/25 逐字节；自举 2 轮；seed 两轮；`check-all` 8 门。

### I2-4 阶段二：写入

- `void set(K, V) index;` → `o[k] = v`；
- 必须定义并写进 spec：只读实现的 `set` 语义（空实现 / 运行期报错 / 不可标注）、值的所有权（借用视图是否复制）、失败语义（返回类型决定 `=` 的表达结果）；
- 不新增槽（`set` 本就是 trait 方法）；
- 判据：正例（可写实现）、负例（只读实现、键类型不符）、ASAN 无泄漏；语料逐字节。

### I2-5 文档与样例

- spec 新增节（`index` 修饰词 + 接口值下标 + 两阶段语义）、glossary、tutorial：**REQ 落笔**
  （DEV 提供生成 C 实测与夹具路径，REV 复核）；
- `docs/planning/feature-examples-matrix.md` 加行；README 片段可选；
- 判据：`check-docs` OK（含 `--selftest`）。

## 4 统一门禁（每片）

```sh
cc -Wall -Wextra -std=c99 -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o /tmp/ct-i2
CT_C_BOUNDARY=allow bash selfhost/check-goldens-ast.sh /tmp/ct-i2     # 25/25
bash selfhost/check-ast.sh /tmp/ct-i2        # 0 失败；后台跑
bash selfhost/gen-seed.sh && bash selfhost/check-seed.sh              # 片末一次，两轮
bash selfhost/check-all.sh                   # 8 门
bash selfhost/check-warnings.sh              # 0
python3 test/docs/check-docs.py
bash tools/check.sh g1 && bash tools/check.sh g6 && bash tools/check.sh g8
```

## 5 负例清单（每类 ≥2）

| 类 | 负例 | 期望 |
| --- | --- | --- |
| 语法 | `impl Store for S { Str get(char *k) index { … } }` / `index` 写在返回类型前 | 硬错，提示标记只属于 trait 声明 |
| 解析 | trait 有 `get` 但未标 `index`；`o[0]` 而只有 `get(char *) index` | 硬错，列出可用键类型 |
| 误用 | 对 non-interface 值走 I2 路径；对 struct 用未声明固有 `get` 的键 | 硬错，提示 D-028 规则 |
| 阶段二 | trait 未声明 `void set(K, V) index` 却写 `o[k] = v`；写值生命周期越过对象 | 编译期硬错 D034-8 / 借用检查拒绝 |
| 跨单元 | trait 在 A、impl 在 B、调用在 C，B 改签名后 C 未重编 | build 模式全量重编，无 stale vtable |

## 6 风险

| # | 风险 | 处置 |
| --- | --- | --- |
| 1 | `index` 作上下文关键字与既有标识符冲突 | 只在"方法签名后、`;` 前"识别；`test/ast` 专测既有 `index` 用例 |
| 2 | vtable 槽顺序与显式调用不一致，生成 C 漂移 | I2-3 要求"与 `o.get(k)` 逐字节一致" |
| 3 | 接口值来自 `.h.ct` 但调用方看不到 `index` 标记 | 标记随 `pub trait` 进公开头；负例覆盖 |
| 4 | 阶段二把只读视图变成可写 | 只读实现必须显式拒绝（ADR 定形态） |
| 5 | 与 I1 争用解析表 | 共用 D-028 表：struct 走 I1/固有 impl，接口值走 I2；`D-034` 写清优先级 |

## 7 回滚

| 对象 | 动作 | 结果 |
| --- | --- | --- |
| I2-1…I2-3 | 单独 revert | 接口值下标消失，struct 路径不变 |
| I2-4 | 单独 revert | 写形态消失，只读保留 |
| 任一片 | 同批 seed revert | goldens 与 seed 一致 |

## 8 交接

| 席位 | 事项 |
| --- | --- |
| ARCH | 起草 `D-034`（语法位、解析、D-028 口径、两阶段边界）；不得缺位 |
| EDITOR | 审核并签收 `D-034`（非作者席位） |
| REV | 实施后只读复核（正负例、生成 C 一致、shim/seed 无回归），只出结论与样例 |
| DEV | 按 I2-1 → I2-2 → I2-3 → I2-4 → I2-5 实施，各片独立提交 |
| REQ | 签收后安排排期；验收 `E-V3-9e` / `E-V3-9f`；同步 spec 与矩阵 |

## 9 排期（2026-11-28）

| # | 任务 | 写者 | 前置 | 交付/验收 |
| --- | --- | --- | --- | --- |
| P-1 | `D-034` 起草（语法位、接口值解析、D-028 的 (i)/(ii) 口径、两阶段边界、诊断文案） | ARCH | 无（四问已裁） | ADR 合入 `docs/decisions/` |
| P-2 | 签收 `D-034` | EDITOR（非作者席位） | P-1 | 签名行；未签不动代码 |
| P-3 | 排期确认（本表顺序与片边界） | REQ | P-2 | 队列 Q-8 与本表一致 |
| I2-1 | 语法位：`index` 上下文修饰词 | DEV | P-2 | 独立提交；`test/ast` 正负例 |
| I2-2 | 接口值只读解析与检查（**E-V3-9e**） | DEV | I2-1 | 独立提交；`check-ast` 0 失败 |
| I2-3 | 发射与跨单元（与显式 `o.get(k)` 逐字节一致） | DEV | I2-2 | 独立提交；语料 25/25、自举 2 轮 |
| I2-4 | 阶段二写入（**E-V3-9f**）：`set(K,V) index` | DEV | I2-3 | 独立提交；ASAN；语料逐字节 |
| I2-5 | 文档与样例（REQ 落 spec/glossary/matrix；DEV 给夹具与实测；REV 复核） | REQ / DEV / REV | I2-1 后先落只读部分；I2-4 后补写形态 | `check-docs` + `--selftest` |

**串行点与冲突**

- I1（LANG-31）的 `T1` 与 I2-2 共用 D-028 解析表：**I1 先落 `T1`/`T2`，I2-2 再改同一函数**；
  若两片不改同一函数，可并行提交（各自独立提交，不混片）。
- 与 S8B-REM-1 R3–R8 文件集不重叠，可并行。
- 每片末 `gen-seed.sh` + `check-seed` 两轮；`v1.2.0` 的 tag 在 I1 与 I2 两阶段都落地后由所有者执行。

**不阻塞声明**：`D-034` 未签期间 DEV 继续 S8B R3–R8、Q-13，不空转；I2 停留不阻塞任何一项；
REQ 的 spec 同步与 REV 复核都不进 DEV 提交前置。

**裁定（所有者 2026-11-28）**：**ARCH 不得缺位**——技术设计规划由 ARCH 完成，ADR 由 **EDITOR**
审核签收，签收后由 **REQ** 安排具体任务与排期。此前"ARCH 不在场时由 REQ/DEV 代笔 ADR"的
临时口径作废。

## 10 验收清单（`E-V3-9e` / `E-V3-9f`）

> REQ 只读验收用；夹具名以 DEV 落地为准（下表给建议名，放在 `test/ast/i2_*`）。
> 每条都要有「命令 + 末行输出」证据，写入 `E-V3-9e` / `E-V3-9f` 的验收行。
> **键类型口径以 [D-034](../decisions/D-034.md) §3 为准**：字符串字面量的静态类型是
> `char *`，因此 `s["name"]` 只命中 `get(char *k) index`；`Str get(Str k) index` 不命中
> 字面量键（可先把键绑定为 `Str` 变量）。

### 10.1 阶段一（只读，`E-V3-9e`）

| # | 用例 | 期望 | 建议落点 |
| --- | --- | --- | --- |
| A1 | `trait Store { Str get(char *k) index; }`，接口值 `s["name"]` | 调 vtable 的 `get(char *)`；与 `s.get("name")` 生成 C 逐字节一致 | `test/ast/i2_index_read/` |
| A2 | 同一 trait 两个键类型都标 `index`（`get(char *)` / `get(int)`） | `s["k"]` 与 `s[7]` 分别命中，C 符号各不相同 | `i2_index_read_keys/` |
| A3 | trait 在 `.h.ct`、impl 在他单元、调用在第三单元 | `ct build` 全量重编、vtable 一致、运行输出正确 | `test/modules/i2_cross_unit/` |
| A4 | struct 的 D-028 / I1 路径 | `p52_*`、`320_*`、`321_*` 生成 C 逐字节不变 | 既有夹具 |
| A5 | 未标 `index` 的 trait 用 `o[k]` | 硬错 `trait 'T' declares no indexed get; 'o[k]' is not available` | `test/ast/errors/i2_no_index.ct` |
| A6 | `o[0]` 但只有 `get(char *) index` | 硬错并列出可用键类型 | `errors/i2_key_mismatch.ct` |
| A7 | `impl` 侧写 `index` | 硬错，提示标记只属 trait 声明 | `errors/i2_impl_index.ct` |
| A8 | 阶段一对 `o[k] = v` | 只读诊断（写入属阶段二），不写产物 | `errors/i2_write_phase1.ct` |
| A9 | 对非接口值误用 I2 路径 | 走 D-028 的既有诊断，不声称接口规则 | `errors/i2_non_iface.ct` |

### 10.2 阶段二（写入，`E-V3-9f`）

| # | 用例 | 期望 |
| --- | --- | --- |
| B1 | `void set(K,V) index;` + `o[k] = v` | 调 vtable 的 `set`；与 `o.set(k, v)` 生成 C 逐字节一致 |
| B2 | trait 未声明 `void set(K,V) index` 时写入 `o[k] = v` | **编译期硬错** D034-8（D-034 D5：不存在“只读实现被写入”的运行期分支） |
| B3 | 键类型与 `set` 不匹配 | 硬错并列出可用键类型 |
| B4 | 写入值的所有权/生命周期越过对象 | 借用检查或 ASAN 拒绝 |
| B5 | 阶段二不改变阶段一 | A1–A3 的生成 C 逐字节不变 |

### 10.3 执行命令（REQ）

```sh
cc -Wall -Wextra -std=c99 -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o /tmp/ct-i2
sh test/ast/i2_index.sh /tmp/ct-i2                       # 阶段一探针（DEV 提供）
sh test/ast/i2_index_write.sh /tmp/ct-i2                 # 阶段二探针（DEV 提供）
CT_C_BOUNDARY=allow bash selfhost/check-goldens-ast.sh /tmp/ct-i2   # 25/25
bash selfhost/check-ast.sh /tmp/ct-i2                    # 0 失败（至少 p52_*/320/321 + 新夹具）
bash selfhost/check-seed.sh                              # 两轮逐字节
bash selfhost/check-warnings.sh                          # 0
sh test/ir/run.sh /tmp/ct-i2                             # 15 checks
python3 test/docs/check-docs.py                          # OK
```

**门槛**：`E-V3-9e` 只要求 10.1 全绿；`E-V3-9f` 要求 10.1 + 10.2 全绿且 A4/B5 的逐字节不变成立。
任一负例出现「多诊断 / 写产物 / 退出 0」即验收失败，退回 DEV，不改判据。
