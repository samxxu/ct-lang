# ct-pkg 共享库包体系 · 需求定稿

| 项 | 值 |
| --- | --- |
| 状态 | **已定稿**（2026-11-15；依据 [提案](../proposals/ct-pkg-shared-store.md) §12 五条裁定） |
| 性质 | **契约变更**，不是增量字段：`docs/package-guide.md` §1 现写死「包根 = 单元根、单元与 `ct.pkg` 并列不嵌套」，本需求以 `ns-root` 取代该契约；`ct install` 的 `-I vendor/<name>` 输出契约同时作废 |
| 判据形态 | 全部为二值判据（通过/失败），每条给出可执行验收命令；不含主观项 |
| 施工入口 | [phase54.md](../history/design/phase54.md)（S0 卡）；切片与版本位见 [roadmap §ct-pkg 共享库](../roadmap.md) |
| 变更控制 | 判据只能更严不能放宽；如需改判据，另起 errata 并保留原文 |

## 1. 术语

- **store**：每用户共享库 `$CT_HOME/pkg`（`CT_HOME` 默认 `$HOME/.ct`）。
- **包身份**：`<publisher>/<name>`，磁盘 `<store>/<publisher>/<name>/<version>/`。
- **ns-root**：包声明的单元树根（相对包根），`-I` 指向 `<版本目录>/<ns-root>`。
- **dev override**：同包名的本地目录覆盖 store 版本，必须双留痕。
- **v1 / v2 lock**：带 `# ct-lock 2` 头的为 v2；无头的旧文件为 v1。

## 2. 需求条目

### 身份与落盘

| ID | 要求（二值判据） | 验收命令 | 切片 |
| --- | --- | --- | --- |
| SP-001 | `ct get <pub>/<name>@x.y.z` 后存在 `<store>/<pub>/<name>/x.y.z/ct.pkg`，且该目录不再位于项目内 | `ct get ct/std@0.1.0 && test -d "$HOME/.ct/pkg/ct/std/0.1.0" && test ! -e vendor/std` | S1 |
| SP-002 | `publisher` 在 `ct.pkg` 中**必填**；缺失、为空、或写成 `local` 占位均失败 | `ct pkg check R` 输出含 `is missing 'publisher'` 且 RC≠0 | S0 检出 / S1 落地 |
| SP-003 | `ns-root` **必填且无默认值**；缺失即硬错 | `ct pkg check R` 输出含 `is missing 'ns-root'` 且 RC≠0 | S0 检出 / S1 落地 |
| SP-004 | `ns-root` 必须是相对路径、不含 `..`、目录存在 | 同上，输出含 `ns-root '<v>' must be a relative path without '..'` 或 `is not a directory` | S0（S0 只查存在与形态） |
| SP-005 | 库内同名包的多个版本目录可并存：`<ver1>/` 与 `<ver2>/` 同时存在不报错、不互相覆盖 | `ls "$HOME/.ct/pkg/ct/std"` 同时列出两个版本目录 | S1 |
| SP-006 | 同一次构建不得解析同一包的两个版本：lock 一包一行；出现两条同名行即硬错 | 手工构造两行同名 lock → `ct install` RC≠0 且文案指明重复 | S2 |

### 解析与构建

| ID | 要求（二值判据） | 验收命令 | 切片 |
| --- | --- | --- | --- |
| SP-007 | 解析顺序固定：本地目录 → store → 联网；`ct install` / `ct build` 只允许前两步 | 断开网络后 `ct install` 在 store 命中时 RC=0；store 缺失时 RC≠0 且**不**发起 git | S1/S2 |
| SP-008 | `ct build` **默认读 `./ct.lock`** 并自动补 `-I`，用户不必传 `-I` | 删除命令里的 `-I` 后 `ct build main.ct -o build` RC=0 | S2 |
| SP-009 | `ct build --locked` 在 lock 与 store 不一致（目录缺失/摘要不符）时立即失败，不回退 | 删掉版本目录后 `ct build --locked` RC≠0 且文案含 `is not installed` 或 `does not match` | S2 |
| SP-010 | 无 `ct.lock` 的工程退回 `vendor/` 并打警告；无 vendor 亦无 lock 时不新增报错 | 删除 lock 的旧工程 `ct build` 仍 RC=0（若原先可构建），stderr 含 `no ct.lock; reading vendor/` | S2 |
| SP-011 | 编译期零网络：`ct build` / `ct compile` 不发起任何网络调用 | `env -u HOME http_proxy=http://127.0.0.1:9 ct build …` RC=0 | 现状已成立，回归保持 |
| SP-012 | `import` 只写 `<name>::<Unit>`；发布方不得出现在 import 路径中 | 归消费者仓自查；本仓只保留语法口径，不设跨仓验收 | 包外 |
| SP-013 | 依赖图内包名唯一；同名（无论发布方）即硬错 | 两个同名 `dep` 的工程 `ct install` RC≠0 且含 `is required twice` | S2 |
| SP-014 | 裸名在索引中对应多个发布方时硬错 | 构造双发布方索引 → `ct get <name>` RC≠0 且含 `is ambiguous` | S1 |

