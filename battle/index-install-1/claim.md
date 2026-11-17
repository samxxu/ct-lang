# 主张席（REQ）：install.sh 默认拉 index + `ct pkg` 映射发布脚本（A）

> 立场：A 的**意图**（安装即带索引）成立；但**原文五条**里的“匿名 main 默认拉”和“发布脚本进 ct”不成立。本席主动给出 A 的不利证据、A′ 成立条件与 B 胜出条件。证据环境：`Darwin arm64`，HEAD `792d5bc1`（v0.65.1），`ct v0.65.1`；外部 `ct-pkg/index` 不在本机，按 `main` 快照 `f7fb1d85`（2026-11-18 `git ls-remote`）只读抓取到 `/tmp`（`https://raw.githubusercontent.com/ct-pkg/index/f7fb1d85/…`；`index` sha256=`7ed5b97d…`），未改仓库。

## A 的精确路径（原文）

| # | 承诺 | 具体行为 |
| --- | --- | --- |
| A1 | 安装默认拉索引 | `install.sh` 第 4 步后 `git clone --depth 1 https://github.com/ct-pkg/index "$HOME/.ct/index"`；git 缺失/网络失败只告警，不影响 `ct` 安装 |
| A2 | `ct get` 默认使用 | 未显式 `--index`/`CT_INDEX` 时取 `$HOME/.ct/index/index`；显式值优先 |
| A3 | 索引更新 | `ct pkg index update` 对 `~/.ct/index` 做 `git pull --ff-only`；`--pin <sha>` 时 `checkout <sha>` 并记录 |
| A4 | 发布映射 | `ct pkg publish <name> <tag>` 调 index 仓 `tools/release-package.sh`，完成 tag 推送、索引重建、提交推送 |
| A5 | 失败降级 | 索引缺失时 `ct get` 落回现状报错（E1-1）；`ct build/install/verify` 不受影响。A1/A2 的默认值必须 pin（`~/.ct/index` 的 commit 可记录/校验），否则默认便利变成默认可变信任根（E1-4） |

## E1 命令与原始输出（只读重跑，产物 `/tmp/idx-e1`）

**E1-1（利 A：现状没有默认索引，限定名直接失败）**
```console
$ env -u CT_INDEX HOME=/tmp/idx-e1/home CT_HOME=/tmp/idx-e1/home/.ct ct get acme/hello; echo "rc=$?"
ctc: no index resolver for 'acme/hello'
  'acme/hello' is a publisher-qualified package name; without an index
  ...
rc=1
```

**E1-2（利 A：索引在，解析即通）**
```console
$ HOME=/tmp/idx-e1/home2 CT_HOME=/tmp/idx-e1/home2/.ct CT_INDEX=/tmp/idx-e1/index1 ct get acme/hello | grep -E 'resolved|source|digest|package'
resolved   acme/hello 0.1.0
  source   git file:///tmp/idx-e1/pkg
  digest   sha256:9a753567cfa8cf0c035f45af83bbf646967803f98d8c713839ab274d5ce286e8
1 package(s): 1 installed, 0 reused
```

**E1-3（不利 A：官方索引是五字段，默认用它仍解析不了文档主推的限定名）**
```console
$ HOME=/tmp/idx-e1/home-o CT_HOME=/tmp/idx-e1/home-o/.ct CT_INDEX=/tmp/idx-index ct get std/std; echo "rc=$?"   # /tmp/idx-index = 外部仓 main 的 12 行五字段 index
ctc: git clone of 'https://std/std' failed
rc=1
```
外部 `index:1-12` 无 publisher 列；消费端六字段（`Pkg.h.ct:2216`），限定名匹配要求 publisher。A1 把这份文件设为默认后，`ct get ct/std`/`std/std` 不是“能用”，而是从明确报错退化成错误 URL clone。

**E1-4（不利 A：索引行是自证的信任根，main 一变内容就换）**
```console
$ HOME=/tmp/idx-e1/home4 CT_HOME=/tmp/idx-e1/home4/.ct CT_INDEX=/tmp/idx-e1/index-evil ct get acme/hello | grep -E 'resolved|source|digest'
resolved   acme/hello 0.1.0
  source   git file:///tmp/idx-e1/pkg-evil
  digest   sha256:6c09a129b180eb8c471928ee26bab6d748bc9661aaea08a18a841adc13faca7b
$ sed -n 1p /tmp/idx-e1/home4/.ct/pkg/acme/hello/0.1.0/hello.h.ct
pub fn hi() -> int { return 666; }
```
同一个 `acme/hello@0.1.0`，仅索引行不同（URL/tag/digest 一起变）即装成另一份内容；digest 由同一行给出，没有独立签名。把该行放到 `~/.ct/index/index` 并由 main 自动刷新，正是 A1 的默认路径。

