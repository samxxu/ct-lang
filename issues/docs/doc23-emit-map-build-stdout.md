# DOC-23 · README 把 `build --emit-map -` 写成不可用，实测可用

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **High** |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [README.md](../../README.md#L41)（中文）、[README.md](../../README.md#L122)（英文） |
| 状态 | 已修（`94815d7`，2026-11-09 回填） |

## 现象

CLI 表把 `--emit-map` 的 stdout 形态限定为 compile：

```text
中文：`-` 表示 stdout，仅 compile 可用，`build` 须写文件
英文：`-` means stdout, compile mode only — `build` must write a file
```

`build` 模式的解析器并不禁止 `-`，实测把 JSON 写到 stdout。

## 证据（探针）

```bash
$ mkdir -p out
$ /tmp/a/ct-ast build h.ct -o out --emit-map -
{"compiler":"ct v0.13.0", ... }        # stdout 输出完整 JSON
$ echo $?
0
```

`h.ct` 为单单元 `.ct` 输入，build 正常产出 `out/h.c`；`--emit-map -` 与文件形态同样生效。
实现位置：[Module.h.ct](../../selfhost/ct-ast/frontend/module/Module.h.ct) 的 `build_main` 解析分支与
`write_map(dest, …)`（`dest` 为 `-` 时写 stdout）。

## 影响

面向用户的唯一 CLI 参考写错了一条可用能力。按文档操作的 CI 脚本会退化为「先写临时文件再拷贝」，
而实现本身不需要；更严重的是文档与测试口径不一致——`check-ast.sh` 的元数据层已经断言
`--emit-map` 的 stdout 形态（见 [check-ast.sh](../../selfhost/check-ast.sh) 的 metadata 段），
说明该能力是受支持的一等行为。

## 修复建议

两处（中英各一）把 `--emit-map -` 的适用范围改为「compile 与 build 均可用」；若确实希望 build
限制为文件，则应改实现与对应断言，二者择一，不要继续让文档与门禁互相矛盾。

## 验证

修复后重跑探针，stdout JSON 与 `--emit-map <file>` 的内容一致；`bash selfhost/check-all.sh` 九关全绿。

## 处理（2026-10-31）

已修复：README 中英 CLI 表改为「`compile` 与 `build` 都接受 `--emit-map -`」。

- 修复提交：`94815d7`（`docs(spec): dispose of the 2026-10-31 audit findings`）。
- 验证证据：README 中文 CLI 表（`README.md:41`）与英文表（`README.md:122`）均已改为两模式通用；
  2026-11-09 在干净克隆上复跑 `bash selfhost/check-all.sh`，11 道门禁全绿
  （`check-docs: OK (825 relative links in 171 files, v0.24.0, 11 hard gates …)`）。
