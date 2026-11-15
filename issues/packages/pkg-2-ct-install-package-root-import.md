# PKG-2 · `ct install` 只打印 `-I vendor/<包名>`，包内单元不在包根时消费端无法 import

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct install` / 包布局；影响外部仓库 `ct-pkg` 下的消费者） |
| 严重度 | **Medium** |
| 锚点 | 本仓库 `eaaeae75`（`v0.53.0` 之后、`v0.53.1` 之前） |
| 文件 | [Pkg.h.ct#L1388-L1396](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1388-L1396)（打印入口）；[package-guide.md](../../docs/package-guide.md)（`ct install` 的契约描述） |
| 状态 | **open / 未来处理**（不阻塞当前相；负责人已反馈给 CT 项目组，见「处置」） |

## 现象

`ct install` 为每个 vendored 包打印一条固定格式的 include 根：

```c
printf("%s build", prog);
for (i = 0; i < nlock; i++) printf(" -I vendor/%s", lname[i]);
```

它**不读包内布局**，只把包根当 include 根。于是只要包的单元不在包根（典型形态是
`src/<namespace>/`），消费端照抄这条打印出来的命令就会解析不到 import。

包作者没有可配置项：`ct.pkg` 的 `cflags` 只进 `cc` 行，不参与 `ctc` 的 import 解析；
`ct.lock` 也不记录 include 根。

## 最小复现

造一个 `src/<ns>/` 布局的包，走完整链路（`ct get` 建 `ct.lock` + `vendor/`，再 `ct install`
取打印命令，最后照抄执行）：

```sh
# 1) 包：单元在 src/fsguard/，包根没有 fsguard/ 目录
mkdir -p /tmp/pkgprobe/vendor/fsguard/src/fsguard /tmp/pkgprobe/app
printf 'pub trait FsOps {\n    int exists(const char *p);\n}\n' \
    > /tmp/pkgprobe/vendor/fsguard/src/fsguard/FsGuard.h.ct
printf 'name = fsguard\nversion = 0.1.0\n' > /tmp/pkgprobe/vendor/fsguard/ct.pkg

# 2) 消费者
printf '#include <stdio.h>\nimport fsguard::FsGuard;\nint main(void) { return 0; }\n' \
    > /tmp/pkgprobe/app/main.ct
cd /tmp/pkgprobe/app
printf 'name = app\nversion = 0.1.0\ndep = fsguard\n' > ct.pkg
ct-ast get ./../vendor/fsguard        # 写 ct.lock 与 vendor/fsguard

# 3) 取 ct install 打印的命令，并照抄执行
ct-ast install
```

### 实际输出

```text
$ ct-ast install
ct-ast build -I vendor/fsguard main.ct -o build
rc=0

$ ct-ast build -I vendor/fsguard main.ct -o build
ctc: cannot resolve import 'fsguard/FsGuard'
rc=1

$ ct-ast build -I vendor/fsguard/src main.ct -o build
'cc' -std=c99 -I '.ctbuild' '.ctbuild/main.c' '.ctbuild/FsGuard.c' '-o' 'build'
rc=0
```

`ct install` 自己 rc=0、打印的命令也「可执行」，但它打印的 include 根解析不到包内的单元；
真正能工作的是消费者**自己算出来**的 `-I vendor/fsguard/src`。

## 影响的包

| 包 | 布局 | 实测症状 | 记录 |
| --- | --- | --- | --- |
| `ct-http` | 曾为 `src/http/` | 照抄 `-I vendor/http` → `ctc: cannot resolve import 'http/http'` | `ct-http/docs/proposals/ct-install-include-prefix.md`；`issues/HTTP-2.md`；本仓 [sh71](../../issues/selfhost/sh71-host-map-unit-boundary.md) |
| `ct-fsguard` | `src/fsguard/` | 消费者 import `fsguard::FsGuard` → `cannot resolve import 'fsguard/FsGuard'` | `ct-fsguard/docs/decisions/D-011.md` §理由 5 与 §失效条件；`docs/reviews/fsguard-std-overlap.md` |

共性：**单元在 `src/<ns>/`、include 根需要是 `src/`**，而 `ct install` 只给包根。

## 现有两种绕法

1. **包根加一层前缀目录**（`ct-http` 采用）：把单元从 `src/http/` 迁到包根 `http/`，
   于是 `-I vendor/http` 直接成立。`ct-http` 的 `test/gates/p10_install.sh` 断言安装命令含
   `-I vendor/http` 且不含 `-I vendor/http/src`。
2. **消费者自己算 `-I`**：忽略 `ct install` 打印的 `-I`，改成 `-I vendor/<包名>/src`。
   本 issue 的最小复现里第三条命令就是这一种。

## 为什么绕法不该成为规范

- **绕法 1 改变了包自身布局**：`src/<ns>/` 是包内组织方式的选择，不该为了凑工具打印格式而
  被迫把命名空间目录提到包根；包根被单元目录占满后，`README` / `tests` / `docs` 与单元混在一起。
  `ct-fsguard` 的 D-011 明确把「`src/` 与 `ct install` 不兼容」列为待处置的包形态缺口，
  而不是该改布局。
- **绕法 2 让 `ct install` 的输出不再是契约**：`ct install` 的语义是「打印一条可直接执行的
  `ct build` 命令」。要消费者手工追加/改写前缀，这条命令就不是可执行真值，而是需要二次加工的
  半成品；`ct verify` / `ct update` 的重现性也随之打折（同一 `ct.lock` 在不同包上要写不同的
  `-I` 规则）。
- **两种绕法互相冲突**：同一生态里 `ct-http` 用绕法 1、`ct-fsguard` 留 `src/` 只能靠绕法 2，
  下游同时依赖两者时必须记住「哪个包要不要加 `src`」——这是工具该消除的知识，不是包作者该背的。
- **绕法 1 的迁移成本会随时间上涨**：包一旦发布并被打 tag，迁布局就是破坏性变更（`import`
  路径不变，但 `-I` 根与目录校验 `--ns-root` 的输入都变），越晚裁定越贵。

## 修复方向（未裁定，仅登记备选）

沿用 `ct-http` 提案给出的三选一（本 issue 不预设结论）：

1. `ct.pkg` 增加 `include = <相对路径>`（可多条），`ct install` 逐条打印
   `-I vendor/<name>/<include>`，未声明时默认包根（向后兼容）。
2. 强制包根约定：单元必须位于包根，`ct verify` / `ct get` 校验每个 `import` 能从包根解析。
3. 自动探测：`ct install` 探测包根与 `src/`，打印实际存在的第一个 include 根。

选择需要同时回答：`--ns-root` 目录校验的输入、`ct.lock` 是否要记录 include 根、
以及 `ct verify` 的离线校验面是否随之扩大。

## 处置

- **处理时机：未来，不阻塞当前相。** 本条只登记，不改 `Pkg.h.ct`、不改 `package-guide.md`
  的既有契约描述；`v0.53.1` 的两处 P0 修复与本条无关。
- 负责人已把该问题反馈给 CT 项目组，正式规则由 `ct-lang` 侧给出后再统一下游布局；
  在规则落地前，包侧继续按「包根加前缀目录」或「消费者自算 `-I`」自处。
- 恢复条件：`ct-lang` 就 §修复方向 之一作出裁定，或出现第三个受影响的包。
