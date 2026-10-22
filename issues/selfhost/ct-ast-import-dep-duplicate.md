# SH-17 · 同一单元被多次 import 时，生成物重复 `#include` 该单元的头文件

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | Low |
| 锚点 | commit `2ead601`（v0.12.0，2026-10-22） |
| 文件 | [selfhost/ct-ast/frontend/module/Module.h.ct](../../selfhost/ct-ast/frontend/module/Module.h.ct)、[selfhost/ct-ast/backend/emit/Emit.h.ct](../../selfhost/ct-ast/backend/emit/Emit.h.ct)（`write_unit_c` / `write_unit_header` 的 `dep` 循环） |
| 状态 | 待修（Batch 2 / 2c.2） |

## 现象

一个单元通过不同 import 形式多次指向同一目标单元时，`units[u].dep` 里会出现重复条目，
生成物按条目逐一发射 `#include`。

## 证据

`main.ct`：

```ct
import net::conn;
import net::conn::Conn as Conn;
import net::conn::Stream as Stream;
```

`ct build main.ct -o out` 生成的 `main.c` 开头：

```c
#include "main.h"
#include "conn.h"
#include "conn.h"
#include "conn.h"
```

三行 import 都解析到同一个单元 `net/conn.ct`，依赖表未去重。

## 影响

- 生成物冗余；头文件有 guard，所以不影响正确性，也不会触发告警。
- 属于"生成物整洁度"问题，但会让阅读产物的人误以为有三个依赖，也会在依赖较多时放大噪声。

## 修复建议

在把单元登记进 `dep` 时按目标单元去重（线性查重即可，`MAX_IMPORTS` 很小）。
`.c` 与 `.h` 两处发射循环不需要改。

## 验证

- 上面的最小复现：`main.c` 中 `#include "conn.h"` 只出现一次。
- 新增 `test/modules/xunit_box`（Batch 2 / 2a.1）时顺带断言该计数。
- `bash selfhost/check-all.sh` 九关全绿。
