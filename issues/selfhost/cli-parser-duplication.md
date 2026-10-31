# SH-24 · compile 与 build 两套 CLI 解析器并存，导致 `-I` 上限与文案分叉

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | Info |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 站点 | [driver.h.ct:81-160](../../selfhost/ct-ast/tool/driver/driver.h.ct#L81-L160)（compile 的 `run`）与 [Module.h.ct:574-720](../../selfhost/ct-ast/frontend/module/Module.h.ct#L574-L720)（build 的 `build_main`） |
| 状态 | 待决策 |

## 现象

ct-ast 有两个独立的参数解析器：

- compile：`tool/driver/driver.h.ct` 的 `run(int argc, char **argv)`；
- build：`frontend/module/Module.h.ct` 的 `build_main(int argc, char **argv)`。

两者对同一开关的处理并不一致：

| 开关 | compile | build |
| --- | --- | --- |
| `-I <dir>` | 接受后**直接忽略**（`driver.h.ct:144` 注释 `accepted for CLI parity; compile mode resolves no imports`），无上限 | 存入 `incdirs[16]`，第 17 个报 `ctc: too many -I roots`（[Module.h.ct:668](../../selfhost/ct-ast/frontend/module/Module.h.ct#L668)） |
| `--emit-map -` | 写 stdout | 也写 stdout（README 却写「仅 compile」，见 [DOC-23](../docs/doc23-emit-map-build-stdout.md)） |
| `--ns-root` | 不支持 | 支持 |
| 缺参 / 未知选项 / `--std` 非法 | 各自一份文案 | 各自一份文案 |

## 证据

```bash
$ grep -n '"-I"' selfhost/ct-ast/tool/driver/driver.h.ct selfhost/ct-ast/frontend/module/Module.h.ct
selfhost/ct-ast/tool/driver/driver.h.ct:139:            if (strcmp(argv[i], "-I") == 0) {
selfhost/ct-ast/frontend/module/Module.h.ct:662:            if (strcmp(argv[i], "-I") == 0) {
$ sed -n '139,146p' selfhost/ct-ast/tool/driver/driver.h.ct
# "-I" … i++;   /* accepted for CLI parity; compile mode resolves no imports */
```

行为差异见 [DOC-25](../docs/doc25-include-roots-asymmetry.md) 的探针（compile 30 个根 rc=0，build 第 17 个 rc=1）。

## 影响

- 用户可见语义按模式分叉，文档很难写对（DOC-25 已因此失真）；
- 错误文案与缺参断言需要在两处维护，[TEST-10](../testing/test10-build-cli-errors-untested.md) 只覆盖了
  compile 侧；
- 不是当前缺陷（两种行为都能工作），故定为 Info / 设计观察，而非 High。

## 修复建议

先明确产品口径：`-I` 在 compile 模式是否应当报错而非静默忽略？把两套解析器收敛到一个共享的参数表
（或至少共享 `-I` 的检查与文案）会同时消除 DOC-25 与 TEST-10 的分叉来源。注意 AGENTS §5「最小改动」
与冻结边界：若收敛涉及 `driver.h.ct` 与 `Module.h.ct` 的结构调整，应先与用户确认，不要顺手重构。

## 验证

决策落地后，两模式的 `-I` 探针结果一致；README 只需一条口径描述；九关全绿。

## 处理（2026-10-31）

不采纳重构：Info 级设计观察，两种行为都能工作；合并两套解析器要同时改 `driver.h.ct` 与 `Module.h.ct`，属于结构性改动，违背最小改动。`-I` 的差异已在 README 按模式写清（DOC-25）。