**E1-5（不利 A：默认 clone 在离线/重复安装下失败，而今天的本地安装完全离线可用）**
```console
$ https_proxy=http://127.0.0.1:9 git clone --depth 1 https://github.com/ct-pkg/index /tmp/idx-e1/offline-index; echo "rc=$?"
fatal: unable to access 'https://github.com/ct-pkg/index/': Failed to connect to 127.0.0.1 port 9 after 0 ms: Couldn't connect to server
rc=128
$ git clone file:///tmp/idx-e1/pkg clone-target     # 第二次执行（等价于重复安装）
fatal: destination path 'clone-target' already exists and is not an empty directory.
$ env https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 CT_SOURCE_DIR=/Users/samxx/dsh-ws/ct-lang sh /Users/samxx/dsh-ws/ct-lang/install.sh --prefix /tmp/idx-e1/prefix >/tmp/idx-e1/install-offline.log 2>&1; echo "install_rc=$?"
install_rc=0
$ tail -1 /tmp/idx-e1/install-offline.log
==> installed /tmp/idx-e1/prefix/ct (ct v0.65.1) and /tmp/idx-e1/prefix/ctc
```
A5 只说“降级”，未定义：git 缺失、已有非空 `~/.ct/index`、clone 中断留下半目录时如何不污染；A1 必须给出原子落盘（临时目录 + rename）与可重入，否则 E1-5 就是默认失败。

**E1-6（不利 A：发布脚本要求写 token；`ct pkg` 今天是 install 别名）**
```console
$ STAGING=/tmp/idx-e1/staging sh /tmp/idx-tools_release-package.sh hal v0.1.0; echo "rc=$?"
ERROR: set GITHUB_TOKEN (or GH_TOKEN) to a token that may push to ct-pkg
rc=1
$ ct pkg; echo "rc=$?"   # main.ct:121-122 把 pkg 整体交给 ct_pkg_install
ctc: cannot open './ct.pkg'
rc=1
```
`release-package.sh:24-26,49-66` 要求 `repo`+`workflow` 权限的 PAT，并用内联 credential helper 推 package main/tag 与 index main；A4 把它塞进 `ct pkg`，等于把写权限带进编译器进程。

**E1-7（降级面：索引不可读只影响 get；离线 verify 仍绿）**
```console
$ HOME=/tmp/idx-e1/home-f CT_HOME=/tmp/idx-e1/home-f/.ct CT_INDEX=/tmp/idx-e1/nope ct get acme/hello; echo "rc=$?"
ctc: cannot read the package index '/tmp/idx-e1/nope'
rc=1
$ env https_proxy=http://127.0.0.1:9 HOME=/tmp/idx-e1/home-f CT_HOME=/tmp/idx-e1/home-f/.ct ct verify; echo "rc=$?"
verified 1 package(s)
rc=0
```
不可复现项：`CT_INDEX=/tmp/idx-index ct get std` 的裸名成功路径 90s 超时（外部 git 拉取），本席不据此下结论。

## E2 锚点（HEAD `792d5bc1`）