### 覆盖与留痕

| ID | 要求（二值判据） | 验收命令 | 切片 |
| --- | --- | --- | --- |
| SP-015 | dev override 必须双留痕：lock 记 `dir` 行 + 构建 stderr 输出 `note:` | 本地目录依赖的工程 `ct build` stderr 含 `resolves to the local directory (dev override)`；lock 首字段为 `dir` | S2 |
| SP-016 | `ct verify --strict` 在 lock 含 `dir` 行或 vendor 回退时失败 | 同上工程 `ct verify --strict` RC≠0 | S3 |

### lock 与校验

| ID | 要求（二值判据） | 验收命令 | 切片 |
| --- | --- | --- | --- |
| SP-017 | v2 lock 首行为 `# ct-lock 2`；每行含发布方、版本、源类型、源定位、ns-root、`sha256:<64hex>` | `head -1 ct.lock` 等于 `# ct-lock 2`；`awk 'NR>1{print NF}' ct.lock` 全为 7 | S1 |
| SP-018 | v1 lock（无头）读取时告警且不按 v2 解释；`ct install` 输出含 `lock-format` 注释 | 旧工程 `ct install` stdout 含 `# lock-format: v1`，stderr 含 `ct.lock is v1` | **S0** |
| SP-019 | store 内摘要不符必须报错，不静默重装 | 篡改 store 文件后 `ct verify` RC≠0 且含 `does not match ct.lock` | S1/S3 |
| SP-020 | 同版本重复安装为 no-op（摘要相同）或报错（摘要不同），不得覆盖已有目录 | 连续两次 `ct get` 同版本：第二次不改变版本目录的 mtime/内容 | S1 |

### 包仓库约定（边界，不在本仓）

以下六条归各包仓执行与举证，**不属于 Phase 54 或任何 CT phase**；参数与逐仓动作见包外移交清单。

| ID | 要求 | 归属 |
| --- | --- | --- |
| SP-021 | 包根必须有可解析的 `ct.pkg`（`name`/`publisher`/`version`/`ns-root` 四键非空） | 各包仓 |
| SP-022 | `ns-root` 下每个可导入单元的命名空间与其相对路径一致（`::`→`/`），且首段唯一 | 各包仓 |
| SP-023 | `ns-root` 下至少一个 `.h.ct` / `.m.ct` 单元 | 各包仓 |
| SP-024 | 包内不得出现指向自身绝对路径的 `-I` | 各包仓 |
| SP-025 | tag `v<version>` 与 `ct.pkg` 的 `version` 一致，且 tag 为默认分支可达提交 | 各包仓 |
| SP-026 | 依赖一律写 `<publisher>/<name>@<range>`，禁止裸名与无版本依赖 | 各包仓 |

### 只读校验（本仓）

| ID | 要求（二值判据） | 验收命令 | 切片 |
| --- | --- | --- | --- |
| SP-027 | `ct pkg check` 只读：运行前后包目录内容摘要不变 | 运行前后 `find R -type f -exec sha256sum {} +` 结果一致 | **S0** |

### 兼容与文档

| ID | 要求（二值判据） | 验收命令 | 切片 |
| --- | --- | --- | --- |
| SP-028 | 兼容期内旧工程可继续构建；每个 vendor 回退包告警一次 | 旧工程 `ct build` RC=0 且 stderr 含 `is read from vendor/ (v1)` | S5 |
| SP-029 | `ct migrate` 后删除 `vendor/` 仍可构建 | `ct migrate && mv vendor /tmp/v && ct build` RC=0 | S3 |
| SP-030 | 公开文档不再把 `vendor/` 与「包根 = 单元根」写成现行契约 | `grep -rn "包根就是包根" docs/` 零命中；`grep -rn -- "-I vendor/" docs/ README*.md install.sh` 仅剩兼容期说明 | S6 |

## 3. 被取代的提案条款

| 提案位置 | 原文本 | 取代者 |
| --- | --- | --- |
| §3 表格 `publisher` 行 | 「本地开发可写 `publisher = local`」 | SP-002（必填真名） |
| §3 表格 `ns-root` 行 / §3 末尾 | 「`src` 或 `.`」「默认 `.`」 | SP-003（必填、无默认） |
| §4 末条 | 「不是同一包多版本同时进图」（表述模糊） | SP-005 / SP-006（磁盘可并存、构建只一个） |
| §5 末条 | 「`./ct.lock` 存在即读；不存在不报错」 | SP-008 / SP-009 / SP-010（默认读、`--locked`、vendor 回退） |
| §11 末段 | 「`vendor/` 仅在 lock v1 时被读」 | SP-010 / SP-028（无 lock 也回退并告警） |

## 4. 非目标

- 不做发布方推导、私库鉴权、镜像同步、包签名。
- 不做同一包多版本同图（C 无模块隔离）。
- 不改 `import` 语法（不带发布方是既定口径）。
- 不改 MVS 选版算法。
