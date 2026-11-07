# TEST-9 · 绝大多数容量上限可达但无用例（仅 MAX_MAPS / MAX_ERRORS 有夹具）

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | Medium |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [selfhost/ct-ast/frontend/sym/Symbols.h.ct](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct)、[selfhost/check-ast.sh:829](../../selfhost/check-ast.sh#L829)、[:1771](../../selfhost/check-ast.sh#L1771) |
| 状态 | 已修（2026-11-07，按「显式约定」处置）：覆盖范围与不补理由写进 `docs/language-spec.md` §7 与 `Symbols.h.ct` 的 `MAX_*` 定义处 |

## 现象

ct-ast 的容量上限集中在 `Symbols.h.ct`：
`MAX_TEXT 160` / `MAX_PARAMS 16` / `MAX_FUNCS 256` / `MAX_VARS 4096` / `MAX_SCOPE 256` /
`MAX_TYPES 256` / `MAX_METHODS 64` / `MAX_TRAITS 64` / `MAX_STRUCTS 128` / `MAX_FIELDS 64`。
规格要求越界「一律报错、不静默截断」（`docs/language-spec.md:59`），但绝大多数上限**没有任何夹具**。

探针实测可达（均非零退出）且报错文本已知：

```text
too many variables / types / structs / traits / functions / parameters /
nested scopes / calls / labels in one function / gotos in one function /
trait methods / warnings / map bindings / map parameters / used traits /
imports / exported type names
```

另有驱动级上限：`too many inputs`、`too many -I roots`（见
[DOC-25](../docs/doc25-include-roots-asymmetry.md)）与各类路径长度上限。

## 证据

```bash
$ grep -n "MAX_MAPS cap\|MAX_ERRORS cap" selfhost/check-ast.sh
830:    ok "map (MAX_MAPS cap)"
# MAX_ERRORS 在 10.4 段
```

`check-ast.sh` 里只有这两条上限断言（`MAX_MAPS` = 64、`MAX_ERRORS`）；其余 `MAX_*` 均无。

## 影响

上限是最容易出现「静默截断 / 越界写」的区域，而 `ct_sem_error` 的错误分支只有被实际触达才可验证。
没有夹具时，常量调整（例如把 `MAX_FUNCS` 抬高）可能连带改变错误文案或让守卫失效而无人察觉；
`MAX_TEXT 160` 与长标识符截断问题（[SH-23](../selfhost/ct-ast-identifier-truncation.md)）正是这一空白
区的实例。

## 修复建议

每个 `MAX_*` 至少一条负例（`test/ast/errors/` 或 `check-ast.sh` 的生成式断言），文本由实测输出生成：

- 变量 / 类型 / struct / trait / 函数 / 参数 / 嵌套作用域 / 调用 / label / goto：各一条；
- 驱动级：`too many inputs`、`too many -I roots`、`output path is too long` 等，归入
  [TEST-10](test10-build-cli-errors-untested.md)；
- 生成式夹具（脚本循环生成 N 个声明）比手工 256 行更可维护，但必须固定种子与计数。

## 验证

每条新夹具在旧实现上非零退出、在新实现上仍非零退出且文本一致；`bash selfhost/check-all.sh` 九关全绿。

## 处理（2026-10-31）

部分修复：新增 5 条生成式上限用例（params / methods / funcs / scopes / vars，覆盖 17 / 65 / 257 / 257 / 4097 个元素）。其余 `MAX_*` 按需再补——每条都要一份生成器与一个文案契约，收益递减。

## 处理（2026-11-07，约定化）

不追求「每个 `MAX_*` 一条用例」，而是把边界写成显式约定：

- 契约测试**只覆盖** `MAX_PARAMS` / `MAX_METHODS` / `MAX_FUNCS` / `MAX_SCOPE` / `MAX_VARS` /
  `MAX_FIELDS`（SH-29）/ `MAX_STRUCTS`（SH-53），外加 `check-ast.sh` 的 `MAX_MAPS` 与 `MAX_ERRORS` 两条；
- 其余上限可达但**故意不补夹具**，理由（每条约需一份生成器 + 一份文案契约，收益已递减）写在
  `docs/language-spec.md` §7（中英各一份）与 `selfhost/ct-ast/frontend/sym/Symbols.h.ct` 的
  `MAX_*` 定义块上方；
- 新增上限或调整现有上限时，才顺带把该条文案钉成断言，不再批量补历史夹具。

`tests/` 侧不新增用例；本条到此收口。
