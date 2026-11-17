# battle/index-pkg-1 判决

> **状态：`closed`**（2026-11-18；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **结论：B 胜。`ct pkg` 保持 `install` 别名 + 原生 `check`；不把参数透传给 index 仓 `package.sh`。仅接受“`ct pkg init` 一次性拉取/校验索引”这半个 A。**

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 语义/兼容 | **B 胜** | `ct pkg` 无参/`--help` 与 `ct install` 逐字相同；`ct pkg check` 是只读原生入口。A 把 `ct pkg check` 透传给 `package.sh` 会与 `package.sh:199` 自己调 `ct pkg check` 冲突，实测参数错位/失败。 |
| J-2 安全 | **B 胜** | `package.sh publish` 需要 `GITHUB_TOKEN`/REST 写权限；任意 argv 透传扩大写面。凭据不能进 `ct` 进程环境。 |
| J-3 架构 | **B 胜** | `package.sh` 在 `37fa8a3` 里**未被提交**，工作树 mode 644，默认 `STAGING=~/vscspace/ct-pkg`；消费者机没有这些前提。A 的 `$CT_HOME/index/package.sh` 不存在。 |
| J-4 UX | **unresolved** | A 的 init 缺口真实（无索引时 `ct get` 要求手写 `--index`），B 的消费者机不可用也真实；两边各一半。 |
| J-5 索引质量 | **B 胜** | 官方 index 仍是 12 行五字段、无 publisher/签名/tag/pin；不能作为执行 `package.sh` 的信任根。 |
| J-6 成本/回退 | **B 胜** | `ct pkg` 0 行改动、失败面小；A 未实现，且“256 函数已满”是过期注释（实际 512），成本论据不成立。 |

## 2 采纳：B′

1. `ct pkg` 保持 `ct install` 别名；`ct pkg check <dir>` 保持原生只读。
2. **接受 `ct pkg init` 作为一次性索引设置**：
   - 显式命令，不自动在首次 `ct pkg` 时偷偷拉；
   - 固定 commit/tag，不跟匿名 main；
   - 原子写 `$CT_HOME/index`，失败不污染；
   - 校验签名/摘要；尊重 `CT_HOME`；
   - 只拉索引，**不执行** `package.sh`。
3. `ct pkg <args>` **不透传**给 `package.sh`；发布仍由 index 仓 `package.sh`/CI 执行。
4. 若未来要统一发布入口，另立 `ct-pkg` 独立工具，不塞进 `ct` 二进制。

## 3 不采纳

- `ct pkg` 作为 `package.sh` 透传捷径：破坏 `ct pkg check` 消费点、参数语义、权限边界。
- 首次 `ct pkg` 自动 init：隐式联网；应显式 `ct pkg init`。
- 在 install.sh 拉 index：与 index-install-1 判决冲突。
- 把 publish/release 脚本放进 `ct pkg`：复开已被否决的 A4。

## 4 证据限制

- `package.sh` 在工作树是未跟踪文件，`37fa8a3` 无该路径；A 的 init/透传未实现，用等价 wrapper 模拟，不称实测 A 代码。
- 官方 index 只读快照；签名/pin 未实现。
- `ct pkg init` 是建议新增，不是当前功能。

## 5 下一步

- 先修索引：六字段、publisher、`std/std` 解析、签名/pin；
- 再评估 `ct pkg init`（只读索引）是否值得做；
- `ct pkg` 的脚本透传不做；发布留在 CI。
