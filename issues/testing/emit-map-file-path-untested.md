# TEST-6 · `--emit-map <file>` 的成功路径没有用例

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | **Medium** |
| 锚点 | commit `ec97f99`（2026-10-17） |
| 位置 | `test/modules/map*`、[driver.ct](../../selfhost/src/driver.ct#L411-L425) |
| 状态 | ✅ 已修复（2026-10-18；compile 与 build 两条写盘路径均有用例，`cannot write` 也已钉住） |

## 现象

6.1 文档化的主用法是 `--emit-map <file|->`，其中 **compile 模式写 stdout（`-`）** 与 **build 模式写文件** 是两条不同路径；现有用例只覆盖了前者和「build 下拒绝 `-`」。

## 证据

`grep -rn "emit-map" test/modules/*/*.args` 只有三处：

```
test/modules/map_noarg/compile.args:1:--emit-map
test/modules/map_stdout_build/build.args:1:--emit-map - test/modules/map/prog.ct
test/modules/map/compile.args:1:--emit-map - prog.ct -o prog.c
```

**没有** `--emit-map <file>` 在 build 模式下成功写盘的用例，也没有该路径失败（`cannot write`，`core.ct:4979/4984`）的负例。

## 影响

build 模式的 map 落盘（含「由最后一个单元落盘」的语义）是 6.1 的关键行为；目前只有实现、没有断言。

## 修复建议

新增 designed 用例 `map_file_build`：

- `build.args`：`--emit-map out.json <units>… -o <outdir>`；
- 断言 `out.json` 与 golden 逐字节一致（形状同 `test/modules/map/expected.stdout`）；
- 再补一条不可写路径的负例，钉住 `cannot write`。

## 验证

`bash selfhost/check-archive.sh` 的 designed 计数 +1/+2 且 0 regression。

## 处理（2026-10-18）

新增 `test/modules/map_file`（compile 模式 `--emit-map prog.map`），`check-archive.sh` 增加 `expected.map` 断言（比对编译输出目录中的 `*.map`）。`designed cases: 39 pass / 0 regression`。

未覆盖：build 模式的 map 落盘（其 `map_path` 相对 CWD，runner 需要把工作目录切到 outdir 才能断言，留作后续）。

## 处理（2026-10-18，第二轮）

`map_file_build` 补齐了 build 模式的写盘断言：

- `build.args`：`--emit-map out.map test/modules/map_file_build/prog.ct`；
- runner 侧新增一段：build 模式的 map 相对仓库根解析，跑完把 `out.map` **归位**到输出目录再比对，测试不会往仓库里写文件；
- `expected.map` 由真实 L2 输出生成，断言「由最后一个单元落盘」的完整 JSON。

另补 `map_unwritable`（compile 模式，`--emit-map nope/prog.map`）钉住 `cannot write 'nope/prog.map'`。

验证：`bash selfhost/check-archive.sh` → `designed cases: 43 pass, 0 new, 0 pending, 0 regression`；`bash selfhost/check-all.sh` 七道硬关卡全绿。
