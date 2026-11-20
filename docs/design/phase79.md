# Phase 79 — 切片 `T[]`（S3）

> **状态：完成（S3a–S3e / E79-1–E79-6；2026-11-20 收口，`v0.79.0`）**（2026-11-20 立项）。
> **签收：EDITOR 2026-11-20**（主编统一签收；卡作者 REQ）；实现红证 VERIFY 见 §5。
> **前置（口径写死）**：本卡入口只要求 **P-7.2 切片原型**（`docs/planning/j6-evidence/p72/`，
> 25/25 通过、A.4 放置矩阵 10/10）+ **PH-78 收口**（`v0.78.0`）。
> **J-6 全量不在本卡入口**（P-1…P-6 证据包未齐）；卡内不据此声称 J-6 已过。
> P-7.2 为执行方自评证据；本卡实现按 §5 的本地门禁独立签收。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase79.md`。
> **依据**：[提案 v2](../proposals/pointer-free-v2.md)、[D-011](../decisions/D-011.md)、
> [phase 安排](../planning/pointer-free-phase-plan.md)、[P-7.2 证据](../planning/j6-evidence/p72/evidence.md)。

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

### 1.1 原型边界

P-7.2 已证（见 [证据](../planning/j6-evidence/p72/evidence.md)）：`T[] = {ptr,len}`、数组→切片、子切片、`foreach`、`s[i]` 越界 trap、`s.get(i)`（越界返回 0 指针）、`const T[]` 写硬错、A.4 十类放置、返回局部视图 lint。补丁在 [`j6-evidence/p72/p72.patch`](../planning/j6-evidence/p72/p72.patch)；已 rebase 到 `ca3354a5` 并重放 **25/25**，产物 [`p72-rebased-ca3354a5.patch`](../planning/j6-evidence/p72/p72-rebased-ca3354a5.patch)，DEV 可直接移植。

本卡首轮不覆盖（明确不做，避免收口争议）：`s.field[i]` 与 `f().get(i)` 的链式 place；`int[] s; s = a;` 后置赋值；`Vec.as_slice`（需要 pointer+len 构造器，E79 不含）；`box` 的存储语义（PH-81）。这些如要纳入，必须回到本卡改 E79 判据。

### 1.2 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S3a 表示/语法 | `{ptr,len}`、`T[]`、数组→切片、子切片、`foreach` | P-7.2 |
| S3b place/索引 | `s[i]` 读写、越界 trap、`get`、`const T[]` | S3a |
| S3c 白名单/返回 lint | 四位置硬错、返回局部视图 lint | S3b |
| S3d `T a[]` 迁移 | 形参/无初始化器告警；推断长度数组保留 | S3c |
| S3e 文档/门禁 | spec、package-guide、golden | S3d |

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S3a 表示/语法 | 切片类型、数组/子切片、`foreach` | `p79_basic` | M |
| S3b place/索引 | `s[i]` 检查 place、trap、`get`、`const T[]` | `p79_index` | M |
| S3c 白名单/返回 lint | 四位置硬错、返回局部数组/owning 视图 lint | `p79_places` | M |
| S3d `T a[]` 迁移 | 形参/无初始化器告警；`T a[] = {...}` 保留 | `p79_migrate` | S |
| S3e 文档/门禁 | spec/package-guide/golden | `p79_docs` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；S3e 为纯文档任务，写 `no-test:` 并由 REVIEW 签字。

### 2.1 S3a 红证夹具（开工第一步）

| 夹具 | 断言 |
| --- | --- |
| `p79_basic` | `int[] s = a;`、`s[i]` 读写、`a[1..]` 子切片、`foreach`、`Vec.as_slice` |
| `p79_index` | 越界 `s[i]` trap；`get` 越界返回 0 指针；`const int[]` 写硬错 |
| `p79_places` | 字段/全局/接口/box/Option/Result/Vec/Map/数组元素/泛型实参/闭包捕获 10 类硬错 |
| `p79_migrate` | `T a[]` 形参/无初始化器告警；`T a[] = {...}` 仍是推断长度数组 |
| `p79_docs` | `no-test:`，spec/package-guide/golden 同步 |

> **实现进度（2026-11-20 收口）**：S3a–S3e 已落（P-7.2 rebase + `T a[]` 告警 + spec §4.69）；
> `test/ast/p79_basic.sh` 15/15，已接入 `selfhost/check-ast.sh`；全量门禁见 §5。
> `Vec.as_slice` 按 §1.1 延期（需要 pointer+len 构造器），不属于 E79。

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

## 5 收口证据（2026-11-20）

| 判据 | 证据 |
| --- | --- |
| E79-1 | `p79_basic` 的 `migrate_param`（告警）与 `migrate_infer`（静默）；spec §4.69 |
| E79-2 | `p79_basic` 的 `basic`：数组→切片、`s[1..]`、`foreach`、`{ptr,len}` |
| E79-3 | `basic` 读写/借用；`trap` 越界非零退出；`get` 越界 0；`const_write` 硬错 |
| E79-4 | `const_write`；C 数组下标保持（PH-78 与既有 goldens 不变） |
| E79-5 | `p79_basic` 的 `field` / `global` / `generic` / `container` / `option` / `result` / `arrelem` / `iface` / `closure` 九类硬错 |
| E79-6 | `ret` 返回局部视图 lint；全量门禁见下 |

- `sh test/ast/p79_basic.sh <ct-ast>` → **15 passed, 0 failed**。
- `sh selfhost/check-ast.sh` → `1526 passed, 1 failed, 3 skipped`；唯一失败是
  `baremetal_renode`（podman 未产出 `uart.txt`，环境缺失，与本卡无关）。
- `sh selfhost/check-sanitizers.sh` → `check-sanitizers: OK (581 checks, no sanitizer report)`。
- `python3 test/docs/check-docs.py` → `check-docs: OK (… v0.79.0, 11 hard gates, … 5 signoff(s))`。
- `sh tools/check.sh g0` / `g8` → OK（PN-2 版本一致）。
- 迁移：`test/ast/17_param_array/prog.ct`、`examples/21_generic_bound/generic_bound.ct`
  的 `T a[]` 形参改为 `T *`，`ct check`/`ct build` 与运行输出不变。
- 版本：五处 `CTC_VERSION` + 51 个 golden/expected + p39 ABI banner 仅版本 token 变化。
- 延期（不影响 E79）：`Vec.as_slice`、`s.field[i]`、`f().get(i)`、`int[] s; s = a;`。
