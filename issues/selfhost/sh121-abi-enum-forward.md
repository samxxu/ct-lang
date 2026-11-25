# SH-121 · `.abi.h` 枚举形参缺 `enum X;` 前置声明（REQ-ABI-3）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`--lib` 导出面 / `.abi.h`） |
| 定性 | 缺陷（消费方构建失败，不是新特性） |
| 严重度 | **P2** |
| 锚点 | `682faf2f`（2026-11-25） |
| 依据 | [REQ-ABI-3](../../docs/planning/requirements-pool.md) |
| 文件 | `selfhost/ct-ast/backend/emit/Emitter.h.ct`（导出面前置声明循环）；`test/ast/abi_enum_union.sh` |
| 状态 | verified |
| 负责人 | DEV |
| 处置证据 | **fixed（`682faf2f`）**：`struct` / `union` / `enum` 三类形参都写入前置声明；`test/ast/abi_enum_union.sh` 断言 `enum E;` 并用 `-Werror=visibility` 编译消费方 |

## 1 现象

`ct build --lib` 生成 `.abi.h` 时，导出签名里的枚举形参没有前置声明：

```c
pub int take_enum(enum E e);
```

生成的 ABI 头里只有函数声明，没有 `enum E;`。消费方只包含 `.abi.h` 时，clang 给
`-Wvisibility`，gcc / `-Werror` 下构建失败；枚举按值传参需要完整类型。

## 2 根因

前置声明收集循环只匹配 `struct ` 前缀，`enum` 形参被直接跳过
（修复前 `Emitter.h.ct` 的 `strncmp(tp, "struct ", 7) != 0` 分支）。同一处也漏了 `union`，
见 [SH-122](sh122-abi-union-forward.md)。

## 3 修复

`682faf2f` 把前缀判断扩成三类，并在去尾（星号/空格）后写入 `fwd[]`：

```c
if (strncmp(tp, "struct ", 7) == 0)      snprintf(nm, sizeof nm, "struct %s", tp + 7);
else if (strncmp(tp, "union ", 6) == 0)  snprintf(nm, sizeof nm, "union %s", tp + 6);
else if (strncmp(tp, "enum ", 5) == 0)   snprintf(nm, sizeof nm, "enum %s", tp + 5);
else continue;
```

输出行由固定 `struct %s;` 改为按记录原样输出 `%s;`。

## 4 证据

- 夹具：`test/ast/abi_enum_union.sh`（与 SH-122 共用）
  - `.abi.h` 含 `enum E;`；
  - 消费方只带 `types.h` + `.abi.h`，以 `cc -std=c99 -Werror=visibility` 编译并运行；
- 提交：`682faf2f`；seed 同批重生成（`bootstrap/MANIFEST.sha256` 更新）。

## 5 回归与回滚

- 回归：`test/ast/abi_enum_union.sh` 纳入 check-ast；`p88` 度量随 ABI 修复更新（`c360c66d`）。
- 回滚：单提交 revert 后重生成 seed；不影响非 `--lib` 路径。

## 6 关联

- [REQ-ABI-3](../../docs/planning/requirements-pool.md)、[REQ-ABI-4](../../docs/planning/requirements-pool.md)
- [SH-122](sh122-abi-union-forward.md)（同族 `union *`）
- [`v1-PH-2` §2 S0](../../docs/phases/v1-PH-2/card.md)
