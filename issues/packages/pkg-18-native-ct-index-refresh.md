# PKG-18 · v1.1：原生 `ct index refresh`（替代 shell 生产链）

| 项 | 值 |
| --- | --- |
| 模块 | packages（原生索引生产） |
| 定性 | **特性**（不是 bug；v1-pre 冻结期不实现） |
| 严重度 | Medium |
| 目标版本 | v1.1（Wave 2 候选；由 [v1 路线](../planning/v1-release-plan.md) 排期确认） |
| 锚点 | v0.84.1（2026-11-21） |
| 依据 | 用户 2026-11-21 裁决；[D-014](../decisions/D-014.md) 第 1 条；[契约 v1](../planning/ct-pkg-get-contract.md)；[对齐清单](../planning/ct-pkg-index-alignment.md) |
| 状态 | verified |
| 处置证据 | **提案（v1.1；冻结期只登记，不实现）** |

## 背景

当前索引生产在 `ct-pkg/index` 仓的 shell 链：`refresh-index.sh` / `gen-index.sh` /
`package.sh` / `verify-index.sh`。D-014 第 1 条维持 B′，只把**只读** `ct index verify`
收进 `ct`，发布与索引生成留在 index CI。

用户 2026-11-21 裁定：原生 `ct index refresh` 缺失是**特性**，按 v1-pre 冻结纪律归 v1.1；
冻结期不实现。index 仓的 `verify_row` 在找不到 `ct` 时 `warn` 并成功，是 index 仓的 bug，
另派单修复，不在本仓范围。

## 目标

1. `ct index refresh` 从固定的包清单/仓库集合生成六字段 `index` 行；
2. 生成器与消费者共用同一 digest 算法、同一行模型、同一身份校验；
3. 默认执行回放校验：用生成的 index 跑 `ct get --index` 指定行，摘要必须匹配；
4. 产出确定、可 diff、原子替换；失败不写半成品索引；
5. 为 index 仓 workflow 提供可直接替换 shell 生产链的命令。

## 非目标

- 索引签名、pin、多索引并存、自动发现 org 下所有仓库；
- 发布 tag、建仓、推包仓（仍属 index 仓/包仓 CI）；
- 新索引字段（如 `min-compiler`）、新行格式；仍只写六字段；
- 在 `ct` 内内置 HTTP 客户端；需要取源码时只走 `git` 子进程（与 `ct get` 同一约束）；
- 凭据进入通用二进制。

## 判据（必须逐条满足）

| ID | 断言 |
| --- | --- |
| P18-1 | `ct index refresh` 生成六字段行；`ct index verify` 对该文件返回 0；`ct get --index` 能回放至少一个标准 fixture |
| P18-2 | **回放失败处理不得继承 Q2**：找不到 `ct` 或回放失败时**硬错退出**；唯一例外是显式 `--no-verify`，且必须写审计记录（时间、索引摘要、被跳过的行/包、原因、操作者），审计记录不得静默丢弃 |
| P18-3 | 确定性：同一输入（包清单 + tag + 包树）重复运行，`index` 逐字节一致；按 `name`、版本排序 |
| P18-4 | 原子性：先写临时文件再替换；任一步失败保持原 `index` 不变；不 force push、不改已存在的行 |
| P18-5 | 与消费者同源：digest 算法、`sha256:<64 lowercase>` 拼写、publisher/`ns-root`/tag 校验与 `ct get` / `ct index verify` 共用实现或共用 conformance 向量 |
| P18-6 | 双 job 门禁：host + Linux x64 均跑 `ct index refresh` → `ct index verify` → `ct get --index` → `ct install` → 运行比对 |
| P18-7 | 回滚切片：命令本身可单提交撤回；不改变 `ct get` / `ct.lock` / store 的既有格式 |
| P18-8 | **shell 生产链退场是独立可回滚切片**：先让 `ct index refresh` 与 shell 链并行一个完整刷新周期并比对 `index` 逐字节一致；确认后再关 shell 链。退场提交只改 workflow/脚本调用，不混入命令实现 |

## 接口与兼容

- 输入：包清单（`packages.txt` / `repos.txt` 的固定集合）与包仓 tag；具体键沿用 index 仓现行布局，不在本卡发明新配置格式；
- 输出：单个 `index` 文件，六字段；五字段旧行不生成、读到即硬错（D-014 第 5 条）；
- 消费兼容：`ct get` / `ct install` / `ct.lock` 不改格式；生成器只写索引，不改包树；
- 与 `ct index verify` 的关系：verify 是只读 oracle，refresh 不得绕过它；P18-2 的回放是**额外**校验，不替代 verify。

## 门禁与证据

```sh
# 生成
ct index refresh --packages <list> --out <tmp>/index

# 只读校验
ct index verify <tmp>/index

# 回放（隔离 HOME / CT_HOME）
HOME=<tmp>/home CT_HOME=<tmp>/cthome \
  ct get --index <tmp>/index <publisher>/<name>@<version>

# 安装与运行比对
ct install
<run expected output> && diff -u <expected> <actual>
```

- fixture：官方 `ct/std@0.19.0` + 第三方 fixture（[PKG-17](pkg-17-third-party-fixture-ci.md)）+ 五字段 legacy 负例；
- 无 `ct` 时硬错：`env -u CT_BIN -u PATH ...` 的负例必须非零退出并给可用诊断；
- `--no-verify` 审计痕：测试断言审计文件存在且含 `index-sha256` / `skipped` / `reason`；
- 并行周期比对：shell 链与本命令各生成一次，`diff` 为空才允许退场。

## 冻结纪律

- 本卡在 v0-PH-85…88 冻结窗口内**只登记、不实现**；不占用重写卡合入窗口；
- 实现前置：v1-pre 收口（v0-PH-88）且 v1.0 发布；
- 若实现需要新索引字段或新配置格式，先改契约并重新过 ADR，不在本卡夹带。

## 关联

- [PKG-21](pkg-21-ct-pkg-index-refactor-ruling.md)（总跟踪）
- [D-014](../decisions/D-014.md)、[契约 v1](../planning/ct-pkg-get-contract.md)
- [消费侧对齐清单](../planning/ct-pkg-index-alignment.md)
- [PKG-15](pkg-15-conformance-suite.md)、[PKG-17](pkg-17-third-party-fixture-ci.md)
- index 仓 `verify_row` 的 Q2 行为：另派单修复，不在本仓

## 复核（REV，2026-11-23）

`ct index refresh --packages <list> --out <index> [--check]` 本地切片：六字段生成、排序、
重复/坏包行号、`--check` 不写、原子 rename；探针 43 ok（generate/errors/atomic/concurrency/replay）；
与 PKG-17 fixture 的 shell 产物逐字节一致；check-all 12 门绿。
