# SH-13 · `pub` 全局变量在 build 模式下被整个丢弃，连定义单元自身都无法编译

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | **High** |
| 锚点 | commit `2ead601`（v0.12.0，2026-10-22） |
| 文件 | [selfhost/ct-ast/backend/emit/Emitter.h.ct](../../selfhost/ct-ast/backend/emit/Emitter.h.ct)（`write_unit_c`、`write_unit_header`） |
| 状态 | 已修（Batch 2 / 2a.2，`836c2e2` + `329016d`；证据见文末「处理（2026-11-09 回填）」） |

## 现象

build 模式对 `pub` 全局变量**两头都不发射**：

- `.c` 侧跳过所有 `d == 1` 的 `N_STRUCT / N_TYPEDEF / N_GLOBAL`
  （`write_unit_c` 的 `d != 1` 条件）；
- `.h` 侧只收 `N_STRUCT / N_TYPEDEF`，**没有 `N_GLOBAL` 分支**。

结果是符号既不在头文件里，也不在实现文件里。引用它的函数直接编不过。

## 证据

单元 `count.ct`：

```ct
pub int g_counter = 5;

pub int bump(void) {
    g_counter = g_counter + 1;
    return g_counter;
}
```

`ct build count.ct -o out` 成功（`exit=0`），但产物是：

```c
/* out/count.h */
int bump(void);
```

```c
/* out/count.c */
int bump(void);
int bump(void) {
    g_counter = (g_counter + 1);
    return g_counter;
}
```

`cc -Wall -Wextra -std=c99 -c out/count.c`：

```
count.ct:3:5: error: use of undeclared identifier 'g_counter'
count.ct:3:18: error: use of undeclared identifier 'g_counter'
count.ct:4:12: error: use of undeclared identifier 'g_counter'
```

compile 模式（单文件）不受影响：该路径对 `N_GLOBAL` 不做 `d` 过滤。因此这是 build 模式独有的缺口。

## 影响

- 用户写的 `pub` 全局既不能自用也不能导出，且 ct-ast 不报错，C 编译器才暴露。
- 跨单元的 `map` 实例必须先能导出（Batch 2 / 2a.1 的 Q2 依赖本项），本项不修则「跨单元 OO」链路断在这里。
- 与 `pub` 的直觉语义（"对外可见"）不符：目前实际语义是"彻底消失"。

## 修复建议

1. `.c`：`write_unit_c` 的过滤条件改为只跳过 `N_STRUCT / N_TYPEDEF` 的 `d == 1`，
   `N_GLOBAL` 一律发射（非 static 定义）。
2. `.h`：`write_unit_header` 增加 `N_GLOBAL && d == 1` 分支，发射 `extern <type> <name>;`，
   **不携带初始化器**；数组保留维度（`text3`）。
3. 若同一全局同时写了初始化式，初始化式留在 `.c`，头里只有声明。

## 验证

- `count.h` 含 `extern int g_counter;`，`count.c` 含 `int g_counter = 5;`，两文件编译零告警。
- 消费单元 `import count;` 后能读写 `g_counter`。
- 新增 fixture `test/modules/pub_global/`，由 `check-ast.sh` 断言上述两条字符串并运行比对。
- `bash selfhost/check-all.sh` 全绿（现行口径 11 道门禁）。

## 处理（2026-11-09 回填）

已修复：`.c` 侧只对 `N_STRUCT / N_TYPEDEF` 过滤 `d == 1`，`N_GLOBAL` 一律发射；`.h` 侧新增
`N_GLOBAL && d == 1` 分支，发射不带初始化器的 `extern` 声明。

- 修复提交：`836c2e2`（`fix(codegen): export pub globals, dedupe imports, declare ignored impl parameters`）
  与 `329016d`（`feat(codegen): cross-unit OO, map bindings and function pointers`）。
- 验证证据：`test/modules/pub_global/` 存在，`check-ast.sh` 的 `pub_global` 断言
  `count.h` 含 `extern int g_counter;`、`count.c` 含定义；2026-11-09 在干净克隆（`6da3ce4`）上复跑
  `bash selfhost/check-all.sh`，`check-ast: 765 passed / 0 failed`，11 道门禁全绿。
