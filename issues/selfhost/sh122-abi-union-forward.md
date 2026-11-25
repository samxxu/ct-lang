# SH-122 · `.abi.h` `union *` 形参缺 `union X;` 前置声明（REQ-ABI-4）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`--lib` 导出面 / `.abi.h`） |
| 定性 | 缺陷（标签不一致，调用点出现不兼容指针诊断） |
| 严重度 | **P3** |
| 锚点 | `682faf2f`（2026-11-25） |
| 依据 | [REQ-ABI-4](../../docs/planning/requirements-pool.md) |
| 文件 | `selfhost/ct-ast/backend/emit/Emitter.h.ct`（导出面前置声明循环）；`test/ast/abi_enum_union.sh` |
| 状态 | verified |
| 负责人 | DEV |
| 处置证据 | **fixed（`682faf2f`）**：`union` 形参写入 `union U;` 前置声明；`test/ast/abi_enum_union.sh` 断言并用 `-Werror=visibility` 编译消费方 |

## 1 现象

导出签名出现 `union *` 形参时，`.abi.h` 没有 `union X;`：

```c
pub int take_union(union U *u);
```

消费方包含 `.abi.h` 后，参数表里的 `union U` 与实际定义不是同一标签；
clang 给 `-Wvisibility`，调用点出现不兼容指针诊断。

## 2 根因

同一处前置声明循环只识别 `struct ` 前缀，`union` 被跳过
（与 [SH-121](sh121-abi-enum-forward.md) 同根）。

## 3 修复

`682faf2f` 在 `struct` / `enum` 之外补 `union ` 分支，并把输出改为按记录原样输出
`%s;`（记录里已带 `union ` 前缀）。

## 4 证据

- 夹具：`test/ast/abi_enum_union.sh`（与 SH-121 共用）
  - `.abi.h` 含 `union U;`；
  - 消费方 `-Werror=visibility` 编译并运行 `take_union(&u) == 3`；
- 提交：`682faf2f`；seed 同批重生成。

## 5 回归与回滚

- 回归：同一夹具覆盖；`check-ast` 全绿。
- 回滚：单提交 revert 后重生成 seed；不影响非 `--lib` 路径。

## 6 关联

- [REQ-ABI-4](../../docs/planning/requirements-pool.md)、[REQ-ABI-3](../../docs/planning/requirements-pool.md)
- [SH-121](sh121-abi-enum-forward.md)（同族枚举形参）
- [`v1-PH-2` §2 S0](../../docs/phases/v1-PH-2/card.md)
