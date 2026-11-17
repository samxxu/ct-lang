# battle/index-install-1 — 反证书（主张 B）

| 字段 | 值 |
| --- | --- |
| 主张 | B：`install.sh` 只装编译器；索引更新显式 `ct index update` 且 pin/验签；`ct pkg` 只读、不执行发布脚本；发布留在 index 仓 CI |
| 基线 | `792d5bc1`（v0.65.1）；`ct` 由该提交源码经 `install.sh` 自举为 `/tmp/ct-b/bin/ct` |
| 环境 | macOS / `cc`（Apple clang）、`git`、`curl`；证据均在 `/tmp/ct-b` 重跑 |
| 不可复现项 | `ct-pkg/index` 是外部仓，本机不存在（`ls ~/.ct` → `pkg  pkg-backup`）；凡依赖该仓脚本/签名的断言只引用提案文本，不称实测 |

## 1. B 的安装 / 索引更新 / 发布边界

| 层 | B 的边界 | 现状锚点 |
| --- | --- | --- |
| 安装 | 只「下载归档 → 自举 → 安装二进制」；不 clone 索引、不写 `~/.ct/index`、不新增 `git` 依赖 | `install.sh:59-61`、`install.sh:168-172`、`AGENTS.md:519`、`AGENTS.md:528-532` |
| 索引更新 | 索引侧唯一网络入口是显式 `ct index update --ref <commit 或 tag> [--verify]`：`git` 取固定 commit，记录 `git rev-parse HEAD`，验签失败或摘要不符即拒绝且原子替换 | `Pkg.h.ct:132-134`、`Pkg.h.ct:2167`、`Pkg.h.ct:2507-2509` |
| 索引消费 | 仍走 `--index <file>` / `CT_INDEX`；索引行自带 `sha256:<64 hex>`，客户端逐包校验，不符不写 `ct.lock`、不落 store | `docs/package-guide.md:112-121`、`Pkg.h.ct:2149-2160`、E1-4 |
| `ct pkg` | 只读：`ct pkg check`（read-only audit）、`ct install`（校验+打印命令）；不执行 index 仓脚本、不写索引、不接触 credentials | `main.ct:121-122`、`Pkg.h.ct:1742-1748`、`Pkg.h.ct:2949-2956` |
| 发布 | 由 index 仓 CI 生成/校验/签名/提交，客户端只消费固定索引 | 提案 `docs/proposals/ct-pkg-index-proposal.md:59`（CI 唯一写者）、`:12,113`（消费固定索引、不客户端扫描）；`docs/proposals/ct-pkg-package-maintainer-rules.md:57`（提案，待目标组受理） |
| 失败 | 索引拉取失败不影响已装 `ct`；无索引时 `ct get` 维持既有硬错与一键指引 | `Pkg.h.ct:1133-1150`、E1-2 |

## 2. E1 命令 + 原始输出

### E1-1 安装不碰索引（利 B）

```console
$ cd /Users/samxx/dsh-ws/ct-lang
$ HOME=/tmp/ct-b/home CT_SOURCE_DIR=. ./install.sh --prefix /tmp/ct-b/bin >/tmp/ct-b/install.log 2>&1; echo "rc=$?"
rc=0
$ grep -E 'using local|installed /tmp' /tmp/ct-b/install.log
==> using local source tree /Users/samxx/dsh-ws/ct-lang
==> installed /tmp/ct-b/bin/ct (ct v0.65.1) and /tmp/ct-b/bin/ctc
$ grep -nE 'git clone|CT_INDEX|index' install.sh | wc -l
       0
$ ls /tmp/ct-b/home/.ct/index
ls: /tmp/ct-b/home/.ct/index: No such file or directory
```
### E1-2 用户要多一步（不利 B）

