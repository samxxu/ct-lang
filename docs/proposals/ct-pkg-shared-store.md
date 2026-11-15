# 提案：ct-pkg 共享库包体系（发布方 / 包名 / 版本）

| 项 | 值 |
| --- | --- |
| 状态 | **已裁定**（2026-11-15，§12 五问已由负责人拍定；条款按 §12 修订，不含实现） |
| 范围 | `ct get` / `ct install` / `ct update` / `ct verify`、`ct build` 的 `-I` 生成、`ct.pkg` / `ct.lock` 格式、ct-pkg 各包仓布局 |
| 契约变更 | **本提案改的是既有契约**：`docs/package-guide.md` §1 现写死「包根即包根、单元与 `ct.pkg` 并列不嵌套」，本提案以 `ns-root` 取代该隐含约定；`ct install` 的 `-I vendor/<name>` 输出契约同时作废。不是「加几个字段」 |
| 现状核对 | `ct v0.53.0` 实测：包固定落 `./vendor/<name>`；无共享库；`ct.pkg` 的 `ns-root` 无读取点；`ct install` 固定打印 `-I vendor/<name>`；同名包静默取首个；`ct build` 不读 `ct.lock`（详见核对报告，未入库） |
| 不做 | 新语言关键字、私库鉴权、GC/沙箱、传递更新的 MVS 策略变更 |

## 0. 结论

1. **包身份 = `<publisher>/<name>`**，磁盘 = `~/.ct/pkg/<publisher>/<name>/<version>/`。
2. **`import` 只写包名与单元**（`import <name>::<Unit>`），发布方不进源码；因此同一依赖图内包名必须唯一，重名即硬错。
3. **项目根只留 `ct.pkg` 与 `ct.lock`**；`vendor/` 进入兼容期后删除。
4. **`ct build` 默认读 `ct.lock` 生成 `-I`**，不再要求消费者手抄 `ct install` 的输出；`--locked` 供 CI 强校验（lock 与库不一致立即失败）。
5. **包自己用 `ns-root` 声明单元树根**，工具据此拼 `-I`，取消「包根下同名目录」这一隐含约定。
6. **库内多版本可并存，单工程只解析一个版本**：磁盘按版本分目录，lock 一包一行，同一次构建不得同包两版本（C 无模块隔离，必然符号冲突）。

## 1. 目录与共享库

```
$CT_HOME/pkg/                 # CT_HOME 默认 $HOME/.ct，可用环境变量覆盖
  ct/std/0.1.0/               # 发布方 ct / 包 std / 版本 0.1.0
  ct/std/0.2.0/
  ct/http/0.1.0/
  abc/its-package/1.0.0/
```

- 每个版本目录 = 一份完整包树（`ct.pkg` + `ns-root` 下的单元 + LICENSE + 其它文件）。
- **版本目录不可变**：同版本重复安装只做摘要校验；摘要不符报错，不覆盖。升级 = 新增目录。
- 删除某版本只能由 `ct pkg gc`（显式命令）执行，不在 `get`/`install` 中隐式回收。
- 发布方与包名字符集同为 `[a-z0-9][a-z0-9-]*`；`publisher` 由 `ct.pkg` 声明，与 git 组织解耦（`github.com/ct-pkg/std` 的 publisher 写作 `ct`）。
- git 侧的 `~/.cache/ct-pkg` 退化为纯传输缓存，**键改为 `<publisher>/<name>`**；不得再用裸名（现状 `ct get foo/http` 会复用 `ct-pkg/http` 的克隆，见核对报告 §9）。

## 2. 解析顺序

对 `ct.pkg` 里每一条 `dep = <publisher>/<name>@<range>`：

1. **当前目录覆盖**：`./<name>/ct.pkg` 存在且 `name` 匹配 → 用本地目录，lock 记 `dir`，构建时打 `dev override` 提示。显式 `./path`、`file://`、绝对路径同属这一档。
2. **共享库**：lock 已钉 `<version>` 且 `$CT_HOME/pkg/<publisher>/<name>/<version>` 存在 → 直接用，零网络、零子进程。
3. **联网**：仅 `ct get` / `ct update` 允许。git 解析出 commit → 校验摘要 → 落共享库 → 写 lock。
4. **`ct install` / `ct build` 只走 1、2**；缺任何一项即硬错，绝不隐式下载。

