# PKG-13 · `ct install` 打印的 `-I` 与 dev override 冲突

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct install` 输出指引 / import 根去重） |
| 定性 | 实现缺陷：工具给出的 `-I` 指引本身导致构建失败 |
| 严重度 | Medium |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 实测版本 | v0.60.0 |

## 现象

`dir` 源安装后，`ct install` 打印的 `-I` 直接照抄进 `ct build`，会与 dev override 的根重复：

```console
$ ct install
...
-I /path/to/vendor/http
$ ct build ... -I /path/to/vendor/http
error: unit 'http/http' exists in two import roots
```

## 最小复现

```console
$ mkdir -p /tmp/inst13 && cd /tmp/inst13
$ ct install            # 使用 dir 源，记录打印的 -I
$ ct build <入口> -I <上一步打印的路径>
error: unit 'http/http' exists in two import roots
$ echo $?
1
```

## 期望行为

- `ct install` 打印的 `-I` 必须可直接使用；
- 若 dev override 已自动加入同一个根，输出应去重，或只打印未覆盖的根；
- 冲突时诊断列出两个根的来源（lock / override / 显式 `-I`），而不是只报「two import roots」。

## 影响

安装指引与构建规则自相矛盾；用户按提示操作必然失败，只能靠猜去掉某个 `-I`。

## 关联

- [PKG-8](pkg-8-local-override-no-trace.md)：dev override 的留痕与优先级。
- [PKG-2](pkg-2-ct-install-package-root-import.md)：`ct install` 输出的 `-I` 形态。