```console
$ mkdir -p /tmp/ct-b/proj0 && cd /tmp/ct-b/proj0
$ HOME=/tmp/ct-b/home /tmp/ct-b/bin/ct get ct/std; echo "rc=$?"
ctc: no index resolver for 'ct/std'
  'ct/std' is a publisher-qualified package name; without an index
  there is no mapping from that name to a git URL.
  Choose the case that matches how the package is published:
  1) built-in / official library (bare name, no publisher):
       ct get std
     uses CT_REGISTRY (default https://github.com/ct-pkg).
  2) publisher-qualified package (what you typed):
       ct get --index <file> ct/std
       CT_INDEX=<file> ct get ct/std
     the index is a local plain-text file; line format:
       name version publisher git-url tag sha256:<64 hex>
  3) known git URL:
       ct get https://<host>/<publisher>/<repo>
  4) local checkout:
       ct get ./path-to-std
  Note: CT_REGISTRY only applies to bare names without '/';
        'ct/std' requires an index (case 2) or a URL/path (case 3/4).
rc=1
```
### E1-3 索引不自动更新会过期（不利 B）；E1-4 摘要校验（利 B）

```console
# 夹具：本地 git 包 acme/hello，索引只收录 1.0.0，上游随后 tag v1.1.0
$ mkdir -p /tmp/ct-b/fix/repo/hello && cd /tmp/ct-b/fix/repo/hello
$ printf 'name = hello\npublisher = acme\nns-root = .\nversion = 1.0.0\n' > ct.pkg
$ printf 'pub fn hello() -> int\n{\n    return 42;\n}\n' > hello.h.ct
$ git init -q && git add -A && git -c user.email=a@b -c user.name=a commit -qm v1 && git tag v1.0.0
$ mkdir -p /tmp/ct-b/fix/proj1 && cd /tmp/ct-b/fix/proj1 && HOME=/tmp/ct-b/fix/h1 /tmp/ct-b/bin/ct get ../repo/hello | grep digest
  digest   sha256:2681199aa55c27c3aedb361f7f15a4087d73fc882004948b6fb6644e9590c3bb
$ printf 'hello 1.0.0 acme file:///tmp/ct-b/fix/repo/hello v1.0.0 sha256:2681199aa55c27c3aedb361f7f15a4087d73fc882004948b6fb6644e9590c3bb\n' > /tmp/ct-b/fix/index
$ cd /tmp/ct-b/fix/repo/hello && sed -i '' 's/version = 1.0.0/version = 1.1.0/' ct.pkg
$ git add -A && git -c user.email=a@b -c user.name=a commit -qm v2 && git tag v1.1.0
$ mkdir -p /tmp/ct-b/fix/proj3 && cd /tmp/ct-b/fix/proj3
$ HOME=/tmp/ct-b/fix/h3 CT_INDEX=/tmp/ct-b/fix/index /tmp/ct-b/bin/ct get hello@^1.1.0; echo "rc=$?"
ctc: package 'hello' is not in the index
rc=1
$ printf 'hello 1.1.0 acme file:///tmp/ct-b/fix/repo/hello v1.1.0 sha256:a6c85149664f995a34f394866a876f02801fea29e8fc48a599bf760cb07a6775\n' >> /tmp/ct-b/fix/index
$ mkdir -p /tmp/ct-b/fix/proj5 && cd /tmp/ct-b/fix/proj5
$ HOME=/tmp/ct-b/fix/h5 CT_INDEX=/tmp/ct-b/fix/index /tmp/ct-b/bin/ct get hello@^1.1.0; echo "rc=$?"
requested  hello@^1.1.0
resolved   acme/hello 1.1.0
  source   git file:///tmp/ct-b/fix/repo/hello
  tag      v1.1.0
  commit   14bf00a134ab4f52476ff069db7f7f4dec64d597
  store    /tmp/ct-b/fix/h5/.ct/pkg/acme/hello/1.1.0
  digest   sha256:a6c85149664f995a34f394866a876f02801fea29e8fc48a599bf760cb07a6775
  action   installed
1 package(s): 1 installed, 0 reused
rc=0
$ sed 's/a6c85149664f995a34f394866a876f02801fea29e8fc48a599bf760cb07a6775/0000000000000000000000000000000000000000000000000000000000000000/' /tmp/ct-b/fix/index > /tmp/ct-b/fix/index-bad
$ mkdir -p /tmp/ct-b/fix/proj7 && cd /tmp/ct-b/fix/proj7
$ HOME=/tmp/ct-b/fix/h7 CT_INDEX=/tmp/ct-b/fix/index-bad /tmp/ct-b/bin/ct get hello@^1.1.0; echo "rc=$?"
ctc: 'hello' does not match the index (source sha256:a6c85149664f995a34f394866a876f02801fea29e8fc48a599bf760cb07a6775, index sha256:0000000000000000000000000000000000000000000000000000000000000000)
rc=1
$ ls ct.lock
ls: ct.lock: No such file or directory
```
## 3. E2 `file:line` 锚点

