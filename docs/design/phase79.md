# Phase 79 — 切片 `T[]`（S3）

> **状态：规划中（未开卡；J-6 门槛）**（2026-11-20 立项；`v0.79.0` 拟）。
> **前置**：P-7.2（S3 全量原型）；PH-78 收口（单卡纪律；S2/S3 无技术依赖）。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase79.md`。
> **依据**：[提案 v2](../proposals/pointer-free-v2.md)、[D-011](../decisions/D-011.md)、
> [phase 安排](../planning/pointer-free-phase-plan.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-79（legacy 文件 `phase79.md`） |
| 目标 | `T[]` 作为借用视图：唯一拼写、带检查 place、`get` 软访问、`const T[]` 只读、四位置白名单 |
| 范围 | `{ptr,len}` 表示、数组/切片/Vec 转换、子切片、`foreach`、`s[i]`/`get`、`const T[]`、旧 `T a[]` 迁移 |
| 非目标 | `String/Str`（PH-80）；`box/new`（PH-81）；跨过程定值；借用检查 |
| 交付物 | 编译器改动、`test/ast/p79_*`、迁移 lint、文档 |
| 任务清单 | §2（S3a–S3d） |
| 退出判据 | E79-1…E79-6（§3） |
| version-minor | 79（PH-79，`d=0`） |
| 已知风险 | R79-1…R79-5（§4） |

## 1 需求与边界

```ct
int a[] = {1, 2, 3};     /* 推断长度数组：C 存储 */
int[] s = a;             /* 切片视图 */

int x = s[1];            /* 带检查 place，读 */
s[1] = 9;                /* 可写切片 */
int y = s[9];            /* 越界 trap */
int *p = s.get(9);       /* 软访问：越界 0 */

const int[] ro = a;
ro[0] = 1;               /* error：只读切片 */
```

- `T[]` 是唯一切片拼写；`T a[]` 只在无初始化器/形参时废弃，`T a[] = {...}` 保留为推断长度数组。
- C 数组 `T[N]` 保持 C 下标，不检查；编译器可探知越界时报警。
- 切片 `s[i]` 是带边界检查的 place；越界 trap；`get` 软访问返回空/0。
- `T[]` 可写；`const T[]` 只读；`String/U16String` 不可写（PH-80）。
- 四位置白名单：字段/全局/接口/box/Option/Result/容器/数组元素/泛型实参/闭包捕获硬错。
- 返回局部数组/局部 owning 视图的 lint；透传路径作者负责。

### 1.1 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S3a 表示/语法 | `{ptr,len}`、`T[]`、数组→切片、子切片、`foreach` | P-7.2 |
| S3b place/索引 | `s[i]` 读写、越界 trap、`get`、`const T[]` | S3a |
| S3c 白名单/迁移 | 四位置硬错、`T a[]` 迁移、返回 lint | S3b |
| S3d 文档/门禁 | spec、package-guide、golden | S3c |

## 2 任务

| 任务 | 交付 | 验收 |
| --- | --- | --- |
| S3a 表示/语法 | 切片类型、数组/子切片、`foreach`、`Vec.as_slice` | `p79_basic` |
| S3b place/索引 | `s[i]` 检查 place、trap、`get`、`const T[]` | `p79_index` |
| S3c 白名单/迁移 | 四位置硬错、`T a[]` 告警/迁移、返回 lint | `p79_places` / `p79_migrate` |
| S3d 文档/门禁 | spec/package-guide/golden | `p79_docs` |

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E79-1 | `T[]` 唯一；`T a[] = {...}` 推断长度数组；`T a[]` 形参/无初始化器告警→v1 硬错 |
| E79-2 | 切片表示 `{ptr,len}`；空 `{0,0}`；数组→切片自动补 len；子切片半开区间 |
| E79-3 | `s[i]` 读/写/借用作用于底层；越界 trap；`get` 软访问；`s[0] = x` 可写切片 |
| E79-4 | `const T[]` 写硬错；C 数组保持 C 下标；非法越界可探知时报警 |
| E79-5 | 四位置白名单硬错；`Vec<int[]>`/`struct { int[] s; }`/闭包捕获全红 |
| E79-6 | 返回局部数组/局部 owning 视图 lint；全量 `check-all` 与 ASan 通过 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R79-1 | `T a[]` 上下文二义 | 明确「有初始化器=数组；形参/无初始化器=废弃」；负例 |
| R79-2 | 切片越界 trap 成本 | 每下标一个分支；`get` 软访问；`byte_*` 不适用切片 |
| R79-3 | 字段/容器/闭包存切片 | 四位置硬错；`Vec<Str>` 同样禁止 |
| R79-4 | 返回视图透传悬垂 | 契约 + 直接 lint；ASan |
| R79-5 | 与 `String/Str` 表示冲突 | `Str` 是 `char` 切片 nominal 特化，PH-80 复用本卡表示 |

回滚：单卡回滚；C 数组与 Vec 行为不变。
