# SH-30 · `emit_unit` / `write_unit_header` 的失败路径漏 `fclose`，`build` 还留下半截 `.h`

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 发射器 / 构建驱动） |
| 严重度 | Low |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [backend/emit/Emitter.h.ct:2595-2661](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2595-L2661)（`emit_unit`）、[:2678-2727](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2678-L2727)（`write_unit_header`）、[frontend/module/Module.h.ct:936-946](../../selfhost/ct-ast/frontend/module/Module.h.ct#L936-L946) |
| 状态 | 已修（2026-10-31）：两个发射函数的正文拆到文件作用域静态 helper，失败路径对称 `fclose`；`.h` 失败时删除半截产物 |

## 现象

两个函数都在 `fopen` 之后把 `self->out` 指向新文件，随后每一处失败都是裸 `return -1`
（`emit_map_prologues` / `emit_struct_fwd` / `emit_trait_range` / `emit_type_decl` / `emit_proto` /
`emit_global_extern` / `emit_link_externs` / `emit_impls` / `emit_maps` …），**没有一处在返回前 `fclose`**。

`Module.build_main` 的处理是：

- `emit_unit` 失败：`remove(<base>.c)`，但不 `fclose`；
- `write_unit_header` 失败：**什么都不删**。

后果：`.c` 被 `unlink` 但缓冲区在进程退出时才 flush（写进已删除的 inode），
而 `.h` 会以**部分内容**留在输出目录里，看起来像真实产物。这与
[Driver.h.ct:259-263](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L259-L263) 明确写的
「the file was opened before emission, so a failure in the middle of it would leave a truncated `.c`
that looks like a real artefact」的契约不一致。

## 证据

读码确认（未构造触发）：`emit_unit` 的 2606、2622、2623、2624、2633、2638、2643、2650、2653、2655、2658
均为 `if (… != 0) return -1;`；`write_unit_header` 的 2705、2706、2707、2713、2716、2722 同理。
`Module.h.ct:936-946` 只 `remove` `.c`。

要构造触发需要「`.c` 已打开、发射中途失败」的输入（例如某个 `pub` 声明在 `emit_proto` 阶段失败），
本轮没有找到稳定的最小构造，因此只按代码路径立案。

## 建议

把两个函数收口成「`fclose` + 失败返回」的单一出口（例如用 `st` 变量 + `goto done`），
并让 `build_main` 在 `write_unit_header` 失败时 `remove(<base>.h)`，与 `.c` 的清理对称。
（每进程最多泄漏 1–2 个 fd，真正的危害是残留半截头文件。）
