# DOC-19 · 教程四处与实现不符：`delete` 的 `p = 0`、`ctc` 建议、数组字段、示例行号

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `dde0dda`（2026-10-21） |
| 文件 | [docs/tutorial.md:305](../../docs/tutorial.md#L305)（英文 [:705](../../docs/tutorial.md#L705)）、[:401](../../docs/tutorial.md#L401)、[:403](../../docs/tutorial.md#L403)、[:322](../../docs/tutorial.md#L322) 与 [:334](../../docs/tutorial.md#L334) |
| 状态 | ✅ 已修复（2026-10-21，`docs/tutorial.md` 中英各四处：delete 展开、ctc 建议、数组字段、泄漏行号；`leak.ct:20` 为实测值） |

## 现象

新增的 `docs/tutorial.md`（818 行）是中英双语、命令可粘贴的入门材料，但有四处与实测不符。

### 1. `delete` 的展开写多了一句

`tutorial.md:305`（英文 `:705`）注释：

```c
delete p;   /* -> if (p) { Box_Drop_drop(p); free(p); p = 0; } */
```

实测（`/tmp/rev22/tut/leak.c`）：

```c
if (p) { Box_Drop_drop(p); free(p); }
```

**没有** `p = 0`。教程让读者以为删除后指针会被置空（从而可以安全再判），实际是悬空指针。

### 2. 让用户「用 `ctc`」写 `switch`

`tutorial.md:401`：「要写这类代码，用 `ctc`（L0 种子）或 L2。」

但 `install.sh` 装出来的 `ctc` 是 `ct` 的软链（同一 ct-ast 二进制，实测 `ctc -> ct`），执行
`ctc sw.ct` 得到 `ctc: line 1: unexpected token (at '{')`。要得到 L0 行为必须**手工**
`gcc selfhost/l0/ctc.c -o ctc`；L2 更不是默认安装产物。

### 3. §11 第 7 条与同篇 §6 相反

`tutorial.md:403`：「**struct 类型的数组字段**等少数组合仍不支持」；同篇 `:236-237` 说 ct-ast 已支持
接口数组、接口数组字段。实测 ct-ast 对 `struct Duo { Num ab[2]; }` 可用（`test/acceptance` 的
`p18_struct_array_field` 已晋升基线）。该结论与 [DOC-18](language-spec-struct-array-field-stale.md)
同源，属同一事实的第三处站点。

### 4. 同一泄漏示例出现两个行号

`:322` 写 `leak.ct:20: warning: …`，`:334` 写 `leak.ct:9: warning: …`，指向同一个程序。实测输出为：

```text
leak.ct:9: warning: potential leak: 'leak' (Box*) allocated but never deleted
```

## 影响

教程是新用户第一入口（README 两处把它列为「从这里开始」）。第 1、2 条会导致直接可执行的知识错误，
第 3 条与规范互斥，第 4 条影响可信度。

## 修复建议

1. `:305` / `:705` 的注释改为 `if (p) { Box_Drop_drop(p); free(p); }`；若要讲「置空」，改成
   「编译器不置空，需要自己 `p = 0;`」。
2. `:401` 改为：「需要 `switch` / `do-while` 时，手工构建 L0 种子 `gcc selfhost/l0/ctc.c -o ctc` 并用
   该 `ctc` 编译；`install.sh` 装出的 `ctc` 是 ct-ast 的别名，同样不支持。」
3. `:403` 改为：「L0 / L2 仍不支持 struct 类型的数组字段；ct-ast 已支持（见 §6 与 language-spec §6）。」
   ——与 DOC-18 的订正口径保持一致。
4. `:322` 与 `:334` 统一为 `leak.ct:9:`（按实测），或让示例程序的 `return` 行位于第 20 行并重跑核实。

## 验证

- 逐条按修正后的文本在本地执行：`delete` 展开、`ctc` 行为、struct 数组字段、泄漏行号四处与实测一致。
- 文档改动不触发 golden 重生成：`bash selfhost/check-all.sh` 仍须八关全绿。
