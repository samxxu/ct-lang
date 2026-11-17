# battle/index-pkg-1 · 主张席（REQ）claim A：`ct pkg` = index init + `package.sh` 透传

| 项 | 值 |
| --- | --- |
| 主张 | A（init + 透传），完整形态见 §1 |
| 基线 | `a979ce0d`（v0.65.1）；工作树仅 `battle/` 未跟踪 |
| 外部只读件 | `ct-pkg/index` @ `37fa8a3`（工作树有未提交修改，只读，未写入） |
| 判定 | **A 原样不成立**：`ct pkg check` 已是 package.sh 依赖的原生只读入口（E1-3）；仅 init 半部可留 |
## 1. A 的完整形态（init / 透传 / 诊断 / CT_HOME）
1. **init**：`ct pkg init` 在 `$CT_HOME/index` 缺失时用系统 `git` 取 `ct-pkg/index`（默认 `main`，`--pin <sha>` 可钉）到 `$CT_HOME/index.tmp.<pid>`，校验 `tools/package.sh` 后原子 rename；已存在幂等返回 0；失败清理临时目录。
2. **透传**：`ct pkg <args>` 若 `$CT_HOME/index/tools/package.sh` 缺失 → 提示 `ct pkg init`；存在 → `bash <script> <args...>`（脚本 mode 644、shebang bash，见 E1-5），继承环境，退出码原样返回。
3. **失败诊断**：未 init / 无 git / 网络失败 / 脚本缺失 / `CT_HOME` 相对或不可写，各一条 stderr + 非 0；不得悄悄退回 `ct install`。
4. **CT_HOME**：沿用 `Pkg.h.ct:1954-1975`（缺省 `$HOME/.ct`）；index 放 `<root>/index`，store 仍 `<root>/pkg`；拒绝相对/空 `CT_HOME`，不落到 cwd。
5. **install.sh**：不拉 index（**现状已如此**，E1-7）；最多加一行 `ct pkg init` 提示。
## 2. E1 命令与原始输出
环境：`~/.local/bin/ct` = `ct v0.65.1`；`ct-pkg/index` 只读（`git log -1` = `37fa8a3`）。
**E1-1 `ct pkg` 当前是 install 别名（不利 A）**

```console
$ cd /tmp && ~/.local/bin/ct pkg; echo "[exit $?]"
ctc: cannot open './ct.pkg'
[exit 1]
$ ~/.local/bin/ct pkg check /tmp; echo "[exit $?]"
ctc: cannot read '/tmp/ct.pkg'
[exit 1]
```

读 `./ct.pkg` 即 `install` 语义，不是脚本入口；`main.ct:121-122` 把 `pkg` 派给 `ct_pkg_install`。A 会让无参 `ct pkg` 从「离线安装当前目录」变成「打印 package.sh 用法」，属行为破坏。
**E1-2 `ct pkg check` 是原生只读审计（既可用，也占用名字）**

```console
$ ~/.local/bin/ct pkg check /tmp/battle-index-pkg-1/staging/hal; echo "[exit $?]"
ok: 4 criteria
[exit 0]
```

实现见 `Pkg.h.ct:1741-1765`（PK-1/2/5/8），与 `package.sh:199-200` 的 preflight 调用点直接对接。
**E1-3 A 的透传会让 `package.sh` 自身 preflight 失败（决定性不利）**

用 /tmp 下 `ct-a` 忠实模拟 A 的映射（`shift` 掉 `pkg` 后 exec 真 `package.sh`），再跑真 `package.sh`：

```console
$ cat /tmp/battle-index-pkg-1/ct-a
#!/bin/bash
shift
exec bash /Users/samxx/dsh-ws/ct-pkg-index/tools/package.sh "$@"
$ cd /Users/samxx/dsh-ws/ct-pkg-index && STAGING=/tmp/battle-index-pkg-1/staging \
    CT_BIN=/tmp/battle-index-pkg-1/ct-a bash tools/package.sh check hal; echo "[exit $?]"
== preflight ==
--- hal ---
[stderr]
        == preflight ==
        ERROR: '/tmp/battle-index-pkg-1/staging/hal' is not a row in /Users/samxx/dsh-ws/ct-pkg-index/tools/repos.txt
ERROR: ct pkg check failed for hal
ERROR: 1 package(s) failed the preflight
[exit 1]
```

因果链：`package.sh:199` 调 `ct pkg check "$dir"` → A 转成 `package.sh check "$dir"` → `manifest_row` 只认包名。修法只有两条：A 里把 `check` 特判回原生（「透明透传」不再成立），或改 `package.sh` 调用名（跨仓协调，须计入成本）。
**E1-4 `package.sh` 需要 credentials（不利 A）**

