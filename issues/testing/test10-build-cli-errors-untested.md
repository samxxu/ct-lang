# TEST-10 · build 模式的 CLI 错误分支几乎未测

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | Medium |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [selfhost/check-ast.sh:1518-1600](../../selfhost/check-ast.sh#L1518-L1600)、[:1592](../../selfhost/check-ast.sh#L1592) |
| 状态 | 待修 |

## 现象

CLI 错误分支集中在 `check-ast.sh` 的末段，但几乎全部以 **compile 模式**触发；`build` 模式只有
一条断言：

```sh
elif grep -q "build needs -o" "$work/cli-bo.err"; then
```

`build` 下的以下分支没有任何断言：

- `-o` / `-I` / `--ns-root` 缺参；
- 未知选项、`--std` 非法值；
- 无输入（空参数表）；
- `too many -I roots`（第 17 个根，见 [DOC-25](../docs/doc25-include-roots-asymmetry.md)）；
- `too many inputs`；
- 写失败（`cannot write the output file` / `header` / `map`）；
- 输出路径 / map 路径 / 输出目录过长；
- `--emit-map` 写文件成功路径（见 [TEST-6](emit-map-file-path-untested.md) 的部分覆盖）。

## 证据

```bash
$ sed -n '1518,1600p' selfhost/check-ast.sh | grep -n "build" 
# 只有 "build needs -o" 一条
```

compile 与 build 是两套独立的参数解析器（[SH-24](../selfhost/cli-parser-duplication.md)），
compile 的断言不能代表 build 的行为。

## 影响

build 是安装后的主要使用形态（`ct build <in.ct>… -o <dir>`），其参数错误若退化为崩溃、静默成功或
错误前缀不符（`file:line:col:` vs `ctc:`），当前门禁都不会发现。尤其是 `too many -I roots`：
一条已经在实现中存在的守卫，没有任何测试证明它仍然可达。

## 修复建议

在 `check-ast.sh` 的 CLI 段为 build 补齐上述分支，断言「非零退出 + `ctc:` 前缀 + 具体文本」；
文本由真实二进制输出生成。注意把「写失败」类用例放在临时目录，避免污染仓库（生成物清理见本轮
审计的工作树检查）。

## 验证

每条新断言用 `/tmp` 中的 ct-ast 实测输出核对；`bash selfhost/check-all.sh` 九关全绿，工作树无新增未跟踪文件。

## 处理（2026-10-31）

已修复：build 模式补 8 条断言（`-o` / `-I` 缺参、`--std` 非法、未知选项、无输入、17 个 `-I`、65 个输入）。
