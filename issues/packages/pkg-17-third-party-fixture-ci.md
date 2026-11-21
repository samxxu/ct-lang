# PKG-17 · 第三方真实包 fixture 与 `ct index verify` 进 CI

| 项 | 值 |
| --- | --- |
| 模块 | packages / CI |
| 定性 | 能力缺口（v1.0 包体系收尾） |
| 严重度 | Medium |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [ct-pkg-get-contract.md](../../docs/planning/ct-pkg-get-contract.md)、[D-014](../../docs/decisions/D-014.md)、[PKG-14](pkg-14-ph83-index-verify-and-binary.md) |
| 状态 | **实施中（REQ fixture 规格已出；DEV 建 fixture + 接 CI）** |

## REQ 规格（2026-11-21，方案 A：仓库内 vendored 快照）

### 1. Fixture 布局（极小化）

```
test/pkg/fixtures/thirdparty/
  README.md                 # 来源、版本、sha256、生成命令、离线边界
  pkg/hello/                # demo/hello 0.1.0：一个 .h.ct + 一个消费者
    ct.pkg                  # publisher=demo, name=hello, version=0.1.0, 无 dep
    src/hello.h.ct          # 一个 pub 函数（最小可编译单元）
  consumer/main.ct          # import demo::hello 并调用；ct build 可跑
  index/six                   # 六字段行（正例）
  index/five                  # 五字段旧行（负例：按行硬错）
  index/bad-digest            # 六字段 + 错误 sha256（负例：摘要不符硬错）
```

- 包内容**只保留证明安装/构建所需的最小面**：不引入真实第三方包的完整功能，不复制其源码历史；
- `url` 必须是**离线可解析**的本地形式（本地 git 仓 / `file://` / 契约允许的本地路径）；
  具体形式由 DEV 按 [D-014](../../docs/decisions/D-014.md) 与 [契约 v1](../../docs/planning/ct-pkg-get-contract.md) 选，
  但必须在 `README.md` 记录，并保证干净环境可重放；
- 六字段行必须与契约 v1 的字段顺序/大小写一致；摘要写进 README 与索引行，两处一致。

### 2. 三条正负用例（离线）

| 用例 | 命令 | 期望 |
| --- | --- | --- |
| 六字段可安装 | `ct index verify <six>` + `ct get --index <six> demo/hello` | index 校验通过；store 出现 `demo/hello/0.1.0`；`ct.lock` 六字段正确 |
| 五字段旧行 | `ct index verify <five>` / `ct get --index <five> demo/hello` | **按行硬错**，错误指向该行；不得静默降级 |
| 摘要不符 | `ct get --index <bad-digest> demo/hello` | 摘要硬错，不得写入 store / 不得改写既有 `ct.lock` |

三步都必须在隔离 `HOME` / `CT_HOME` 下执行，结束清理临时目录；除了本地 git/文件路径，不得联网。

### 3. D-010 三断言（进验收）

把 D-010 的裁定归纳为三条可执行断言：

| 断言 | 内容 | 用例 |
| --- | --- | --- |
| D-010-A 身份与裸名 | 官方规范名 `ct/std`；裸名 `std` 只解析官方；第三方必须 `publisher/name`；裸名命中多个 publisher 硬错 | 用 fixture 的 `demo/hello` 验证“裸 `hello` 不可解析”；再放一条同名不同 publisher 的负例验证硬错 |
| D-010-B 显式索引优先 | `--index` / `CT_INDEX` 命中 `publisher = ct` 行时以索引为准（内置 pin 表退让），不联网 | 在 fixture 索引里放一条 `ct/hello` 行，验证 `--index` 生效；不触发 pin 表 |
| D-010-C 发布回放 | 隔离 `HOME` / `CT_HOME` 用 `ct get --index` 回放索引行，摘要比对一致；找不到 `ct` 不得跳过 | 与上面三步同一隔离环境执行；把“`ct` 缺失”做成显式失败而不是 skip |

### 4. Fixture 变更 = golden 变更

- fixture 的包内容、索引行、sha256 **一经入库视同 golden**：
  - 改动必须单独提交，提交说明写原因与影响面；
  - 包内容变化必须 bump `version` 并同步 README 的 sha256 与索引行；
  - 不允许“为了让测试变绿”而改 fixture；测试期望随 fixture 一起改时必须同提交说明。
- `README.md` 必须记录：来源（vendored 快照的原始出处/生成方式）、版本、sha256、
  重新生成命令、离线边界；缺任一项视为 fixture 不完整。

### 5. CI 三步独立失败定位

在 `test/pkg/run.sh` 增加 `PKG-17` 段，三步各自输出独立结果，任一失败即非零，
且**失败信息必须能定位到步骤**：

1. `pkg17-index: OK|FAIL` — 六字段通过 + 五字段/坏摘要按行硬错；
2. `pkg17-get: OK|FAIL` — `ct get --index` 安装与 store/lock 断言（隔离 HOME/CT_HOME）；
3. `pkg17-build: OK|FAIL` — 消费者 `ct build` + 运行输出。

不允许把三步压成一个 `ok`；CI 日志里三步各自可搜。先把三步做成 `test/pkg/run.sh` 的
附加段（不新增硬门禁条数），稳定后再评估是否单独成 gate。

## 现象

`ct index verify` 已实现（PH-83），但常规 CI 尚未覆盖；第三方身份路径缺少一个可重放的
真实包 fixture，无法证明“非官方 publisher 可安装”。

## 期望

1. 选一个**固定、可离线重放**的第三方包 fixture（vendored 或固定 commit + 摘要）；
2. CI 常规跑：`ct index verify` + `ct get --index` + `ct build`，验证：
   - 六字段行可安装；
   - 五字段旧行按行硬错；
   - 摘要不符硬错；
3. 不依赖网络；若必须联网，标为外部依赖并给手动步骤；
4. fixture 的版本/摘要写进测试说明，防漂移。

## 验收

- CI 有独立断言，失败可定位到具体步骤；
- fixture 与契约 v1 的 spec 形态一致；
- 不改变发布边界（不做 release/index 生成）。

## 关联

- [D-014](../../docs/decisions/D-014.md)、[PKG-13](pkg-13-legacy-five-field-row-hard-error.md)、[v1 路线 §1.5](../../docs/planning/v1-release-plan.md#L57-L71)
