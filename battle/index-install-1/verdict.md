# battle/index-install-1 判决

> **状态：`closed`**（2026-11-18；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **结论：B 胜；A 的“install.sh 默认 clone index + ct pkg 执行发布脚本”不成立。可以采用 B′：安装不新增 git/index 依赖；索引显式更新并 pin；发布留在 index CI。**

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 离线/可复现 | **B 胜** | 现状离线 `CT_SOURCE_DIR` 安装 rc=0、不写 `$HOME/.ct`；A1 clone 在代理黑洞 rc=128，目标已存在再 clone rc=128，无原子落盘。准确边界不是“安装完全不联网”（源码归档本来要下载），而是**不新增 git/index 依赖**。 |
| J-2 供应链 | **B 胜** | 官方 `ct-pkg/index` main `f7fb1d85` 是 12 行五字段、无 tag、无 `.sig`、commit 未签名；A1 默认匿名 main 等于把可变索引当信任根。仅替换索引行即可把同一 `acme/hello@0.1.0` 装成不同内容（42 vs 666）。 |
| J-3 架构边界 | **B 胜** | 编译器核零网络；包路径只有 `git_run` 一个调用点，但一次全新 `ct get` 实测 spawn 4–5 个 git 进程；“单调用点”不等于“单子进程”。A4 让 ct 执行发布脚本，直接引入 credentials/写权限。 |
| J-4 UX | **A 仅窄胜** | 安装即用确实省一步；但官方索引五字段导致 `std/std`/`ct/std` 解析成 `https://std/std` 并失败，A1 会把“明确报错”退化成“错误 URL clone”。当前手动 `CT_INDEX=...` 只多一行。 |
| J-5 发布工作流 | **B 胜** | `release-package.sh` 需要 repo+workflow PAT，`index.yml` 是 `contents: write` CI；`ct pkg` 今天是 `ct install` 别名，`ct pkg index/publish` 全部 rc=1。发布不该进编译器二进制。 |
| J-6 成本/失败模式 | **B 胜** | install.sh 0 行改动；A 未实现，失败模式已实测：离线、重复 clone、索引过期、`CT_HOME` 与 `$HOME/.ct` 不同根。 |

## 2 采纳：B′

1. **install.sh 不默认 clone index**；保持“下载源码 + 自举 + 安装”，不新增 git 依赖。
2. **索引显式更新**：未来若加 `ct pkg index update`，必须：
   - 用固定 commit/tag，不跟匿名 main；
   - 原子写临时目录，失败不污染 `~/.ct/index`；
   - 尊重 `CT_HOME`，不要固定 `$HOME/.ct`；
   - 有签名/摘要校验；
   - 离线失败只提示，不阻断 `ct`。
3. **消费端可选**：`ct get` 可读取已存在的 `$CT_HOME/index/index`，但**不自动联网**；`CT_INDEX` 仍可覆盖。
4. **发布留在 index 仓 CI**：`ct pkg` 不执行带 credentials 的发布脚本；最多提供只读 `ct pkg index check`/打印 CI 触发说明。
5. **先修索引生产端**：官方索引当前五字段、`std/std` 解析失败；先达到六字段、publisher/ns-root、签名/pin，再谈安装集成。

## 3 不采纳

- A1：install.sh 默认 clone 匿名 main；离线/重复安装/供应链都不过。
- A4：`ct pkg publish` 直接执行 `release-package.sh`；credentials 进二进制、权限过大。
- “安装即用”作为默认：当前索引不可信/不完整，默认只会把错误前移。
- 把“安装本来联网”当作 clone 索引的理由：源码下载与可变索引是两种信任模型。

## 4 证据限制

- `ct-pkg/index` 是外部仓；main 快照 `f7fb1d85`，无 tag/签名；发布脚本按文本审阅，未执行写操作。
- A1/A4/A5 与 `ct pkg index update` 均未实现，失败模式基于等价命令探针。
- 一次 `ct get std` 30s 超时属网络波动；120s 下成功；证据已标 `unreproduced`。

## 5 下一步

- 若要“安装即用”，先做 **可选** `install.sh --with-index`（pin commit + 原子 + 签名），不要默认。
- 索引仓先修五字段→六字段、`std/std`、签名/pin；否则任何自动消费都会放大错误。
- 发布仍由 index CI 做；`ct pkg` 保持只读/包管理，不接管 credentials。
