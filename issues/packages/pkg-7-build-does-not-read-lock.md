# PKG-7 · `ct build` 不读 `ct.lock`，删掉 lock 仍能构建

| 项 | 值 |
| --- | --- |
| 模块 | packages / build（依赖解析与构建的衔接） |
| 定性 | **需求缺口**（不是 bug：当前文档从未承诺 `ct build` 读 lock） |
| 严重度 | Medium |
| 锚点 | 工作树 `89b1124b`（`ct v0.53.0` 二进制实测） |
| 文件 | `selfhost/ct-ast/frontend/module/Module.h.ct`（无 `ct.lock` 引用）、`selfhost/ct-ast/tool/driver/Driver.h.ct`（同样无） |
| 状态 | **已修**（PH-54 S2：SP-008；`ct build` 默认读 `ct.lock` 并自动补 `-I`，显式 `-I` 优先） |

## 现象

依赖钉版信息只在 `ct install` 打印的命令里体现；`ct build` 自身不读 lock，也不自动补 `-I`。删掉 `ct.lock` 仍可构建（只要命令行给了 `-I`），因此「同一 lock 可复现」无法由构建工具保证。

## 最小复现

```sh
cd /tmp/ct-audit/proj3          # 无 ct.lock 的工程
ls ct.lock                      # ls: ct.lock: No such file or directory
ct build main.ct -o /tmp/p7; echo "rc=$?"
```

实际输出：

```text
'cc' -std=c99 -I '.ctbuild' '.ctbuild/main.c' '.ctbuild/Alpha.c' -o '/tmp/p7'
rc=0
```

## 期望行为

- `ct build` 默认读 `./ct.lock`，按 lock 行自动补 `-I`。
- `ct build --locked`：lock 与共享库不一致立即失败，不回退。
- 无 lock 的工程退回 `vendor/` 并告警（[SP-010](../../docs/planning/ct-pkg-shared-store-requirements.md)）。

## 交叉引用

- 提案 [§5](../../docs/proposals/ct-pkg-shared-store.md)、[§12 D5](../../docs/proposals/ct-pkg-shared-store.md)
- 需求 SP-008 / SP-009 / SP-010
- [PKG-6](pkg-6-install-does-not-validate-imports.md)（同一套 `-I` 计算应共用）

## 修复排期

S2（编译读 lock）。调用点与 `install()` 共用 ns-root → `-I` 的单一实现，禁止两份逻辑。
