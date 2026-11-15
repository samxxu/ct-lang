# SH-79 · `--emit-map` 两个 facet：`--lib` 不落文件、build 的 `file` 指向内置层

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（build 驱动 / map 序列化） |
| 严重度 | **High**（多单元工程拿不到自己的模型图；`--lib` 静默丢产物） |
| 优先级 | **P2** —— 不挡编译，但让「构建产物可审计」的承诺落空 |
| 状态 | open |
| 锚点 | `v0.53.1`（`a8f9a113`）；实测 `ct-ast v0.53.1`（HEAD 重建） |
| 类型 | **实现缺陷**（usage 宣称的开关不生效 / 生效到错的对象） |

## 现象（两个 facet）

1. `ct build --lib --emit-map out.json`：rc=0，但 `out.json` 不存在；
2. `ct build --emit-map nb.json main.ct`：文件写了，但顶层 `file` 与所有 `structs[].file`
   都是 **`lib/std/Vec.h.ct`**，输入单元的模型是空的。

## 最小复现

```sh
mkdir -p lib && cat > lib/lib.h.ct <<'EOF'
namespace lib;
pub struct Box { int n; }
pub int box_get(struct Box *b) { return b->n; }
EOF
cat > main.ct <<'EOF'
#include <stdio.h>
import lib::lib;
int main(void) { struct Box b; b.n = 3; return lib::box_get(&b); }
EOF

# facet 1
CT_STD_DIR=<repo>/lib/std ct build --lib --emit-map map.json -I . lib/lib.h.ct -o out
ls -l map.json

# facet 2
CT_STD_DIR=<repo>/lib/std ct build --emit-map nb.json -I . main.ct -o prog
grep -o '"file":"[^"]*"' nb.json | head
```

### 实际输出

```text
# facet 1
rc=0
ls: map.json: No such file or directory

# facet 2
rc=0
"file":"/tmp/cthead/lib/std/Vec.h.ct"
"file":"/tmp/cthead/lib/std/Vec.h.ct"
...
```

`nb.json` 的 `structs` 只列 `ct_buf` / `Vec` / `MapEntry` / `Map`，`functions` / `impls` / `calls` 全空，
输入单元的 `Box` / `main` 不在里面。

## 根因

- facet 1：`--lib` 分支在 [Module.h.ct:1573-1610](../../selfhost/ct-ast/frontend/module/Module.h.ct#L1573-L1610)
  提前进入归档流程，未走到 1819 行的 `write_map`；
- facet 2：[Module.h.ct:1819](../../selfhost/ct-ast/frontend/module/Module.h.ct#L1819)
  固定写 `self->units[0].prog, 0`。`units[0]` 是内置层（`Vec.h.ct` 先加载），输入单元排在后面，
  于是模型图永远只导出内置层。

## 定性

**bug（A）**：同一份 usage 在 build 行列出 `[--emit-map <file|->]`
（[Driver.h.ct:242](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L242)），但 build 路径要么不写、
要么写错对象，且都不报错。

## 修复落点

| 文件 | 改什么 |
| --- | --- |
| `frontend/module/Module.h.ct` | `write_map` 按**非内置输入单元**生成：一个 map 汇总所有输入单元，或按根单元逐个写；`file` 一律指向输入单元路径 |
| `frontend/module/Module.h.ct` | `--lib` 收口也调用 `write_map`（放在归档成功之后、返回之前） |
| `tool/driver/Driver.h.ct` | 只做参数透传；compile 路径保持不变 |
| `backend/emit/Emitter.h.ct` | `ct_emit_map` 去掉「单 prog 单 file」假设；每个声明带自己的 `file` |

## 0.53.8 验收口径

| ID | 断言 |
| --- | --- |
| R1 | compile：`ct one.ct --emit-map m.json -o one.c` 落文件且可 `json.load` |
| R2 | build（非 `--lib`）：`ct build --emit-map m.json -I . main.ct -o prog` 落文件 |
| R3 | build `--lib`：`ct build --lib --emit-map m.json -I . lib/lib.h.ct -o out` 落文件 |
| R4 | **`file` 字段必须是输入单元**：`m.json` 里每个 `file` ∈ 输入单元集合；不得出现 `lib/std/*`；输入的 `Box` / `main` 必须在 `structs` / `functions` 里 |
| R5 | 不带 `--emit-map` 时零产物；同一输入重复运行 JSON 逐字节相同 |

## 与 LANG-10 / PH-58 的关系

- **不合并**：LANG-10 / PH-58 是**诊断**通道（错误/警告的 JSON 与字段位置）；SH-79 是**代码模型**
  导出（struct/函数/调用图）。消费者与稳定性要求不同。
- 共同点只有「机器可读输出的信封与版本化」；这条统一口径放到模型导出提案
  （[ct-model-export-proposal](../../docs/proposals/ct-model-export-proposal.md) §5），
  不在本 patch 里做。

## 文件族

`Driver` / `Module` / `Emitter` 与 LANG-11、SH-76 同族，**必须串行发版**；根因不同，**不合并**。
`Emitter` 的改动还会与 LANG-9 的 header/ABI 窗口冲突，排期时把 0.53.8 放在 LANG-9 之前。