```console
$ env -u GITHUB_TOKEN -u GH_TOKEN bash tools/package.sh publish hal; echo "[exit $?]"
== preflight ==
[exit 1]
[stderr]
ERROR: set GITHUB_TOKEN (or GH_TOKEN) first: export GITHUB_TOKEN=github_pat_xxx
```

`package.sh:18/107-111/127-131`：`publish` 还要 RESTie，token 经 `credential.helper` 进 git。挂到 `ct pkg` 默认入口，等于让编译器命令携带写仓库凭据执行 index `main` 上的脚本。
**E1-5 `package.sh` 无执行位、shebang 是 bash（不利 A）**

```console
$ stat -f '%Sp %N' tools/package.sh
-rw-r--r-- tools/package.sh
$ ./tools/package.sh check hal; echo "[exit $?]"
env: ./tools/package.sh: Permission denied
[exit 126]
```

「直接执行 `$CT_HOME/index/package.sh`」必须由 ct 显式 `bash` 包裹；execve 会 EACCES。
**E1-6 index 是五字段、无签名（不利 A）**

```console
$ awk '{print NF}' index | sort | uniq -c
  12 5
$ head -1 index
hal 0.1.0 https://github.com/ct-pkg/hal v0.1.0 sha256:d38db6f2f733a13a7067e465267d07eb4f8f1ecc2e486a772160d1a18a92fbde
$ grep -c 'signature\|gpg\|sig' index
0
```

`Pkg.h.ct:2214-2225`：六字段行才带 publisher，旧五字段行仍合法；当前 12 行全五字段、无 publisher、无签名。`sha256:` 是包树摘要，从同一条未签名 index 取，不能证明来源真实；A 把脚本执行权交给它是 TOFU。
**E1-7 `install.sh` 从未拉 index（A 第 4 条是空改动）**

```console
$ grep -n 'index' install.sh; echo "[exit $?]"
[exit 1]
$ sed -n '172p;186,187p' install.sh
say "the standard library is a package; in your project run: ct get ct/std && ct build main.ct -o main"
Standard library (a ct-pkg package, per project):
  ct get ct/std
```

没有可删代码，成本为 0，但触发理由（替代 install.sh 拉索引）前提不实。另一面：装完立即让用户 `ct get ct/std` 却没有索引，这个 UX 缺口真实（利 init 半部）。
## 3. E2 `file:line`
**利 A**

| 位置 | 事实 | 对 A 的意义 |
| --- | --- | --- |
| `selfhost/ct-ast/tool/pkg/Pkg.h.ct:1129-1147` | 无索引时 `ct get ct/std` 无 resolver，错误要求手写 `--index`/`CT_INDEX` | `ct pkg init` 把「手写索引」变成一次默认动作，缺口真实 |
| `selfhost/ct-ast/tool/pkg/Pkg.h.ct:2155-2170` | 索引只从 `--index`/`CT_INDEX` 读本地纯文本，无默认路径 | `$CT_HOME/index` 给出唯一默认，可审计 |
| `install.sh:172,186-187` | 安装后下一步就是 `ct get ct/std`，安装器却不取索引 | 首次提示/init 有明确落点 |

**不利 A**

| 位置 | 事实 | 对 A 的意义 |
| --- | --- | --- |
| `selfhost/ct-ast/main.ct:121-122` | `pkg` 是 `ct_pkg_install` 别名 | 复用一个已被占用的活命令，破坏无参 install（E1-1） |
| `Pkg.h.ct:1741-1765` + `ct-pkg-index/tools/package.sh:199-200` | `ct pkg check <dir>` 是原生只读审计，且是 package.sh 的 preflight 依赖 | 透传与消费者直接冲突（E1-3） |
| `ct-pkg-index/index`（12 行 × 5 字段）/ `package.sh:107-131` | 无 publisher、无签名 + 需 token/RESTie | 任意脚本执行与写凭据绑进日常命令，攻击面扩大 |
| `Pkg.h.ct:98` | 本单元恰在 256 函数上限 | init/exec 不能就地加方法，须新拆单元并改 main.ct 装配 |
## 4. E3 可证伪预测（A 成立时应观察到）
- **P1 init 一次可用**：`CT_HOME=/tmp/i1 ct pkg init` 退出 0，`/tmp/i1/index/tools/package.sh` 存在；再跑一次退出 0 且 pin/commit 不变；无 git 时退出非 0 且 `/tmp/i1/index` 不存在（原子性）。
- **P2 透传可审计且不污染**：`CT_HOME=/tmp/i1 ct pkg --help` 打印 package.sh usage（非 install usage）；无 token 的 `ct pkg release hal v0.1.0` 退出非 0、stderr 含 token 诊断、`git -C /tmp/i1/index status --porcelain` 为空；stderr 预置 `index: <script> argv=[...]`（凭据打码）；`ct pkg check <fixture>` 仍退出 0。
- **P3 失败不污染**：未 init 时 `CT_HOME=/tmp/i2 ct pkg check .` → stderr 恰为「未初始化，运行 ct pkg init」，退出非 0，`/tmp/i2/index` 不存在；任何失败不得退回 install 语义。

