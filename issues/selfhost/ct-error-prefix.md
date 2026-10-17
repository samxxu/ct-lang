# SH-3 · 以 `ct` 运行时，驱动错误仍打印 `ctc:` 前缀

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | **Low** |
| 锚点 | commit `ec97f99`（2026-10-17） |
| 位置 | [driver.ct](../../selfhost/src/driver.ct#L390-L445)（25 处）、[core.ct](../../selfhost/src/core.ct)（12 处） |
| 状态 | ✅ 已决策（2026-10-18，选 2：保持 `ctc:`） |

## 现象

Phase 7.1 让 `-v` 与 usage 按 `argv[0]` 输出 `ct` 或 `ctc`，但驱动层错误信息仍是硬编码的 `ctc:`：

```c
fprintf(stderr, "ctc: -o needs an argument\n");
fprintf(stderr, "ctc: cannot open '%s'\n", path);
```

因此：

```console
$ ct /nonexistent.ct
ctc: cannot open '/nonexistent.ct'
$ ct -v
ct v0.7.0
```

## 证据

`grep -c "ctc:" selfhost/src/driver.ct selfhost/src/core.ct` → `25` / `12`。  
[driver.ct](../../selfhost/src/driver.ct#L191-L195) 的注释说明「其余名字保持 ctc 身份，使既有断言不动」，但未说明**诊断前缀**是否也应随身份变化。

## 影响

单入口 `ct` 的用户看到 `ctc:` 会困惑；与同一二进制 `-v` 的身份不一致。不影响正确性，也不影响现有测试（它们调用的是 `ctc` 身份）。

## 修复建议

二选一，并把选择写进 roadmap / AGENTS：

1. **随身份变化**：把 37 处前缀改为 `%s:` + `g_ct_prog`（注意 `core.ct` 的 `die` 已有 `文件:行:列:` 格式，需区分 CLI 前缀与语法诊断两类）；
2. **保持 `ctc:`**：在 README / roadmap 明确「诊断前缀保持 `ctc`，以稳定既有断言与日志约定」，并说明这是兼容性选择。

## 验证

若选 1：`ct /nonexistent` 输出 `ct: cannot open …`，`ctc /nonexistent` 仍输出 `ctc: cannot open …`；全部关卡保持绿色。  
若选 2：文档中出现该约定，且无代码改动。

## 处理（2026-10-18）

选 2：诊断前缀保持 `ctc:`。README 的退出码段（中英）与 roadmap 的 Phase 7 段记录了该约定及理由（`core.ct` 跨单元取身份需新增 `pub` 包装器，`MAX_FUNCS` 余量近乎为零；保持前缀也避免移动既有日志与断言）。无代码改动。