| 判定 | `file:line` | 内容/含义 |
| --- | --- | --- |
| 利 A | `install.sh:18,72-74` | 默认 `ref=main` 并从 GitHub 下载源码：默认安装本来就要网络，B 的“离线安装”只在 `CT_SOURCE_DIR`（`install.sh:59-61`）成立 |
| 利 A | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:707-708` | 裸名默认走 `CT_REGISTRY`（`https://github.com/ct-pkg`）：网络名称解析已是既成事实，默认 index 不是第一个信任根 |
| 利 A | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:1129-1152` | 无索引时限定名硬错；A2 是让“装完即用”成立的唯一入口 |
| 不利 A | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:132-135` | 设计注释：`Nothing is built in -- a package name only resolves through an index the user named`：默认索引与现行契约相反 |
| 不利 A | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:31-32,746-760` | 只有 `get` 可跑 git，且只有**一个**子进程调用点；A3/A4 新增网络与发布子进程 |
| 不利 A | `AGENTS.md:528-532` | `install.sh` 只用 `cc/tar/curl/wget`，**不需要 git**；新增下载来源/安装位置属行为变更，需用户确认——A1 两条都撞 |
| 不利 A | `selfhost/ct-ast/main.ct:109-122` | `ct pkg` 是 `ct install` 别名；A3/A4 改其语义，`ct pkg index` 从“装 index 包”变成子命令 |
| 不利 A | `docs/package-guide.md:140-142,224-225` | `get` 是唯一 git 调用点，`update/verify/install` 零网络零子进程；A3 的 `index update` 是新的联网更新路径 |
| 不利 A | 外部 `index:1-12` vs `docs/package-guide.md:112-120` | 生产端五字段、消费端六字段：A1 默认指向的数据无法解析 publisher 限定名（E1-3） |

## E3 可证伪预测（A′ 实现后一次性验证）

| # | 场景 | A′ 成立时预测 | 反例（出现即 A 不成立） |
| --- | --- | --- | --- |
| 1 | 断网安装（`https_proxy=:9`，`CT_SOURCE_DIR`） | `install.sh` rc=0，`ct -v` 正常；索引拉取 warn 后跳过，**不留** `~/.ct/index` 半目录 | rc≠0、或留下 `~/.ct/index` 空/半仓 |
| 2 | 代理下安装 | clone 失败 ≤ 超时上限后继续；不重试无限、不阻塞 `ct` 安装 | 挂死/无超时/失败仍宣称“索引已就绪” |
| 3 | 重复安装 | 已有索引时走 `git fetch + checkout <pin>`（或 skip），rc=0；`index` 内容不变 | 第二次 rc≠0（E1-5 现状）或删索引重拉 |
| 4 | 索引更新 pin | `ct pkg index update --pin <sha>` 后 `git -C ~/.ct/index rev-parse HEAD` == `<sha>`；两次同 pin 的 `sha256 index` 相等 | 仍跟踪 main、无法回到旧 commit |
| 5 | 未 pin 的更新 | 若允许，必须打印 old/new commit 与行级 diff；不静默改解析结果 | 无提示换行（E1-4 的静默换内容） |
| 6 | 发布审计 | `ct pkg publish` 无 token → rc≠0（E1-6）；成功后打印 name/tag、package commit、index commit；`git config --get credential.helper` 为空 | token 写进 `.git/config` 或 argv/日志；无 index commit 可追溯 |
| 7 | 发布幂等 | 同 tag 重跑 rc=0，index 无新 commit（外部脚本 `release-package.sh:119-121` 同形） | 每次发布都改 index/强制推 |
| 8 | 索引失败不伤构建 | `CT_INDEX` 缺失/损坏时 `ct get` rc≠0 且 `ct.lock` 字节不变；`ct verify` rc=0（E1-7） | `ct.lock` 被改写或 store 被删 |

## E4 代价（文件/行数/失败模式）

| 面 | 量 | 失败模式 |
| --- | --- | --- |
| `install.sh` | +12–18 行（git 检测、clone/fetch、原子 rename、降级）；新增 **git 依赖**与 `~/.ct/index` 安装位置 | 无 git、无网、超时、已有非空目录、并发安装、`CT_HOME` 自定义时索引不在 `$CT_HOME`（store 根见 `Pkg.h.ct:1954-1970`） |
| `main.ct` / `Pkg.h.ct` | +6–10 行分派；+120–200 行（index update/pin + publish 包装/校验） | 与现有 `ct pkg <spec>` 语义冲突；新增子进程/token 路径，违反 `Pkg.h.ct:31-32,746` 单点边界 |
| 索引仓 CI/脚本 | 外部仓 755 行：`release-package.sh` 147、`refresh-index.sh` 275、`publish-package.sh` 218、`gen-index.sh` 66、`index.yml` 37、`index` 12 | 五字段/最高 tag、无签名（审计 G7/G9）、`$STAGING=~/vscspace/ct-pkg` 布局假设（`release-package.sh:43-47`）、夜间 bot 推送 |
| 测试/门禁 | +80–120 行（pkg 夹具 + 断网矩阵） | 网络用例不稳定；`g7` 密钥扫描对 token 夹具敏感 |
| 回退 | 3 个提交（test 红、feat、docs）；revert feat 即回现状 | install.sh 行为变更未走用户确认（`AGENTS.md:528-532`）即 G8 越界 |

## E5 steelman B 与逐条回应

B 原文（`question.md:21-27`）：安装不默认 clone；`ct pkg` 只读、发布留 CI；更新必须 pin/签名、不能匿名 main；发布脚本带 credentials 不进二进制；离线/可复现优先，失败不污染 `~/.ct`。

1. **B1/B5 最强：默认值是“失败面”而非“功能”。** 承认 `install.sh:18,72-74` 本来联网，但源码归档是**必需**输入，索引是**可选**物；把可选项做成默认，恰好把唯一离线入口 `CT_SOURCE_DIR`（`install.sh:59-61`）和重复安装（E1-5）变成失败场景，且违反 `AGENTS.md:528-532` 的“不需要 git / 行为变更需确认”。A′ 必须改成显式 `--with-index` 或默认只读本地、绝不因索引失败而失败。
2. **B2“发布留 CI”不可反驳。** 外部 `index.yml:11-12,27-37` 用 `permissions: contents: write` 的作业提交索引，日志与 commit 就是审计链；`release-package.sh` 需要 repo/workflow PAT（E1-6），把这条链路搬进 `ct` 只会让每个开发者机器持有写权限，并新增子进程。A 的“一条命令”用 `gh workflow run` 即可，不必进编译器。
3. **B3“pin/签名”是实现前置，不是反对 A 的 UX。** 但原文 A1 只写 `git clone`，且外部仓**没有 tag**（`git ls-remote --tags` 空），只能按 commit pin；A′ 应默认记录并校验 commit，`--pin` 可回退。做不到就落入 E1-4 的默认可变信任根。
4. **B4 credentials 是 A 的硬伤。** `release-package.sh:49-66` 把 PAT 内联进 git credential helper；无论 `ct pkg` 是 exec 脚本还是重写，token 都会进入 `ct` 进程环境/命令行。A4 应降级为“打印/触发 CI”，而不是“映射执行”。
5. **A 的真正增量只剩 J-4。** 在索引生产端六字段、包身份补齐（`std 0.3.2`）后，默认索引能把 E1-1 的报错变成可用；但今天官方索引五字段（E1-3），这个增量尚未兑现。B 的“手动一步 `CT_INDEX`”成本是一行环境变量，收益可复现；在数据未就绪前，A 的默认只是把明确错误换成错误 URL。

## 结论

| 判据 | 判定 | 依据 |
| --- | --- | --- |
| J-1 离线/可复现 | **A 不成立** | E1-5：默认 clone 离线/重复失败；降级未定义；B 的 `CT_SOURCE_DIR` 现状 rc=0 |
| J-2 供应链 | **A 不成立** | E1-4：索引行自证，main 变更即换内容；无签名/无 pin（审计 G9） |
| J-3 架构边界 | **A 不成立（仅 A4）** | `Pkg.h.ct:31-32,746` 单子进程；A4 新增写权限路径；A1/A2 的本地文件读取本身不破坏零网络 |
| J-4 UX | **A 窄胜（条件）** | 索引六字段+包身份齐备后“装完即用”成立；今天五字段使限定名失败（E1-3），优势未兑现 |
| J-5 发布工作流 | **B 胜** | CI + commit 审计；本地 token 脚本不可审计且扩大权限面 |
| J-6 成本 | **B 胜** | A 约 +220–330 行 CT 侧 + 755 行外部仓依赖；B 为 0 |

**A 作为原文整体不成立**（A1 未 pin、A4 越界、A5 降级不可验证）。**A′ 可胜出的条件**（全部满足）：(a) 索引生产端六字段、包身份补齐，`std/std` 经默认索引端到端通过；(b) 默认 clone 固定 commit（外部仓无 tag），`ct pkg index update` 记录并可回退 pin；(c) 安装默认**不**因索引失败而失败，原子落盘、尊重 `CT_HOME`、不新增 git 硬依赖（可用 `curl` 归档或显式 `--with-index`）；(d) 删除 A4，`ct pkg publish` 只打印/触发 CI，不执行带 token 的脚本；(e) 先修 G4（限定名索引未命中不得落 `https://<publisher>/<name>`）。在 (a)–(e) 落地前，B 胜；落地后 A′ 只在 J-4 胜出，J-1/J-2/J-5 仍按 B 的守卫。

复现链：`ct` 用 `ct v0.65.1`（`/Users/samxx/.local/bin/ct`）；夹具与外部快照见 `/tmp/idx-e1`、`/tmp/idx-*`；`install.sh` 离线安装产物 `/tmp/idx-e1/prefix`。仓库只新增本文件，未改源码/规范/测试。
