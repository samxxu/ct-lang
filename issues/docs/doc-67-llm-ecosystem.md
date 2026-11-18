# DOC-67 · LLM 生态入口：std / ct-pkg / index

| 项 | 值 |
| --- | --- |
| 模块 | docs（llm-guide / std-catalog / ct-pkg / ct-pkg-index / tutorial / package-guide / glossary） |
| 定性 | 文档补充与口径统一；**不占新 phase** |
| 严重度 | High（LLM 只读本仓会把 std/包全部重造） |
| 优先级 | P0 |
| 状态 | **open** |
| 落点 | 挂 `v0-PH-67` R5「文档漂移审查」，与 DOC-66 同批；可提前做，不阻塞 ID 迁移 |
| 来源 | 用户 2026-11-18 指示：LLM 必须知道 CT 有生态，先复用，不要重写 std 和包 |

## 核心原则

> **LLM 不仅要懂 CT 语法，还要知道 CT 有生态：先查 std / hal / index，再决定是否实现；不要重写标准库，不要复制包源码。**

## 交付物

### P0-1 `docs/llm-guide.md`

固定决策顺序：

1. 语言/语法 → `language-spec`；
2. 容器/字符串/文件/UTF-8/arena/test → 先查 `std`；
3. 硬件 → 先查 `hal` / `hal-posix`；
4. 通用能力 → 先查 `ct-pkg/index`；
5. 都没有 → 才实现；可复用就发布成包，不 vendored。

硬规则：

- `Vec<T>` / `Map<K,V>` 是编译器内置，不要重写；
- `std::str` / `std::fs` / `std::utf8` / `std::vec` / `std::map` / `std::arena` / `std::test` 用 `ct get ct/std`，不要手写替代；
- 别人的包用 `ct get <pub>/<name>`，不要复制；
- 包格式用 `ct.pkg` + `ns-root` + publisher，不要自造。

### P0-2 `docs/std-catalog.md`

薄目录，不复制完整 API：

| 模块 | 用途 | 导入 |
| --- | --- | --- |
| 内置 | 泛型容器 | 免 import：`Vec<T>` / `Map<K,V>` |
| `std::str` | 字符串 | `import std::str::String` |
| `std::fs` | 文件 | `import std::fs` |
| `std::utf8` | UTF-8 | `import std::utf8` |
| `std::vec` | C 映射向量操作 | `import std::vec` |
| `std::map` | C 映射映射操作 | `import std::map` |
| `std::arena` | 区域分配 | `import std::arena` |
| `std::test` | 测试 | `import std::test` |

附：`ct get ct/std@...`、store 路径、完整 API 读安装包内 README。

### P0-3 `docs/ct-pkg.md`

四角色：

| 角色 | 归属 |
| --- | --- |
| 编译器 | ct-lang |
| 标准库 | `ct-pkg/std` |
| 平台包 | `ct-pkg/hal` / `hal-posix` |
| 索引/发布 | `ct-pkg/index` |

写清：CT 仓不内置 std；`ct get` 是消费入口；`package.sh` 是发布入口，不是 `ct` 内置；`ct pkg check` 是过渡，不是长期 API。

### P1 `docs/ct-pkg-index.md`

区分 current / target：

- 当前官方 index 五字段、无 publisher/签名；
- 六字段是目标/兼容形态；
- `CT_INDEX` / `--index` 显式，不自动联网；
- 发布走 `package.sh` / CI，带 token，不进 `ct`；
- pin/签名未落地前，不声称可信。

### P1 统一现有口径

- `tutorial.md` 的 std 段指向 `std-catalog`，不重复全文；
- `package-guide.md` 补 consumer / publisher / index 三分；
- `glossary.md` 五字段改“当前五字段；六字段目标/兼容”；
- `docs/README.md` 加 Ecosystem 入口，明确 `proposals/` 不是现状。

## 验收

| # | 判据 |
| --- | --- |
| A1 | 问“实现字符串 split” → 回答用 `std::str`，不是手写 |
| A2 | 问“实现 Vec/Map” → 回答用内置泛型，不是重写 |
| A3 | 问“加一个包” → 回答 `ct.pkg` + `ns-root` + publisher，不是复制源码 |
| A4 | 问“索引格式” → 区分当前五字段 / 目标六字段 |
| A5 | 文档中五/六字段不再互相矛盾；`proposals/` 标注非现状 |
| A6 | LLM 能从 `llm-guide` 走到 std/index，不先自己实现 |

## 不做什么

- 不新开 phase；不 bump 版本；
- 不复制 std 全量 API；
- 不改 ct-pkg/index 仓；
- 不把发布脚本写进 `ct`；
- 不把 `proposals/` 当 current。

## 落点

- **不占 phase**；挂 `v0-PH-67` R5，与 DOC-66 同批。
- 可先做 P0 三份短文档，不等 ID 迁移。