观测：P2 的 `check` 子预测已被 E1-3 证伪；P1/P3 因 init 未实现不可观测，是 A 收窄后可复验的判据。
## 5. E4 代价
| 面 | 改动 | 量级 | 风险/失败模式 |
| --- | --- | --- | --- |
| `main.ct:121-124` | `pkg` 分支改新入口 + import/装配 | +4~8 行 | 与 `install`/`get` 分派顺序冲突 |
| `Pkg.h.ct` | 已满 256 函数（:98）不能加方法；需新单元（路径、原子 clone、pin、定位脚本、exec、诊断） | 约 120~180 行 | 与 Phase 8「包管理只在 tool::pkg」边界漂移 |
| `install.sh` | 0 行（前提不实）；可选 2 行提示 | 0~2 行 | 无 |
| `ct-pkg-index/package.sh` | 保留透传需改 `:199` 调用名 + 文档 + exec 位（644→755） | 1~3 行 + mode | 跨仓协调；改后不再「透明」 |
| `AGENTS.md:543-544` | 零网络例外扩到 `ct pkg init`，属行为变更，须用户确认（`:531-532`、`:606`） | 2~3 行 + 签字 | 未确认即违 AGENTS |
| 测试 | 3 负例（未 init、clone 失败、脚本缺失）+ G5 红证 | 约 40~80 行 | 无红证则任务未完成 |

失败模式：F1 `check` 递归/语义冲突（已实测）；F2 无 git/无网络；F3 未签名可变 `main` 上执行脚本并携带 token；F4 缺 token/RESTie/staging；F5 脚本无执行位、依赖 bash；F6 `CT_HOME` 相对/未设/不可写；F7 无参 `ct pkg` 兼容破坏；F8 pin 过期或仓库改名。合计约 150~220 行 + 一次跨仓协调 + 一次 AGENTS 例外签字。
## 6. E5 steelman B（不复用 ct pkg，发布留 CI）与逐条反驳
- **B1 语义**：`ct pkg` 应保持包管理/只读语义。最强形式：`ct pkg check` 已是真实只读接口且被 `package.sh:199` 消费，改名/透传都会破坏契约。**反驳**：白名单化后仍含 `check`（递归）与 `publish`（凭据），与 B 第 3 条同构。**判定：B 胜。**
- **B2 凭据**：`package.sh` 需 token/RESTie/staging 与写权限。最强形式：E1-4 就是最小权限证据，不应让编译器命令默认携带写凭据。**反驳**：只透传 `check` 可避开凭据，但 `check` 已证明冲突，A 的相对收益归零。**判定：B 胜。**
- **B3 最小 init**：若需 init，只拉/校验索引，不执行 `package.sh`。最强形式：满足 A 的 UX 目标且不引入脚本执行与凭据。**反驳**：这正是 A 的 init 半部，「透传」是额外负担而非必要条件。**判定：A 的 init 被 B 吸收。**
- **B4 审计/兼容**：参数透传带来权限、兼容、审计问题。最强形式：E1-1/E1-3/E1-5 是实测。**反驳**：加 argv 日志与 token 打码可补审计，但无参 `ct pkg` 语义必变，兼容破坏无法消除。**判定：B 胜。**
- **B5 索引质量**：index 五字段、无 publisher、无签名、可变 `main`。最强形式：E1-6；A 让这份数据决定「执行哪个脚本」。**反驳**：init 可 pin sha 降低漂移，但 pin 不替代真实性；CI 的分支保护/审计日志严格更强。**判定：B 胜。**
## 7. 结论
**A 原样不成立**（均已实测）：① 复用 `pkg` 破坏无参 install（E1-1）；② 透传与 `package.sh:199` 的原生 `ct pkg check` 消费点冲突，preflight 失败（E1-3）；③ script 需 token/RESTie、无执行位、依赖 bash（E1-4/E1-5）；④ index 五字段未签名且可变（E1-6）；⑤ install.sh 本就不拉 index，第 4 条无改动（E1-7）。

**A 只有在 C1–C5 同时成立时才可作为胜出方案**：C1 `check` 保留原生、永不透传；C2 透传仅 `ct pkg run -- <args>` 显式开启；C3 init 用系统 git、pin sha、原子失败、无写凭据；C4 不改 `install.sh` 行为；C5 AGENTS 零网络例外扩写经用户签字。满足后 A 的剩余部分 = B 第 3 条（init-only），故**争点上的胜出方是 B；A 的 init 要求被采纳，透传要求被否决**。
