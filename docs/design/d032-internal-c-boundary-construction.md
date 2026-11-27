# D-032 施工卡 · 内部层 C 边界豁免（selfhost/ct-ast + lib/core）

> 中文。REQ 起草 2026-11-28，卡号 `D032-C1`，锚点 `053eee16`。
> 依据：[D-032](../decisions/D-032.md)（设计）、[卡 §8 CR-V3-1](../phases/v1-PH-2/card.md#8-判据变更记录)（判据）、
> [c-shim-contract N-8](../c-shim-contract.md)、[spec §4.66](../language-spec.md)。
> **写者：DEV（A 轨道）**；REV 只签收与只读复核；REQ 只验收。

## 1 范围

| 做 | 不做 |
| --- | --- |
| `c_boundary_for` 增加"单元自身目录 manifest"回退（与 `leaks_for` 对齐） | 不新增"路径前缀自动 allow"的特判 |
| `selfhost/ct-ast/ct.pkg`、`lib/core/ct.pkg` 各写 `c-boundary = allow` | 不改 `c-boundary` 键名/取值，不新增语法 |
| 删 71 个 include-only shim，include 移回对应 `.h.ct` | 不改消费者默认（strict 仍是默认） |
| 保留 3 个有 C 原型的 shim | 不扩 §4.67 补头集合 |
| seed 重生成与对齐 | 不改版本号、不打 tag、不动 `examples`/`test` |

## 2 基线（2026-11-28 实测）

| 项 | 数 |
| --- | --- |
| `selfhost/ct-ast/**/*.shim.h` | 66（63 个只有 `#include`） |
| `lib/core/*.shim.h` | 6（全部只有 `#include`） |
| `lib/core/utf16/*.shim.h` | 2（`U16Str` / `U16String`；**由 `lib/core/ct.pkg` 覆盖子树后退场**） |
| `bootstrap/ct-ast/*.shim.h` | 68 |
| 需保留的 shim | 仅 selfhost 的 `Module`、`ModuleBoundary`、`Pkg`（有原型） |

## 3 切片

### M1 解析语义：包根覆盖子树 + 两处 manifest（编译器改动）

1. 在 `frontend/module/Module.h.ct` 抽出"包根解析"：从单元所在目录向上找最近的 `ct.pkg`，
   **止于单元所属根**（`-I` 根或内置层根），返回该目录与其键值。
2. `c_boundary_for` 改为用该包根：找到 `c-boundary` 键即按其值；找不到 manifest 或键 → `strict`。
3. `leaks_for` 同批改成同一解析：同一份 `ct.pkg` 的 `leaks` 与 `c-boundary` 作用域一致；
   找不到 manifest 或键 → `warn`（沿用现状默认）。不允许两个键各自一套作用域。
4. 新增 `selfhost/ct-ast/ct.pkg`、`lib/core/ct.pkg`，内容仅注释 + `c-boundary = allow`。
5. 前置验证：`ct build` / `ct check` 读这两个 manifest 时，除 `c-boundary` 外不改包语义与产物形状。
   若报缺 `name`/`version` 或触发包模式 → **停，报证据**，不得改用路径豁免或全局 CLI allow。
6. 正负例（全部写进交付报告）：
   - `ct --show-c-boundary selfhost/ct-ast/<单元>` → `allow`；
   - `ct --show-c-boundary lib/core/<单元>` → `allow`；
   - `ct --show-c-boundary lib/core/utf16/<单元>` → `allow`（子树覆盖）；
   - 普通无 manifest 目录的 `.ct` → `strict`；
   - 删掉 `lib/core/ct.pkg` → `lib/core` 与 `utf16` 都回到 `strict`（验证后放回）；
   - 在 `lib/core/utf16/` 临时放一份 `c-boundary = strict` 的 `ct.pkg` → 该子树 `strict`（最近者为准，验证后删除）；
   - 包外目录的 `ct.pkg` 不影响包内单元；
   - `leaks`：同一个 `ct.pkg` 写 `leaks = error` 时子树按 `error`，父目录键不外溢。

判据：`gen-seed` + `check-seed` 两轮、`check-ast` 0 失败、`check-all` 8 门。

### M2 selfhost include-only shim 退场

1. 删 63 个 include-only shim；把系统头移进对应 `.h.ct` 顶部（合并去重）。
2. 保留 3 个有原型的 shim。
3. 判据：用户语料 25/25 逐字节（`CT_C_BOUNDARY=allow bash selfhost/check-goldens-ast.sh <ct>`）；
   `check-ast` fixpoint 0 失败；自举 2 轮；seed 两轮；`check-all` 8 门；`check-warnings` 0。
4. 报告：66 → 3；逐文件列出"删了哪个 shim → 哪个 `.h.ct` 接收了哪些 include"。

### M3 lib/core shim 退场（8 → 0）

1. 删 8 个 shim（6 个顶层 + `utf16/U16Str`、`utf16/U16String`）；
   include 移进对应 `.h.ct` 顶部（`Box` / `Option` / `Result` / `Str` / `String` / `Vec` /
   `utf16/U16Str` / `utf16/U16String`）。
2. 依据：`lib/core/ct.pkg` 是包根，覆盖含 `utf16/` 的整棵子树（D-032 §2 第 2 条）；
   **不要**为 utf16 再加一份 manifest。
3. 负例：`lib/core/utf16` 下临时放 `c-boundary = strict` 的 `ct.pkg` 时必须回到 `strict`（最近者为准）。
4. 注意 `.h.ct` 的 include 会进公开头；以 `check-warnings` 证明生成 C 零告警。
5. 判据同 M2；另：`bootstrap/ct-ast/*.shim.h` 68 → 3（utf16 不在编译器闭包内，seed 里本来就没有）。

## 4 统一门禁（每片）

```sh
bash selfhost/gen-seed.sh        # 失败先 git checkout -- bootstrap/ 再改代码重跑
cc -Wall -Wextra -std=c99 -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o /tmp/ct-dev
CT_C_BOUNDARY=allow bash selfhost/check-goldens-ast.sh /tmp/ct-dev   # 25/25
bash selfhost/check-ast.sh /tmp/ct-dev      # ~30-45 分钟，后台落日志
bash selfhost/check-seed.sh                 # 两轮逐字节 + 手改负例红
bash selfhost/check-all.sh                  # 8 门
bash selfhost/check-warnings.sh             # 0
python3 test/docs/check-docs.py
bash tools/check.sh g1 && bash tools/check.sh g6 && bash tools/check.sh g8
```

## 5 坑（均已实测）

- `ct_scratch_fmt` 必须写 `tool::sh::ct_scratch_fmt`；裸名报
  `that function lives in another namespace and needs a qualified call`。
- `gen-seed.sh` 在 emit 失败时会先清空 `bootstrap/ct-ast/`；失败后先 `git checkout -- bootstrap/`。
- `check-goldens-ast.sh` 不带 `CT_C_BOUNDARY=allow` 会红 5 个 `#include` 负例，不是回归。
- 内置层不在 `-I` 根里：只加 `lib/core/ct.pkg` 而不做 M1 的回退，manifest 是死文件。

## 6 回滚

| 对象 | 动作 | 结果 |
| --- | --- | --- |
| 任一片 | `git revert <该片提交>`（含 seed） | 回到片前；goldens/seed 一致 |
| M1 回退 | 单独 revert | `c_boundary_for` 回到只查 `-I` 根；两处 manifest 失效但无害 |
| M2/M3 | 单独 revert | shim 恢复；include 位置回到 shim |

## 7 交接

| 席位 | 事项 |
| --- | --- |
| DEV（A 轨道，单写者） | 按 M1 → M2 → M3 实施，各片独立提交；独占 seed |
| REV | 签 D-032 `accepted`；实施后只读复核（`--show-c-boundary` 正负例、门禁末行、shim 计数），写评审结论；不改代码 |
| REQ | 验收 E-V3-10 新口径；更新卡 §6 与 S10 清单；必要时补 CR 记录 |
