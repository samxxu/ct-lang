# battle/index-pkg-1 — 反证书（主张 B）

| 字段 | 值 |
| --- | --- |
| 主张 | B：`ct pkg` 保持包管理/只读；`package.sh` 留在 index 仓 CI 或独立 `ct-pkg` 工具；init 只拉索引/校验，不执行脚本 |
| 基线 | `a979ce0d`（v0.65.1）；`ct` 由该提交源码自举为 `/tmp/ct-b/bin/ct`（`ct v0.65.1`） |
| 环境 | macOS / Apple clang / `git`；`CT_HOME` 一律隔离到 `/tmp/counter-home` |
| 外部证据 | `ct-pkg/index` 只读快照 `37fa8a3`（`~/dsh-ws/ct-pkg-index`）；只跑过只读的 `package.sh check`，未执行任何写操作 |
| 不可复现项 | A 的 `init`/透传未实现（`ct pkg init` → `unexpected argument`），A 侧行为用等价命令探针，不称实测 |

## 1. B 的命令边界

| 层 | B 的边界 | 现状锚点 |
| --- | --- | --- |
| `ct pkg` | 维持 `ct install` 别名语义：读 `./ct.lock` 装包；不 exec 外部脚本 | `selfhost/ct-ast/main.ct:121-122` |
| `ct pkg check` | 纯进程内只读审计（PK-1/2/5/8），无子进程 | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:1744-1748` |
| 索引 | 无内置索引；只有用户显式 `--index` / `CT_INDEX` 才解析裸名 | `Pkg.h.ct:133`、`Pkg.h.ct:1130-1150` |
| init | 若做，只「取固定 ref → 校验摘要/签名 → 原子替换」，不执行仓内脚本；init 失败不阻断 `ct` | `battle/index-install-1/verdict.md:27`、`docs/proposals/ct-pkg-index-proposal.md:59` |
| 发布 | 只走 index 仓维护者路径（`tools/package.sh publish/release`）或 index CI；`ct` 不接触 token | `battle/index-install-1/verdict.md:4`、`AGENTS.md:543-547` |

B 不等于「禁止 init」：B 允许只读索引拉取，禁的是把 `ct pkg` 变成「任意参数 + 任意脚本」的执行口。

## 2. E1 命令 + 原始输出

### E1-1 原生只读（利 B）
```console
$ ct pkg check /tmp/counter-pkg/good; echo "rc=$?"
ok: 4 criteria
rc=0
$ shasum -a 256 /tmp/counter-pkg/good/ct.pkg   # 运行前后各一次，输出同一行
22bb9302d29b27809ae4f7910784bd538146e863ed3ef8d18672e363a17db44a  /tmp/counter-pkg/good/ct.pkg
```

### E1-2 不利 B：用户要多一步、入口不统一
```console
$ ct pkg publish json
ctc: unexpected argument 'publish'
rc=1
$ ls "$HOME/.ct/index/package.sh"
ls: /Users/samxx/.ct/index/package.sh: No such file or directory
rc=1
$ test -x ~/dsh-ws/ct-pkg-index/tools/package.sh; echo "exec-bit rc=$?"
exec-bit rc=1
```

维护者只能离开 `ct`：`cd <index 仓> && bash tools/package.sh check`；脚本不是可执行文件，A 设想的 `$CT_HOME/index/package.sh` 连路径都不存在（实际是 `tools/package.sh`）。

### E1-3 不利 B：两套工具、两个答案（碎片化）
```console
$ ct pkg check /tmp/counter-ws/alpha; echo "rc=$?"
ok: 4 criteria
rc=0
$ CT_PKG_ROOT=/tmp/counter-ws bash ~/dsh-ws/ct-pkg-index/tools/check-layout.sh; echo "rc=$?"
FAIL  alpha/Foo/bar.ct: namespace Baz::Qux expects directory Baz/Qux
1 of 1 namespaced units do not match their directory
rc=1
```

同一条命令族下，`ct` 说 OK、索引门禁说 FAIL。B 让用户记住两条命令，这是 A 的「统一入口」最实的收益。

### E1-4 利 B：透传在消费者机上只能报错
```console
$ cd ~/dsh-ws/ct-pkg-index && bash tools/package.sh check hal; echo "rc=$?"
== preflight ==
  ..    hal
