# SH-83 · 包发布后的构建指引：`ct install` 打印的 `-I` 与 dev override 冲突

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct install` 输出指引 / 包 lock / import 根去重） |
| 类型 | 能力缺口（发布产物给出的构建指引不可直接使用） |
| 严重度 | Medium |
| 状态 | 受理（P1，v0.61.x patch） |
| 锚点 | v0.60.0（`14a99b27`） |
| 承诺出处 | [需求 SP-008](../../docs/planning/ct-pkg-shared-store-requirements.md)、[需求 SP-015](../../docs/planning/ct-pkg-shared-store-requirements.md) |

## CT 承诺了什么

- SP-008：`ct build` 默认读 `./ct.lock` 并自动补 `-I`，用户不必手传 `-I`。
- SP-015：dev override 必须双留痕——lock 记 `dir` 行，构建 stderr 输出 `note:`。

两条合起来的含义是：包发布产物安装后输出的 `-I` 与构建自动补的根应当一致，不应互相打架。

## 实测差距

`dir` 源安装后，`ct install` 打印的 `-I` 直接照抄进 `ct build`，会与 dev override 的根重复。
以下 `pkg-a` 为占位名：

```console
$ ct install
...
-I /path/to/vendor/pkg-a
$ ct build ... -I /path/to/vendor/pkg-a
error: unit 'pkg-a/pkg-a' exists in two import roots
```

## 最小复现

```console
$ mkdir -p /tmp/sh83 && cd /tmp/sh83
$ ct install            # 使用 dir 源，记录打印的 -I
$ ct build <入口> -I <上一步打印的路径>
error: unit 'pkg-a/pkg-a' exists in two import roots
$ echo $?
1
```

## 期望行为

- `ct install` 打印的 `-I` 必须可直接使用；
- 若 dev override 已自动加入同一个根，输出应去重，或只打印未被覆盖的根；
- 冲突时诊断列出两个根的来源（lock / override / 显式 `-I`），而不是只报 `two import roots`。

## 影响

包发布产物的安装指引与构建规则自相矛盾；按提示操作必然失败，只能靠猜去掉某个 `-I`。

## 关联

- [SH-84](sh84-verify-strict-no-dev-override-path.md)：同属 dev override 的规则边界。
- [SH-81](sh81-qualified-name-falls-back-to-url.md)：同属工具输出把用户带向错误路径。

## 本仓评估（2026-11-16）

- **受理：是**
- **定性：已声明未兑现**——S1 验收写明的「照抄 `-I` 可构建」在 dev override 下不成立。
- **依据：** 提案 §10 S1 验收（[ct-pkg-shared-store.md](../../docs/proposals/ct-pkg-shared-store.md)）：
  「`ct install` 打印的 `-I` 可直接解析；同版本重装不覆盖」，验收行为「照抄 `ct build` RC=0」；
  SP-008 / SP-015（[需求](../../docs/planning/ct-pkg-shared-store-requirements.md)）分别承诺自动补
  `-I` 与 dev override 双留痕。
- **优先级 / 落点：** P1；`v0.61.x` patch。输出对 override 去重，或只打印未被覆盖的根；
  冲突诊断列出两个根来源。