版本选择沿用 MVS（满足范围的最低版本）；lock 已钉版本时以 lock 为准，`ct update` 才重解。

## 3. `ct.pkg` 字段

行式 `key = value`，`#` 注释，`dep` 可重复，未知键忽略（向前兼容）。

| 键 | 必填 | 含义 |
| --- | --- | --- |
| `name` | 是 | 包名，`[a-z0-9][a-z0-9-]*`；依赖图内唯一 |
| `publisher` | 是 | 发布方，store 一级目录；`dir` 源也必须写真实发布方，不接受推导或 `local` 占位（D1） |
| `version` | 是 | `x.y.z` |
| `ns-root` | 是 | 单元树根，相对路径、无 `..`、目录必须存在；**无默认值**，缺键硬错（D2） |
| `dep` | 否 | `<publisher>/<name>@<range>`，可重复 |
| `cflags` / `ldflags` | 否 | 消费者构建选项；`-I` 只允许相对包根 |
| `requires` | 否 | 编译器版本约束 |
| `licence` | 否 | SPDX 标识（约定，工具不解析） |

- 现状键 `namespace`（`Module.h.ct` `ct_rel_cands` 读的「剥首段」键）**不进入本提案**：它与 `ns-root` 语义相反且未文档化；评审通过后由 `ns-root` 取代，旧键保留兼容但不再推荐。
- `ns-root` 显式必填，避免「靠目录名猜根」再现。

## 4. `ct.lock` v2

首行格式头，随后每包一行：

```
# ct-lock 2
<publisher>/<name> <version> git <url> <commit> <ns-root> sha256:<64hex>
<publisher>/<name> <version> dir <resolved-path> - <ns-root> sha256:<64hex>
```

- 相对 v1 新增：**发布方**、**ns-root**、格式头；`git` 行显式记 url 与 commit，`dir` 行记解析后的绝对路径并以 `-` 占位 commit。
- 无格式头的旧 lock 识别为 v1：`ct install` 告警并提示 `ct migrate` / `ct update`，不静默按 v2 解释。
- 同一包只有一行；多版本共存指「不同包各自钉版本」，不是同一包多版本同时进图（多版本同图仍按 MVS 取一）。

## 5. `-I` 生成规则

唯一生成点（替代 `Pkg.h.ct:1388-1396`）：

```
-I $CT_HOME/pkg/<publisher>/<name>/<version>/<ns-root>      # git 源
-I <resolved-path>/<ns-root>                                # dir 源（dev override）
```

- `ns-root = .` 时路径收敛为版本目录本身，不做多余拼接。
- `ct install` 打印完整命令（含 `--cflags` / `--ldflags`）；`ct build` 读 lock 时自动追加同样的 `-I`，用户显式 `-I` 仍然有效并优先，重复根去重，两处同名单元仍按现状报 `unit '…' exists in two import roots`。
- `ct build` **默认读 `./ct.lock`**；`--locked` 为 CI 强校验模式：lock 与共享库不一致（版本目录缺失、摘要不符、`dir` 行在白名单外）立即失败，不做任何回退。
- 无 `ct.lock` 的工程退回 `vendor/` 并打警告：`ctc: warning: no ct.lock; reading vendor/ (legacy layout)`；`vendor/` 也没有时保持现状（无包可用，不额外报错）。

## 6. 冲突与本地覆盖

| 情形 | 行为 |
| --- | --- |
| 依赖图内同名包（同发布方或不同发布方） | **硬错**：`package '<name>' is required twice: <publisherA> and <publisherB>` |
| 索引里裸名对应多个发布方 | 硬错：`'<name>' is ambiguous; write <publisher>/<name>` |
| 本地目录与共享库同时存在 | 本地胜出 + 每次构建 `note: '<name>' resolves to the local directory (dev override): <path>`；lock 记 `dir` |
| CI 拒绝 dev override | `ct verify --strict`：lock 含 `dir` 行即失败 |
| 两版本目录同时存在 | 按 lock 选择；未钉版本出现在 `dep` 时按 MVS 选最低满足版本 |

