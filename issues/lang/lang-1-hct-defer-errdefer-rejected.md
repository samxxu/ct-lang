# LANG-1 · `.h.ct` 单元里 `defer` / `errdefer` 被拒

| 项 | 值 |
| --- | --- |
| 模块 | lang（解析期位置检查） |
| 严重度 | **High** |
| 优先级 | **P1** —— 挡住所有「头文件里写函数体」的包（ct-sse 因此放弃 errdefer） |
| 状态 | open（本次修复） |
| 锚点 | `v0.53.1`（`c4727787`） |

## 精确触发条件

`.h.ct` 单元的函数体内出现 `defer { … }` 或 `errdefer { … }`。与 `pub`、跨单元/同单元无关：
任何形态都命中，因为看的是**文件后缀**。

## 最小复现

```sh
mkdir -p fx/lib && cd fx
cat > lib/lib.h.ct <<'EOF'
#include <stdio.h>
namespace lib;
pub int with_cleanup(int fail)
{
    defer { printf("defer "); }
    errdefer { printf("errdefer "); }
    if (fail) return err: 7;
    return 3;
}
EOF
cat > prog.ct <<'EOF'
#include <stdio.h>
import lib::lib;
int main(void) {
    printf("ok=%d ", lib::with_cleanup(0));
    printf("err=%d\n", lib::with_cleanup(1));
    return 0;
}
EOF
ct-ast build --emit-c prog.ct -o out
```

## 实际行为

```text
./lib/lib.h.ct:6:5: error: defer is not allowed in a .h.ct unit
./lib/lib.h.ct:7:1: error: errdefer is not allowed here
ctc: 2 error(s) generated
rc=1
```

- `.m.ct`：不是同一问题——映射单元根本不能定义函数，`defer` / `errdefer` 不可达
  （`error: a .m.ct unit cannot define a function`）。
- `.ct`：两者都正常。

## 期望行为

`.h.ct` 的函数体与 `.ct` 一致：`defer` / `errdefer` 按 LIFO 在四条出口执行；`.m.ct` 维持「不能定义函数」。
即**行为只取决于「有没有函数体」，不取决于单元后缀**。

## 用途与影响面

- 包的头文件里写 `pub` 函数体是既有能力（共享实现、避免 `.m.ct` 映射层）；
- ct-sse 因此放弃 `errdefer`，改成每个失败分支手写清理——重复代码、漏释放风险随失败点线性上升；
- `docs/design/phase46-52-plan.md` §11 #13 / #14 把这条记为「规范限制，不是 bug」，本次改为缺陷并修复。

## 定位

两处显式路径检查（不是遗漏的兜底，而是刻意加的后缀判断）：

- `errdefer`：[Stmt.h.ct:1878-1883](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1878-L1883)
- `defer`：[Stmt.h.ct:1924-1929](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1924-L1929)

## 修复方向

删掉这两处后缀检查，保留 `switch` 内禁止、`ndefer_blocks == 0`（函数体外）禁止；规范 §4.9 / §4.58 同步，
并补一条 `.h.ct` 的正例夹具。
