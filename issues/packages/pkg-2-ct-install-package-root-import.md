# PKG-2 · `ct install` 只打印 `-I vendor/<包名>`，包内单元不在包根时消费端无法 import

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct install` / 包布局） |
| 严重度 | **Medium** |
| 锚点 | 本仓库 `eaaeae75`（`v0.53.0` 之后、`v0.53.1` 之前） |
| 文件 | [Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct)（打印入口）；[package-guide.md](../../docs/package-guide.md)（`ct install` 的契约描述） |
| 状态 | **已解决**（v0.55.0 起 `ns-root` 决定 `-I`；v0.58.0 起 `ct build` 默认读 lock 自动补 `-I`） |

## 现象

`ct install` 曾为每个 vendored 包打印一条固定格式的 include 根：

```c
printf("%s build", prog);
for (i = 0; i < nlock; i++) printf(" -I vendor/%s", lname[i]);
```

它**不读包内布局**，只把包根当 include 根。于是只要包的单元不在包根（典型形态是
`src/<namespace>/`），消费端照抄这条打印出来的命令就会解析不到 import。

## 解决

- `ns-root` 是 `ct.pkg` 必填键；`ct install` 打印
  `-I $CT_HOME/pkg/<publisher>/<name>/<version>/<ns-root>`。
- `ct build` 默认读 `./ct.lock` 并自动补同样的 `-I`，消费者不再手算 include 根。
- 判据见[需求](../planning/ct-pkg-shared-store-requirements.md) SP-003/004/008；包仓侧的
  `ns-root` 声明归各包仓，不属于本仓任何 phase。

## 历史绕法（不再推荐）

v0.53.x 期间存在两种临时做法：把命名空间目录前移到包根，或让消费者自己算
`-I vendor/<包名>/src`。前者改变包自身布局，后者让 `ct install` 的输出不再是可直接执行的契约；
`ns-root` 落地后两种做法都不再需要。逐仓的处置记录随包外移交清单分发。