`dev override` 的留痕必须同时出现在两处：`ct.lock` 的 `dir` 行 + 构建 stderr 的 `note:`。现状只有 `dir` 行，构建期无提示。

## 7. 发布与 tag

1. 仓根放 `ct.pkg`（含 `publisher` / `ns-root`）。
2. 版本 = tag：打 annotated tag `v<version>`，tag 提交上 `ct.pkg` 的 `version` 必须与 tag 完全一致；tag 必须是默认分支可达提交（禁止游离 tag）。
3. 索引行扩展为六字段：`name version publisher git-url tag sha256:<64hex>`。
4. 引用方式：`ct get <publisher>/<name>@<range>`；裸名仅在索引中唯一时可用。
5. 破坏性变更换主版本；不做传递更新策略变更。

## 8. 错误文案（固定字符串，供门禁断言）

| 场景 | 文案 |
| --- | --- |
| manifest 缺字段 | `ctc: '<dir>/ct.pkg' is missing '<key>'` |
| ns-root 不存在 | `ctc: ns-root '<path>' of '<publisher>/<name>' is not a directory` |
| ns-root 绝对/越界 | `ctc: ns-root '<value>' must be a relative path without '..'` |
| 包同名冲突 | `ctc: package '<name>' is required twice: <a> and <b>` |
| 裸名歧义 | `ctc: '<name>' is ambiguous; write <publisher>/<name>` |
| 库里缺版本 | `ctc: '<publisher>/<name>@<version>' is not installed; run 'ct get'` |
| 摘要不符 | `ctc: '<publisher>/<name>@<version>' does not match ct.lock (store <a>, lock <b>)` |
| dev override | `ctc: note: '<name>' resolves to the local directory (dev override): <path>` |
| 旧 lock | `ctc: ct.lock is v1; run 'ct migrate' (or 'ct update') to write v2` |
| import 解析不到 | 沿用 `ctc: cannot resolve import '<rel>'`（不新增文案） |

## 9. 包仓库判据（可直接做成门禁）

`R` = 包仓根；`NR = $(ct pkg get ns-root)`。

| ID | 判据 | 验收 |
| --- | --- | --- |
| PK-1 | `R/ct.pkg` 存在且可解析 | `ct pkg check R` |
| PK-2 | `name` / `publisher` / `version` / `ns-root` 非空 | `ct pkg check R --fields` |
| PK-3 | `name`、`publisher` 字符集合规 | 同上 |
| PK-4 | `version` 为 `x.y.z`，且与 tag `v<version>` 一致 | `git describe --tags --exact-match` |
| PK-5 | `ns-root` 相对、无 `..`、目录存在 | `test -d "R/$NR"` |
| PK-6 | `ns-root` 下每个可导入单元的命名空间 = 相对路径（`::`→`/`），首段唯一 | `ct build --ns-root "R/$NR" <units>` |
| PK-7 | `ns-root` 下至少一个 `.h.ct` / `.m.ct` 公开单元 | `find "R/$NR" -name '*.h.ct' -o -name '*.m.ct'` |
| PK-8 | 包内无指向自身绝对路径的 `-I` | `grep -rn -- '-I */' --exclude-dir=.git R` |
| PK-9 | `cflags` 中 `-I` 只能相对包根且目录存在 | `ct pkg check R --flags` |
| PK-10 | 依赖一律 `<publisher>/<name>@<range>`，无裸名、无无版本依赖 | `ct pkg check R --deps` |
| PK-11 | 依赖图内包名唯一 | `ct install` 解析期 |
| PK-12 | 每个单元都能从 `ns-root` 按 `import` 解析（离线） | `ct pkg check R --resolve` |
| PK-13 | tag `v<version>` 且为 HEAD 可达提交 | `git merge-base --is-ancestor <tag> HEAD` |

## 10. 迁移切片（先工具、后包、最后收口）

每片可单独回滚；每片落地前仓库必须可构建。

### S0 · 观测与防回归（工具）

