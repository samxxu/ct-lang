# LANG-15 · `Type::Member` 限定名取值不可表达（`FsErrCode::FS_ERR_OUT_OF_BOUNDS`）

| 项 | 值 |
| --- | --- |
| 模块 | lang（表达式里的限定名解析） |
| 类型 | **新特性**（不是缺陷；从未承诺过值位置的 `Type::Member`） |
| 严重度 | Medium |
| 优先级 | **P2** —— 挡住 ct-fsguard R-02 这类「错误码带类型前缀」的 API 形态；有绕法（裸名或 alias） |
| 状态 | verified |
| 处置证据 | **已修**（v0.59.0：`Type::Member` 同单元/跨单元可用；`test/ast/271`、`272`） |
| 锚点 | `v0.53.1`（`55d89e2b`）；实测 `ct-ast v0.53.1`（HEAD 重建） |
| 关联 | SH-18（**类型位置**的 `ns::Type`）；本条是**值位置**的 `Type::Member`，解析入口不同 |

## 现象

枚举成员用 `Type::Member` 取值时，被当成「命名空间里的变量」去查，报
`no variable of that name in that namespace`，并附带「qualified type names are not supported」。

## 最小复现

```sh
mkdir -p fs && cat > fs/fs.h.ct <<'EOF'
namespace fs;
pub enum FsErrCode { FS_ERR_NOT_FOUND = 2, FS_ERR_OUT_OF_BOUNDS = 7 }
EOF
cat > main.ct <<'EOF'
#include <stdio.h>
import fs::fs;
int main(void) {
    int e = FsErrCode::FS_ERR_OUT_OF_BOUNDS;
    printf("%d\n", e);
    return 0;
}
EOF
CT_STD_DIR=<repo>/lib/std ct build -I . main.ct -o prog
```

### 实际输出

```text
main.ct:3:57: error: no variable of that name in that namespace (qualified type names are not supported; use the bare name or an alias import)
rc=1
```

## 现状与绕法

- `FS_ERR_OUT_OF_BOUNDS` 裸名可用（枚举成员在当前作用域）；
- `import fs::fs as f;` 后仍不能写 `f::FsErrCode::FS_ERR_OUT_OF_BOUNDS`（没有值位置的多级限定）；
- 只能把常量再包一层 `pub const`，或改用裸名。

## 为什么是「新特性」而不是 bug

- 规范只写了类型位置的限定名限制（SH-18），没有承诺过 `Type::Member` 取值；
- 原 battle 第 2 条已定为 B（限定名取值），落点是 PH-57；
- 与 SH-18 的区别：SH-18 是 `parse_type` 拒绝 `ns::Type`；本条是表达式解析把 `Type` 当命名空间，
  两者共享 `::` 词法，但符号查找目标不同（类型表 vs 枚举成员表）。

## 落点（PH-57）

与 SH-18 同 phase：PH-57「限定名与 namespace 常量」。判据草案：

| ID | 断言 |
| --- | --- |
| E57-1 | `FsErrCode::FS_ERR_OUT_OF_BOUNDS` 求值为 7（同单元与跨单元两种） |
| E57-2 | 成员不存在时报「`FsErrCode` 没有成员 `X`」并列出候选，不退化成「命名空间变量」 |
| E57-3 | `ns::Type` 类型位置（SH-18）保持现有行为或一并放开，诊断区分类型/值位置 |
| E57-4 | 裸名与 `import ... as` 两种写法零回归 |
| E57-5 | 不与 C 的 `::` 扩展冲突：生成 C 里不得出现 `::` |

## 文件族

`frontend/parse/Expr.h.ct`（`::` 值路径）+ `frontend/sym`（枚举成员表）。与 TypeCheck/Expr 链同族，
**排在 patch 清完之后**（PH-57 在 PH-53 / PH-54 之后）。
