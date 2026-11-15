# PKG-6 · `ct install` 不校验 import 解析，解析不到仍返回 0

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct install` 校验面） |
| 定性 | **诊断缺陷**（校验不完整，退出码语义失真） |
| 严重度 | Medium |
| 锚点 | 工作树 `89b1124b`（`ct v0.53.0` 二进制实测） |
| 文件 | [Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct)（`install()` 只校验摘要与 dep 覆盖） |
| 状态 | **open**；随 S2 一起修（[Phase 54 卡 §3](../../docs/design/phase54.md)） |

## 现象

`ct install` 的成功语义是「打印一条可直接执行的 `ct build` 命令」。但它不尝试解析包内单元，包布局与 `-I` 不匹配时仍打印命令并返回 0，消费者照抄才失败。

## 最小复现

```sh
# 用一个单元在 src/<ns>/ 的本地包（v0.53.x 现场）
mkdir -p /tmp/p6/proj && cd /tmp/p6/proj
printf 'name = usefs\nversion = 0.1.0\n' >ct.pkg
printf 'import fsguard::FsGuard;\nint main(void){ return 0; }\n' >main.ct
ct get ../pkg-fsguard && ct install; echo "install rc=$?"
ct build -I vendor/fsguard main.ct -o build; echo "build rc=$?"
```

实际输出：

```text
ct build -I vendor/fsguard main.ct -o build
install rc=0
ctc: cannot resolve import 'fsguard/FsGuard'
build rc=1
```

## 期望行为

- `ct install` 用 lock 里的 ns-root 离线试解析每个 `dep` 的公开单元；解析不到即失败：
  `ctc: '<publisher>/<name>@<version>' cannot resolve import '<rel>'`。
- 目标形态见 [提案 §5](../../docs/proposals/ct-pkg-shared-store.md)；包仓侧的 `ns-root` 声明归各包仓，不属于本仓任何 phase。

## 交叉引用

- [PKG-2](pkg-2-ct-install-package-root-import.md)（布局根因，本条的消费端表现）
- 提案 [§5](../../docs/proposals/ct-pkg-shared-store.md)（`-I` 由 ns-root 决定）
- 需求 SP-022

## 修复排期

S2（编译读 lock）：校验逻辑与 `ct build` 共用同一套 `-I` 计算，避免两处漂移。