- 交付：`ct pkg check` 只读子命令骨架（PK-1/2/5/8）、lock 格式头识别（读到 v1 只告警）、`ct install` 输出旁加 `# lock-format: v1` 注释行。
- 判据：旧工程 `ct install` 输出除注释行外逐字节不变；`ct pkg check` 对 `ct-fsguard` 判出缺 `publisher`。
- 验收：`ct pkg check ../ct-fsguard; echo $?` → 非 0；旧 `test/pkg/run.sh` 全绿。
- 影响：无行为变更。

### S1 · 最小可用（工具，必须先于任何包仓改动）

- 交付：`ct.pkg` 读 `publisher` / `ns-root`；`$CT_HOME/pkg` 布局；`ct get` 落共享库；lock v2 写入；`ct install` 按 lock 拼 `-I …/<ns-root>`。
- 判据：`src/<ns>/` 布局的包，`ct install` 打印的 `-I` 可直接解析；同版本重装不覆盖。
- 验收：`ct get <pkg> && ct install` 打印 `-I ~/.ct/pkg/<pub>/<name>/<ver>/src`，照抄 `ct build` RC=0。
- 影响：仍写 `vendor/`（兼容），但 `ct install` 改读共享库。

### S2 · 编译读 lock（工具）

- 交付：`ct build` 读 `./ct.lock` 自动补 `-I`；dev override 的 `note:`；同名包硬错；裸名歧义硬错。
- 判据：无 `-I` 也能构建；两个同名包 `ct install`/`ct build` 报 PKG 冲突；`dir` 行触发 `note:`。
- 验收：`ct build main.ct -o build`（不给 `-I`）RC=0；`ct build` 在两个同名包工程 RC=1 且文案匹配 §8。
- 影响：下游构建命令可精简，旧命令仍可用。

### S3 · 校验与迁移（工具）

- 交付：`ct verify` 校验 store（摘要 + ns-root 存在）；`ct migrate`（vendor → store，重写 lock v2）；`ct update` 按 v2 重解；`ct verify --strict` 拒绝 `dir` 行。
- 判据：篡改 store 报摘要不符；`migrate` 后 `build` 无需 `vendor/`；`--strict` 在 dev override 下 RC=1。
- 验收：`ct migrate && mv vendor /tmp/v && ct build main.ct -o build` RC=0。
- 影响：可开始删除 `vendor/`。

### S4 · 包仓声明对齐（包侧，按仓逐个提交）

- 交付（逐仓）：
  - `std`：`publisher = ct`、`ns-root = .`；处理 `v0.2.0` 游离 tag（并回 main 或重打）。
  - `ct-http`：`publisher = ct`、`ns-root = .`；`test/gates/p10_install.sh` 改断言 store 路径。
  - `ct-fsguard`：`publisher = ct`、`ns-root = src`；`cflags` 去掉 `-Isrc`（由 ns-root 推导）；打 `v0.1.0`。
  - `ct-json`：`publisher = ct`、`ns-root = src`；修 `src/json.h.ct:84`；确定 `import` 形态；打 tag。
  - `ct-sse`：`publisher = ct`、`ns-root = .`；打 `v0.11.0`。
  - `ct-token` / `ct-process` / `ct-llm-sse`：补 `publisher`、`ns-root`；依赖改 `<publisher>/<name>@<range>`；明确「规格占位」或补单元。
  - `nexcore` / `swiftct`：登记为「非 ct 包」，不补 `ct.pkg`。
- 判据：每仓 `ct pkg check` 的 PK-1/2/4/5/6/10/12 全绿。
- 验收：`ct pkg check <repo>` RC=0；`ct get <publisher>/<name>@<range> && ct install` 后消费者 RC=0。
- 影响：`ct-json` / `ct-token` / `ct-llm-sse` / `ct-process` 在本片之前不可消费，属既有状态，不因本片回退。

### S5 · 消费端与门禁切换（收口）