ERROR: /Users/samxx/vscspace/ct-pkg/hal is not a git repository; clone or create it first
ERROR: 1 package(s) failed the preflight
rc=1
```

`package.sh` 假定 `STAGING=~/vscspace/ct-pkg` 的**维护机布局**（`tools/package.sh` 第 34-37 行），不是「装了 `ct` 的机器」。A 把维护者脚本放进面向所有用户的二进制入口，多数调用只会得到上表的失败。

### E1-5 利 B：A 会改掉一个现成行为

```console
$ cd /tmp/counter-ws/alpha && ct pkg; echo "rc=$?"
ctc: no './ct.lock'; run `ct get` first
rc=1                      # 与 `ct install` 逐字相同；`pkg` 就是 install 别名
```

## 3. E2 `file:line`

| 锚点 | 内容 | 对 B |
| --- | --- | --- |
| `selfhost/ct-ast/main.ct:121-122` | `pkg` 直接路由到 `ct_pkg_install`；无独立头文件/帮助/子命令表 | 利 B：A 要在此开二义分支（`pkg` = install 还是脚本） |
| `selfhost/ct-ast/tool/pkg/Pkg.h.ct:1744-1748` | `ct pkg check` 只读、进程内、打印「read-only: PK-1/2/5/8」 | 利 B：A 的透传会抢走这个前缀 |
| `selfhost/ct-ast/tool/pkg/Pkg.h.ct:133` | 「Nothing is built in — 裸名只经用户指名的索引解析」 | 利 B：A 的 `init` 引入隐式默认索引 |
| `selfhost/ct-ast/tool/pkg/Pkg.h.ct:1130-1150` | 无索引时硬错 + 四类指引（已足够可发现） | 利 B：A 的「首次提示」已有等价物 |
| `install.sh:168-172` | `std` 是包，安装器不拉索引、不写 `~/.ct/index` | 利 B：A 让安装/init 边界重新混淆 |
| `AGENTS.md:543-547` | 零网络例外只覆盖包管理；编译器核零子进程 | 利 B：透传是第五类子进程例外，需改规约 |
| `ct-pkg-index` 仓 `tools/package.sh` 第 13-25 行 | `check/publish/release` 单一生命周期入口 | **不利于 B**：统一入口的诉求真实且合理 |
| `ct-pkg-index` 仓 `tools/package.sh` 第 34-37 行 | `STAGING=~/vscspace/ct-pkg`，工作区级布局 | 利 B：脚本无法在消费者机运行 |
| `ct-pkg-index` 仓 `README.md` 第 167-181 行 | 「package.sh 是发布唯一入口」；`publish` 需 `GITHUB_TOKEN` | **不利于 B**：`ct` 侧确实没有发布入口 |
| `README.md:450` | `ct` 只列 `get/update/install/verify/migrate`，无 publish | **不利于 B**：发现性缺口由 B 承担 |
| `docs/reviews/2026-11-17-pkg-index-audit.md:67` | 「本仓不生成索引；`ct` 只读索引，不写索引」 | 利 B：发布写者已归外部仓 |

## 4. E3 可证伪预测

B 成立时下列四条应持续为真；每条给可执行反例（出现即 B 不成立）。

| # | 预测 | 判据命令 | 反例（B 不成立） |
| --- | --- | --- | --- |
| P1 | `ct pkg` 兼容：仍是 install 别名，pkg 路由无 exec | `grep -nE 'exec|system\(|popen' selfhost/ct-ast/main.ct`（pkg 段 121-122 无命中）；`ct pkg` 在包目录输出 `no './ct.lock'` | `ct pkg` 的 stderr 变成 `package.sh` usage，或 121-122 出现分发函数 |
| P2 | init 只读：`$CT_HOME` 只有索引目录变化 | `find "$CT_HOME" -newer /tmp/stamp` 只列 `index`；`find "$CT_HOME/index" -perm -u+x` 为空 | 出现 `$CT_HOME/pkg/<pub>` 新目录、包仓工作树、或索引内脚本被置可执行 |
| P3 | 发布不丢：CI 仍是唯一写者 | `grep -n 'contents: write' ct-pkg-index/.github/workflows/index.yml`（:16-17）；README 仍有 publish 行（:181） | workflow 被删、publish 行消失、或只有 `ct pkg` 一条发布路径 |
| P4 | 无隐式索引：无 `--index`/`CT_INDEX` 时裸名仍硬错 | `ct get ct/std`（隔离 `CT_HOME`）→ `no index resolver`，rc=1 | 该命令 rc=0 并联网解析 → 默认索引被引入 |

## 5. E4 代价（与 A 对比）

| 项 | A（init + 透传） | B |
| --- | --- | --- |
| 源码改动 | `main.ct:121-122` 加分发 + `Pkg.h.ct` 加 init/exec 两个函数；该入口已因函数预算被塞入审计逻辑（`Pkg.h.ct:1741-1743`） | 0 行源码；只改文档/提案 |
| 新增状态 | `$CT_HOME/index` clone（仓外状态，revert 代码不回收） | 无 |
| 权限 | 执行 `publish` 需 `GITHUB_TOKEN` 进 `ct` 进程环境（`tools/package.sh` 第 96-99、127-134 行） | token 只在维护 shell / CI |
| 审计 | 索引 main 夜间可变（`index.yml:1-8`）、无签名/无 pin，脚本内容随每次调用变化 | 脚本变更走 index 仓 git 审阅；`ct` 行为可复现 |
| 回退 | `git revert` 只回代码，用户机上的 clone 需手工删；已发布的 `ct` 无法感知脚本漂移 | 无可回退状态；换版本只换二进制 |
| 失败模式 | 未 init / 脚本缺失 / 无 exec 位 / 无 STAGING / 无 token：5 类错误都从 `ct` 出 | 1 类：没有发布入口（由文档与 CI 承担） |
| 步数 | 首次 init + 每次 1 步 | 维护者 2 步（cd + bash），消费者 0 步 |

A 的净收益只在「已在维护机、已 init、只跑 check」这一窄格；代价扩散到所有 `ct pkg` 用户。

## 6. E5 steelman A 与逐条反驳

A 最强四条：

1. **统一入口**：`package.sh` 自述是生命周期唯一入口（`tools/package.sh` 第 3-5、13-25 行），`ct pkg` 接管后用户只需记一个命令。
2. **合并检查**：E1-3 实测 `ct` 只判 4 项、索引门禁能判布局，透传能得到全量 preflight。
3. **发现性**：`README.md:450` 与 `ct -h` 都没有发布入口，用户撞到 `unexpected argument 'publish'`（E1-2）。
4. **同仓同步**：脚本与索引同仓演进，入口放 `ct` 可减少版本错配。

反驳：

1. 「统一」的价值以能运行为前提：无 STAGING 时 `package.sh check` 直接 rc=1（E1-4），A 只是把 5 类失败前移到 `ct` 里；统一入口可以放在独立 `ct-pkg` 工具或文档，不必进编译器二进制。
2. 全量 preflight 需要**包仓工作树**，而消费者只有 store 里的发布产物（`~/.ct/pkg`）；ct 侧无法凑齐，A 只能把维护者工作区假设带进用户机。
3. 发现性是文档缺陷，用 README/`ct -h` 一行说明即可修；而 A 要改掉 `ct pkg` 的 install 别名语义（E1-5），用兼容性换一次文档省略，净负。
4. 同仓同步不成立：脚本在**可变 main**（`index.yml:1-8` 夜间刷新），`ct` 是**已发布二进制**；客户端无 pin/无签名，二者无法绑定，A 反而制造「同一 `ct pkg` 在不同日期行为不同」。
5. A 与既有判决冲突：`battle/index-install-1/verdict.md:4,27` 已判「`ct pkg` 不执行带 credentials 的发布脚本」，A 是同一争点的重开，未给出新证据。

## 7. 结论与失效条件

**B 胜出**：`ct pkg` 保持 install 别名 + `check` 只读；init 若做，只拉索引/校验（pin + 原子 + 签名）；发布留在 index CI / 独立 `ct-pkg` 工具。B 用 0 行源码换来兼容、可复现与最小权限，代价是维护者多一步 cd。

**B 不成立（复核触发）**：

- `package.sh` 拆成无 token、无 STAGING 的只读 `check` 与独立的写 `publish`；此时 A 的窄版 `ct pkg check` 透传值得重开；
- 索引仓给出固定 pin + 签名 + 六字段，且 `ct` 有可验证的默认索引来源；
- 用户明确要求「不做包维护者与消费者的区分」，并接受 `ct pkg` 语义变更与 token 进 `ct` 环境；
- E1-4 被推翻（无 STAGING 时 `package.sh check` rc=0），则 B 的维护机论据失效。
