# PKG-3 · `ct.pkg` 未知键（如 `ns-root`）被静默忽略，无任何警告

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct.pkg` 解析） |
| 定性 | **诊断缺陷**（声明被接受但不生效，用户无处得知） |
| 严重度 | Medium |
| 锚点 | 工作树 `89b1124b`（`ct v0.53.0` 二进制实测） |
| 文件 | [Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct)（`read_manifest` 只认固定键）、[package-guide.md §8.4](../../docs/package-guide.md)（现状说明） |
| 状态 | verified |
| 处置证据 | **已修**（v0.58.3：`read_manifest` 对未知键发 `has unknown key` 告警；`test/pkg/run.sh` 135/0） |

## 现象

`ct.pkg` 里写目标机制才有的键（`ns-root`、`publisher`）不会报错，也不会生效。用户以为已经声明了单元树根，实际工具仍然只把包根当 include 根。

## 最小复现

```sh
mkdir -p /tmp/p3/pkg/src/beta /tmp/p3/proj
printf 'name = beta\nversion = 0.2.0\nns-root = src\n' >/tmp/p3/pkg/ct.pkg
printf 'namespace beta;\n\npub int pong(void) { return 7; }\n' >/tmp/p3/pkg/src/beta/Beta.h.ct
printf 'name = demo\nversion = 0.1.0\ndep = ../pkg@^0.2.0\n' >/tmp/p3/proj/ct.pkg
printf 'import beta::Beta;\nint main(void){ return beta::pong(); }\n' >/tmp/p3/proj/main.ct
cd /tmp/p3/proj && ct update && ct install && ct build -I vendor/beta main.ct -o build
```

实际输出：

```text
updated 1 package(s)                       # ns-root 不报错
ct build -I vendor/beta main.ct -o build   # 打印的 -I 不含 src
ctc: cannot resolve import 'beta/Beta'     # rc=1
```

## 期望行为

- 未知键至少告警：`ctc: warning: '<dir>/ct.pkg' has unknown key 'ns-root'`（S1 起 `ns-root` 转为已知键，不再告警）。
- S1 起 `ns-root` 必须是已知键且参与 `-I` 计算；缺失即硬错（[SP-003](../../docs/planning/ct-pkg-shared-store-requirements.md)）。

## 交叉引用

- 提案 [§3](../../docs/proposals/ct-pkg-shared-store.md)、[§12 D2](../../docs/proposals/ct-pkg-shared-store.md)
- 需求 SP-002 / SP-003
- [PKG-2](pkg-2-ct-install-package-root-import.md)（同一个坑的消费端表现）

## 修复排期

S1（工具最小可用）：`read_manifest` 增加键白名单与告警，`ns-root` / `publisher` 升为已知键。不得在切片前单独改实现。

## 处置（v0.58.3）

- `read_manifest` 保留既有解析，同时对不在已知集合内的键发
  `ctc: warning: '<dir>/ct.pkg' has unknown key '<key>'`。
- 已知集合：`name` / `version` / `dep` / `publisher` / `ns-root` / `cflags` / `ldflags` / `requires` /
  `licence` / `license` / `namespace` / `source` / `type` / `website`。
- 未知键不阻断构建，只提示；`ns-root` / `publisher` 的形态错误仍由 S1 硬错。

## 验证

```console
$ bash test/pkg/run.sh
== summary: 135 passed, 0 failed ==
```