- 交付：各仓 `test/`、`tools/` 去掉手算 `-I`；`ct-lang` 的 `test/pkg/run.sh` 增加共享库用例；安装脚本提示改为新命令。
- 判据：全仓无 `-I vendor/` 硬编码；两个临时 HOME 下同一 lock 构建结果一致（可复现性）。
- 验收：`grep -rn -- '-I vendor/' --exclude-dir=.git .` 零命中；`HOME=/tmp/h1` 与 `HOME=/tmp/h2` 各自 `ct get && ct build` 产物一致。
- 影响：旧文档全部失效，需与 S6 同批发布。

### S6 · 文档与 errata（收口）

- 交付：`docs/package-guide.md`、`docs/tutorial.md`、`README(.en).md`、`install.sh` 按新机制改写；历史 phase 文档按 errata 加一节「已被共享库取代」，不改正文。
- 判据：全仓 `grep -rn "vendor/" docs README*.md install.sh` 只剩兼容期说明。
- 验收：上述 grep 结果逐条人工确认。
- 影响：无代码。

### S7 · 删除 `vendor/` 支持（兼容期结束后）

- 交付：移除 `vendor/` 读写路径与 deprecation 提示；`ct install` 遇到 v1 lock 只报错并指向 `ct migrate`。
- 判据：无 v1 lock 的工程全部可构建；`test/pkg/run.sh` 的 vendor 用例改为 `ct migrate` 用例。
- 验收：`ct install` 在 v1 lock 下 RC=1 且文案匹配 §8。
- 回滚：恢复 S3 的读路径（保留一个 minor）。

## 11. 兼容期

- **共存**：S1–S5 期间 `ct get` 同时写共享库与 `vendor/`；`ct install` / `ct build` 优先共享库；**无 `ct.lock` 的工程退回 `vendor/` 并告警**（D5），已有 v1 lock 的工程按 `dir`/vendor 语义继续读。
- **提示**：`ct install` 对每个仍从 `vendor/` 取包的依赖打印一次
  `ctc: warning: '<name>' is read from vendor/ (v1); run 'ct migrate'`，同一进程最多一次/包。
- **删除前置条件**：连续两个 minor 版本无 v1 lock 工程；`ct migrate` 覆盖全部已知包；`ct pkg check` 在全部已知包上 PK-6/12 绿。
- **删除动作**：S7。删除前不得移除 `ct migrate`（保留下载/重装能力）。

## 12. 裁定结果（2026-11-15，负责人）

以下五条为**已裁定**，不再讨论；与裁定前文本的差异以本节为准。

| # | 裁定 | 被取代的提案文本 | 影响条款 |
| --- | --- | --- | --- |
| D1 | `publisher` **必填**，不从源推导（`dir` 源、镜像、仓库搬家三种情况都会歧义） | §3「本地开发可写 `publisher = local`」的宽松写法；§7「与 git 组织解耦」仅保留命名建议，不再允许推导 | §3、§7、§8、PK-2 |
| D2 | `ns-root` **必填**，缺失即硬错并给修复提示；**不留 `.` 默认值**（隐式默认正是当前缺陷来源） | §3 表格中「`src` 或 `.`」的可选语气、§3 末尾「默认 `.`」；§9 PK-5 的 `NR` 取值路径不变，但缺键即失败 | §3、§8、PK-2、PK-5 |
| D3 | **接受「包名全局唯一」**：`import` 不带发布方是既定口径，依赖图内重名硬错 | 无文本冲突，改为显式代价声明 | §0-2、§6、PK-11 |
| D4 | **库内多版本可共存，单工程只解析一个版本**：磁盘按版本分目录并存，lock 一包一行，同一次构建不允许同包两版本 | §4 末尾的模糊表述（「不是同一包多版本同时进图」）改为明确禁令与原因（C 无模块隔离） | §1、§4、§6 |
| D5 | **`ct build` 默认读 lock**；`--locked` 供 CI 强校验（不一致立即失败）；无 lock 的工程退回 `vendor/` 并打警告 | §5 原「`ct.lock` 存在即读；不存在不报错」；§11 「`vendor/` 仅在 lock v1 时被读」扩展为「无 lock 也读」 | §2、§5、§11、S2 |

裁定后的验收条目见 [planning/ct-pkg-shared-store-requirements.md](../planning/ct-pkg-shared-store-requirements.md)。
