# DOC-68 · VS Code 跳转索引不识别泛型模板：`T id<T>(T x)` 与 `id<int>(…)` 都无定义

| 项 | 值 |
| --- | --- |
| 严重度 | Medium（新语法可用但 `Ctrl+Click` / `F12` 静默无结果，可察觉的缺口） |
| 锚点 | `v0.26.3` / `02999c4`（HEAD = `main`）+ 本轮语法提交（`editors/vscode` 0.5.0） |
| 文件 | [extension.js](../../editors/vscode/extension.js#L81-L98)、[extension.js](../../editors/vscode/extension.js#L192-L198)、[extension.js](../../editors/vscode/extension.js#L373-L390) |
| 状态 | **open**（本轮只补高亮与语法断言，`extension.js` 未动） |

## 现象

Phase 26 的泛型函数/方法声明 `T id<T>(T x) { … }` 不进入跳转索引，因此：

- 声明本身不被登记（`matchDefinition` 的三条正则都要求名字后直接跟 `(`）；
- 调用点 `id<int>(42)` 的 `id` 虽然取到了词，但索引里没有同名 `function`/`method`，`F12` 静默返回空。

泛型 `struct Box<T> { … }` 不受影响：struct 规则是 `struct\s+([A-Za-z_]\w*)[^;{}]*\{`，名字后的
`<T>` 被 `[^;{}]*` 吃掉，`Box` 仍会登记。缺口只在函数/方法模板。

## 证据

把 `extension.js` 的三条定义正则原样取出，对三种声明跑一遍：

```console
$ node -e '… DEFINITION_RE / DEFINITION_EOL_RE / BARE_DEFINITION_RE …'
"T id<T>(T x)"   braced= false eol= false bare= false
"int f(void)"    braced= false eol= true  bare= false
"T id<T>(T x) {" braced= false eol= false bare= false
```

`int f(void)` 走 Allman 分支登记，泛型声明三条全不中。同一路径也被 `impl` 内方法与 trait 内
默认方法复用（[L199-L209](../../editors/vscode/extension.js#L199-L209)），所以三者一起缺。

## 判据

修复后应同时满足：

1. `T id<T>(T x) { … }`（K&R 与 Allman 两种花括号）在索引里是一条 `function`；
   `impl` 内的 `T get<T>(…) { … }` 是 `method`，trait 内的是 `traitMethod`。
2. `id<int>(42)` / `id<char *>(p)` 的 `id` 至少跳到**声明行**；不要求按类型实参实例化到不同的位置。
3. 负例不新增索引项：`if (a < b) f();`、`int m = a < b > c;`、`p->x < q` 不得被当成模板声明或方法。
4. 既有断言不回退：`int f(void)`、`impl` 方法、trait 方法、`map` binding 的名字与行号不变。

## 代价

- `DEFINITION_RE` / `DEFINITION_EOL_RE` 要在名字与 `(` 之间允许 `<…>`，但必须限定尖括号内容
  （标识符、`,`、空白、`*`），否则 C 的大小比较 `a < b > (c)` 会被误判成调用/定义。
  `BARE_DEFINITION_RE` 不应接受 `<`，它服务于 trait 内无返回类型的方法。
- 索引仍是**行级近似**：只登记声明行，不解析类型参数作用域。`T` 作返回类型不会参与接收者
  类型推断，`p.get<int>()` 的收窄仍按 `p` 的声明类型走——与现有“同名方法多候选”的取舍一致。
- 若要做到“`id<int>` 与 `id<char>` 分别定位、类型实参参与 `traitsForCType` / 接收者推断”，
  需要词法级模板实参解析和实例化表，超出无依赖 `extension.js` 的定位，不在本条范围。
- 验证成本：`extension.js` 目前没有自动化测试，只能靠手工打开 `.ct` 文件点一遍；若加断言，
  需要先把 `parseSource` 从 `extension.js` 拆成可加载的纯函数，属于一次结构性改动。

## 处置

本轮按用户要求不动 `extension.js`：泛型模板的高亮与语法门禁已在 0.5.0 落地，跳转缺口以本条
登记。修复时按上述判据 1–4 写回归，并明确“只到声明行、不区分实例化”的口径后再动正则。