| 方向 | 锚点 | 内容（摘要，逐字见文件） |
| --- | --- | --- |
| 利 B | `AGENTS.md:519`、`AGENTS.md:528-532` | `install.sh` 只准维护「下载 + 自举 + 安装」三件事；只用 `cc`/`tar`/`curl`，**不需要 `git`**。A 的 clone 需 `git`，越界 |
| 利 B | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:132-134` | 「Nothing is built in -- a package name only resolves through an index the user named」 |
| 利 B | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:2507-2509` | v2 update 是离线 pin 审计；「no new version can appear without a network fetch」——显式索引更新与之同构 |
| 利 B | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:1742-1748` | `ct pkg check` 被定位为 read-only audit；发布不属于同一入口 |
| 不利 B | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:707-713` | 裸名默认 `CT_REGISTRY` 即 `https://github.com/ct-pkg`：客户端已有隐式网络默认，B 的「零隐式网络」只是局部成立 |
| 不利 B | `install.sh:72-74` | 默认安装本身下载 GitHub 归档并联网；B 的「离线安装」只在 `CT_SOURCE_DIR` 或预下载时成立 |
| 不利 B | `install.sh:187` | Next steps 要用户手动 `ct get ct/std`；A 的 index clone 也省不掉这一步 |
| 不利 B | `selfhost/ct-ast/tool/pkg/Pkg.h.ct:1133-1150` | 无索引时 publisher 名硬错并打印十余行指引；B 的默认体验确实多一步 |

## 4. E3 可证伪预测

| # | 若 B 成立，运行 X 应得 Y | 一次性反证条件 |
| --- | --- | --- |
| P1 | 在断网、空 `HOME` 下 `CT_SOURCE_DIR=. ./install.sh` 得 rc=0，且 `$HOME/.ct/index` 不存在、`install.sh` 无 `git clone`/`git` 调用 | 安装写 `~/.ct` 或调用 git/网络 → B 的安装边界不成立 |
| P2 | `ct index update --ref <commit>` 后 `git -C ~/.ct/index rev-parse HEAD` 等于该 commit；上游前进到新 commit 后 `ct get` 解析结果不变，直到再次显式更新；无 `--ref` 时拒绝匿名 main | 更新跟随 main、或 install/get 自动更新 → B 退化为 A |
| P3 | 索引行被篡改或签名缺失时 `ct index update`/`ct get` rc≠0、不写 `ct.lock`、不落 store（摘要部分已实测：E1-4） | 接受未验签/摘要不符的索引 → B 的 pin/验签承诺不成立 |
| P4 | `ct pkg publish` 保持 `unexpected argument`；二进制内无 publish/token 路径；索引仓 CI 仍是唯一写者 | 二进制出现发布/凭据代码或执行 index 仓脚本 → B 的发布边界不成立 |

## 5. E4 代价（与 A 对比）

| 项 | A（默认 clone + 发布映射） | B（显式更新 + 只读消费） |
| --- | --- | --- |
| 改动文件/行数（估） | `install.sh` +10–15（191 行）；`main.ct` +2–4（124 行）；`Pkg.h.ct` +80–150，且该单元已在 256 函数上限（`Pkg.h.ct:98`）→ 可能新增单元 150–300 行；文档 +10–20；`test/pkg/run.sh` +40–80 | `main.ct` +2；`Pkg.h.ct` +30–70（`--ref` 解析、git 取固定 commit、pin 记录；验签交给 `git verify-commit/tag`，不内置密码学）；`install.sh` 0 行（可选 +2 行 Next steps）；文档 +8–15；`test/pkg/run.sh` +20–40 |
| 影响门禁 | G3（test/pkg 新用例）、G4（文档）、G8（`install.sh` 与 CLI 行为变更须用户确认，`AGENTS.md:531-532`、`:606`）；发布 token 进仓库会触发 G7 密钥扫描 | G3、G4、G8（仅 CLI 新增须确认）；install 行为不变，不触发安装脚本确认 |
| 回退步骤 | revert 4–5 个文件；`rm -rf ~/.ct/index`；轮换发布 token；index 仓回滚已推的索引提交并通知已拉取的用户 | revert 2–3 个文件；无全局状态（`~/.ct/index` 只在显式命令后出现，可删）；index 仓零改动 |
| 权限/失败模式 | 安装期多一个网络依赖（失败虽“降级”，但随后 `ct get` 仍无索引）；开发机持有写 token；执行 index 仓脚本=以用户权限跑外部代码；匿名 main 使供应链不可审计 | 索引过期显式可见（E1-3 的硬错）；发布走 CI 有延迟；需维护签名/CI secret；客户端无 token、无发布代码 |

