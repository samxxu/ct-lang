# ct-pkg 生态：四个角色与边界

> 中文
>
> 分清「谁提供什么、谁消费什么、谁发布什么」。本文只做职责与入口索引，包清单细节见
> [package-guide](package-guide.md)，索引字段见 [ct-pkg-index](ct-pkg-index.md)。
> 核对基线：`ct` 0.77.1（2026-11-20）。

## 1. 四个角色

| 角色 | 归属 | 提供什么 | 消费/发布入口 |
| --- | --- | --- | --- |
| 编译器 | 本仓 `ct-lang` | `ct` / `ctc` 二进制、语言语义、包解析与 `ct get` | `ct`；源码在 `selfhost/ct-ast/**` |
| 标准库 | `ct-pkg/std`（规范名 `ct/std`） | `std::str` / `fs` / `io` / `utf8` / `num` / `math` / `search` / `arena` / `test` / `env` / `process` / `errno` / `locale` / `wchar` / `time` / `net` | 消费 `ct get ct/std`；目录见 [std-catalog](std-catalog.md) |
| 平台包 | `ct-pkg/hal`（契约）、`ct-pkg/hal-posix`（平台实现） | 硬件抽象与 POSIX 平台能力 | 仓在 ct-pkg；**当前只有 `ct/std` 进内置 pin 表** |
| 索引 / 发布 | `ct-pkg/index` | 纯文本索引、`tools/package.sh`、索引生成与 CI | 发布端脚本 + CI；**不在 `ct` 二进制里** |

## 2. 本仓不内置 `std`

- `std` 是独立 ct-pkg 包，不随本仓发布；本仓 `test/std/` 已移除。
- 本仓 `lib/core/` **只承载编译器内置层**：`Vec` / `Map` / `MapEntry` / `Option` / `Result` / `Str`，
  自动预解析、免 `import`，见 [lib/core/README](../lib/core/README.md)。它不是 `std` 包，也不复制
  `std::str` / `std::fs` 等模块。
- 消费入口是 `ct get`：官方身份 `publisher = ct`，规范名 `ct/std`，落
  `$CT_HOME/pkg/ct/std/<version>/`；`ct build` 按 `ct.lock` 自动补 include root。

## 3. 消费、发布、索引不是同一条命令

| 动作 | 入口 | 属于谁 | 边界 |
| --- | --- | --- | --- |
| 消费 / 安装包 | `ct get` + `ct build` / `ct install` / `ct verify` / `ct update` / `ct migrate` | `ct` 二进制 | `ct get` 是包管理路径里唯一可能调用系统 `git` 的命令；编译器核不联网 |
| 发布包 | `ct-pkg/index` 仓的 `tools/package.sh`（tag / release / 索引行） | 包仓 + 索引仓 CI | 需要 token；**不挂进 `ct`**，避免把写仓库凭据带进面向所有用户的二进制 |
| 生成 / 刷新索引 | `ct-pkg/index` 仓的生成器与 CI | 索引仓 | 新包在首次有效 release 后进入索引；客户端不扫描组织 |
| 只读 preflight | `ct pkg check <dir>`（原生检查，与 `package-check.sh` 的 PK-1/2/5/8 对齐） | `ct` 二进制 | 检查清单 / `ns-root` / `c-boundary` 等；**不是发布 API** |

`ct pkg` 的边界按 [D-010](decisions/D-010.md) 定稿为 **B′**：`ct pkg` 是 `ct install` 的别名，
`ct pkg check <dir>` 是原生只读检查；不做 `package.sh` 透传。DOC-73 早先把 `ct pkg check` 写成
「过渡」，该说法已被 v0-PH-77 / D-010 的 B′ 定稿取代。

## 4. 当前可解析范围（实测）

- **官方 pin 表只有 `ct/std`**（`std 0.20.0`，url / tag / sha256 编译进 `ct`）：
  `ct get ct/std` 与 `ct get std` 都是无索引可用的官方路径。
- **`ct/hal` 目前不在 pin 表**：仓库在 `ct-pkg/hal`，但官方索引行仍是五字段旧行（无 `publisher`）。
  按契约 v1（[D-014](decisions/D-014.md) 第 5 条），请求命中五字段行**按行硬错**；要用它必须给
  六字段索引行（`--index` / `CT_INDEX`）或显式 URL，直到包仓补 `publisher = ct` 并刷新索引。
- 第三方包必须写 `<publisher>/<name>`；裸名只解析官方包，不查索引。
- 索引当前没有签名；pin 表只对官方包提供强校验，第三方索引只是便利，见 [ct-pkg-index](ct-pkg-index.md)。

## 5. 不做什么

- 不把 `std` 或 `hal` 源码复制进本仓；
- 不把发布脚本、token、索引维护逻辑写进 `ct`；
- 不默认联网、不自动 clone 索引；
- 不把 `proposals/` 里的索引/发布提案当现状（提案归目标仓受理）。
