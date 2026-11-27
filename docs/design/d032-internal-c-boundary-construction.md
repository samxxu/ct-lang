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
| 删 69 个 include-only shim，include 移回对应 `.h.ct` | 不改消费者默认（strict 仍是默认） |
| 保留 3 个有 C 原型的 shim + `lib/core/utf16` 的 2 个 | 不扩 §4.67 补头集合 |
| seed 重生成与对齐 | 不改版本号、不打 tag、不动 `examples`/`test` |

## 2 基线（2026-11-28 实测）

| 项 | 数 |
| --- | --- |
| `selfhost/ct-ast/**/*.shim.h` | 66（63 个只有 `#include`） |
| `lib/core/*.shim.h` | 6（全部只有 `#include`） |
| `lib/core/utf16/*.shim.h` | 2（`U16Str` / `U16String`，全部只有 `#include`；**保留**） |
| `bootstrap/ct-ast/*.shim.h` | 68 |
| 需保留的 shim | selfhost：`Module`、`ModuleBoundary`、`Pkg`（有原型）；lib/core：`utf16/U16Str`、`utf16/U16String`（不在 manifest 目录内） |

## 3 切片

### M1 解析回退 + 两处 manifest（编译器改动）

1. `frontend/module/Module.h.ct` 的 `c_boundary_for`：在 `-I` 根循环之后加回退
   `path_dir(path)` → `c_manifest_boundary(dir)`，`>= 0` 即返回；注释写明与
   `leaks_for` 同序（CLI/env → `-I` 根 → 单元目录 → strict）。
2. 新增 `selfhost/ct-ast/ct.pkg`、`lib/core/ct.pkg`，内容仅注释 + `c-boundary = allow`。
3. 前置验证：`ct build` / `ct check` 读这两个 manifest 时，除 `c-boundary` 外不改包语义与产物形状。
   若报缺 `name`/`version` 或触发包模式 → **停，报证据**，不得改用路径豁免或全局 CLI allow。
4. 正负例：两处单元 `ct --show-c-boundary` 均 `allow`；临时移走任一 `ct.pkg` 后回到 `strict`（验证后放回）。

判据：`gen-seed` + `check-seed` 两轮、`check-ast` 0 失败、`check-all` 8 门。

### M2 selfhost include-only shim 退场

1. 删 63 个 include-only shim；把系统头移进对应 `.h.ct` 顶部（合并去重）。
2. 保留 3 个有原型的 shim。
3. 判据：用户语料 25/25 逐字节（`CT_C_BOUNDARY=allow bash selfhost/check-goldens-ast.sh <ct>`）；
   `check-ast` fixpoint 0 失败；自举 2 轮；seed 两轮；`check-all` 8 门；`check-warnings` 0。
4. 报告：66 → 3；逐文件列出"删了哪个 shim → 哪个 `.h.ct` 接收了哪些 include"。

### M3 lib/core shim 退场（8 → 2）

1. 删 6 个**顶层** shim；include 移进 `Box` / `Option` / `Result` / `Str` / `String` / `Vec` 的 `.h.ct`。
2. **保留 `lib/core/utf16/U16Str.shim.h` 与 `U16String.shim.h`**：utf16 是 `lib/core` 的子目录，
   manifest 回退只看单元自身目录，`lib/core/ct.pkg` 不覆盖它；不为 2 个文件再加第三处 `ct.pkg`
   （D-032 §3 的 B2/B3 已记录不采纳理由）。
3. 负例：`ct --show-c-boundary lib/core/utf16/<任一单元>` 必须报 `strict`。
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
