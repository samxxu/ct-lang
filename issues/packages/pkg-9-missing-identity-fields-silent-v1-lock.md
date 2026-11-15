# PKG-9 · 清单缺 `publisher` / `ns-root` 时 `ct get` 静默降级为 v1 lock

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct get` / 清单身份字段 / lock 格式选择） |
| 定性 | **实现缺陷（该报错而沉默）**，不是缺功能；缺必填字段被当成「旧清单」，自动退回 v1 |
| 严重度 | **High** —— 契约静默降级：不写 store、不写 `# ct-lock 2`、不报错，rc=0 |
| 优先级 | **P0**（包线 patch 序列第 2 位） |
| 状态 | **open** |
| 锚点 | 复现于 `v0.58.0`（`45f882a7`）；行号按 `v0.58.1`（`fb82420c`）复核，PKG-5 修复后整体 +46 行 |
| 文件 | [Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct)：`:998`、`:1153`、`:1157`、`:1163`、`:1204-1208`、`:1214-1223`、`:1439`、`:1711`、`:1719`、`:1816-1854` |

## 现象

`ct.pkg` 缺 `publisher` 或 `ns-root` 时，`ct get <dir>` 仍打印 `vendored 1 package(s)` 并返回 0，
但：

- 不写共享 store；
- `ct.lock` 不写 `# ct-lock 2` 头，行退化成 v1 单行 `name ver dir ... digest`；
- 只有主动运行 `ct pkg check` 才会报缺字段。

## 复现（2026-11-15，v0.58.0）

夹具：`p1` 有 `publisher = ct` / `ns-root = src`；`p2` 只有 `name` / `version`。

```console
$ ct get /tmp/repro58/p1
vendored 1 package(s)
$ cat ct.lock
# ct-lock 2
ct/demo 0.2.0 dir /tmp/repro58/p1 - src sha256:56135044...
```

```console
$ ct get /tmp/repro58/p2
vendored 1 package(s)
$ echo $?
0
$ cat ct.lock
demo 0.2.0 dir /tmp/repro58/p2 sha256:8d6ab120...
```

```console
$ ct pkg check /tmp/repro58/p2
ctc: '/tmp/repro58/p2/ct.pkg' is missing 'publisher'
ctc: '/tmp/repro58/p2/ct.pkg' is missing 'ns-root'
$ echo $?
1
```

## 代码定位

1. `Pkg.h.ct:1153` 的 `read_manifest` 只读 `name` / `version` / `dep`，不校验 `publisher` / `ns-root`。
2. `Pkg.h.ct:1157` 调 `pkg_read_identity`；该函数（`:1816-1854`）把两个字段初始化为空串，
   读不到也返回 0，**不区分「缺失」与「为空」**。
3. `Pkg.h.ct:1163` 用 `s1 = (publisher[0] || nsroot[0])` 决定走不走 S1：
   **两个字段都缺 → `s1=0` → 自动按旧清单处理**。这就是「缺字段就按 v1」的判定点。
   索引 / git 路径有同一处判定：`:998`（`fetch_git` 返回后按缓存目录读取身份），修复须同时覆盖两条路径。
4. `Pkg.h.ct:1204-1208` 在 `s1=0` 时跳过 `pkg_store_commit`；
   `:1214-1223` 写 v1 行；`:1439` 因 `lockv2` 未置位而不写 `# ct-lock 2`。
5. 强制校验只存在于 `ct pkg check`：`:1711`（缺 `publisher`）、`:1719`（缺 `ns-root`）。

> 行号变化说明：v0.58.0 的 `:1107/:1111/:1117/:1158-1162/:1173-1176/:1393/:1665/:1673/:1770-1808`
> 在 PKG-5 修复（`fb82420c`，缓存键带发布方 + origin 校验）后整体后移 46 行，逻辑本身未变；
> 上列为 v0.58.1 的实际行号。

## 期望行为

1. `ct get` 对缺必填字段的清单**直接失败**，rc≠0，文案指名缺哪个字段（可复用 `ct pkg check` 的两条文案）；
   不得静默降级到 v1，也不得留下半份 `vendor/` 或 `ct.lock`。
2. 旧清单读取能力（如确实需要）必须由**显式开关**触发，例如 `--allow-v1-manifest`
   或环境变量 `CT_PKG_ALLOW_V1=1`；不得再靠「字段缺失」自动判断。
3. 开关的优先级写清：显式开关 > 字段完整性；未开开关时，缺任一字段即硬错。
4. `ct pkg check` 的现有文案与 rc 不变。

## 验收判据（可执行）

| # | 输入 | 期望 |
| --- | --- | --- |
| A1 | 缺 `publisher`，其余齐全 | `ct get` rc≠0，stderr 含 `is missing 'publisher'`；不生成/不改 `ct.lock`，不写 `vendor/` |
| A2 | 缺 `ns-root`，其余齐全 | `ct get` rc≠0，stderr 含 `is missing 'ns-root'`；同上 |
| A3 | 两字段齐全 | rc=0；`ct.lock` 首行为 `# ct-lock 2`；行含 `publisher/name` 与 `ns-root`；store 有对应版本目录 |
| A4 | 旧的无字段清单 + 显式开关 | rc=0；按 v1 行落盘，行为与今日兼容 |
| A5 | 旧的无字段清单，未开开关 | rc≠0，文案说明缺字段并提示开关 |
| A6 | 失败路径 | 不产生 `vendor/<name>`，原 `ct.lock` 字节不变 |
| A7 | `ct pkg check` 对同一夹具 | rc=1，两条缺失文案逐字不变 |

## 交叉引用

- [PKG-3](pkg-3-unknown-keys-silently-ignored.md)：同一「清单容忍未知/残缺」家族；本条处理必填缺失，PKG-3 处理未知键告警。
- [PKG-4](pkg-4-duplicate-package-name-silent-first.md)：同类静默择一，已由 S2 修为硬错，可作为文案与判据的样式参考。
- [LANG-4](../lang/lang-4-subscript-type-mismatch-silent-empty.md)：参数类型无匹配时静默走空值，同属「该报错而沉默」。
- [LANG-17](../lang/lang-17-preprocessor-line-truncation.md)：静默截断，同属「编译通过但语义已变」。

## 版本位

**建议 v0.58.2**。PKG-5 已于 v0.58.1（`fb82420c`）交付，本条因此成为**包线第一个待修项**；
版本位不变（v0.58.2 仍是 0.58.1 之后的第一个 patch），PKG-6 顺延至 v0.58.3、PKG-3 至 v0.58.4。
位次前移指执行顺序，不另占新号。