## 6. E5 steelman A 及逐条反驳

A 最强原文（`question.md:15-19`，逐字）：「`install.sh` 安装 `ct` 后，默认 `git clone https://github.com/ct-pkg/index` 到 `~/.ct/index`」；「`ct pkg publish` / `ct pkg index publish` 直接调用 index 仓的发布脚本，完成校验/签名/提交」；「安装失败时 index 拉取失败不阻断 `ct` 安装（降级）」。

Steelman：①安装即用——E1-2 的十余行错误正是 A 要消灭的，A 让 `ct get ct/std` 开箱可用；②统一入口——`ct pkg` 已是包入口（`main.ct:121-122`），加 index/publish 发现性最好；③新鲜度——E1-3 的过期错误真实存在，自动 clone/pull 不会过期；④与现状一致——裸名已默认联网（`Pkg.h.ct:707-713`），A 不是新原则。

| 论点 | 反驳 |
| --- | --- |
| 安装即用 | 包仍要 `git` 拉取（`Pkg.h.ct:746-747`；`docs/package-guide.md:140-142`），`std` 仍要单独 `ct get`（`install.sh:172,187`）；A 只省「索引接线」一步，却把可变 main 变成安装期信任根。B 用一行 `ct index update --ref <tag>` 或 `CT_INDEX` 即可，且可写进 Next steps（零网络） |
| 统一入口 | 消费只读、发布写+签名+凭据，是两个信任域；`ct pkg check` 已被限定 read-only（`Pkg.h.ct:1742-1748`）。把发布脚本放进每个用户的二进制，等于把写权限代码分发给所有人；且 256 函数预算已满（`:98`），新增子命令要拆单元/改自举，成本落在 A |
| 新鲜度 | 自动 main 让未审索引即时到达所有用户，与 J-2 及提案的「签名、pin、失败关闭」（`docs/proposals/ct-pkg-index-proposal.md:102-106`、`:59`）冲突；B 的过期是显式、可见、可用 pin 复现的失败（E1-3），A 的过期/攻击是静默的 |
| 与现状一致 | `CT_REGISTRY` 是裸名官方路径，提案明确不改其语义（`docs/proposals/ct-pkg-index-proposal.md:34-36`）；A 把隐式网络扩展到第二个 artifact，是扩大而非对齐。要一致应先收敛 `CT_REGISTRY` |

## 7. 结论与失效条件

**B 胜出**（J-1/J-2/J-3/J-5；A 仅在 J-4「省一步」上占优，且省不掉包下载）。B 同时成立的条件：①`ct index update` 必须带 `--ref`（或默认固定 tag），绝不隐含 main；②更新失败关闭、原子替换，摘要/签名不符不落盘；③`install.sh` 不新增 git、不写 `~/.ct`；④`install.sh` 的 Next steps 打印索引命令，否则用户仍撞 E1-2 的墙。

B 不成立的条件：`ct index update` 退化为 `git pull main` 且无 pin/验签（则 B=A+多打一条命令）；索引仓 CI 不可用而只能本地发布（此时「发布在 CI」失效，但发布脚本仍不应进 `ct`）；项目明确以「安装即用」压过可复现/供应链（价值判断，交用户）。

反证清单（任一条被证实即 B 该条不成立）：①安装写 `~/.ct/index` 或调用 git；②`ct pkg` 已执行发布脚本/持有 token；③索引行无 `sha256` 或客户端不校验（现状已校验，E1-4）；④`ct index update` 跟随 main、无 pin/验签；⑤无索引时 `ct get` 不能给出一键修复（E1-2 已示，需在 B 中补文档/命令）；⑥索引更新需要写权限（读索引应可离线、可只读）。
