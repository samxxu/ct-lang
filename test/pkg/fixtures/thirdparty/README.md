# PKG-17 第三方包 vendored fixture

本目录是 [PKG-17](../../../../issues/packages/pkg-17-third-party-fixture-ci.md) 要求的
最小 vendored 第三方包快照：用来在隔离 `HOME` / `CT_HOME` 下离线证明
`ct index verify`、`ct get --index`、`ct build` 的第三方身份路径，并钉住五字段旧行与
坏摘要两条负例。

| 项 | 值 |
| --- | --- |
| 来源 | 本仓库按 issue §1 合成；不复制上游第三方源码或历史 |
| 版本 | `demo/hello`、`acme/hello`、`ct/hello` 均为 `0.1.0` |
| 重生成 | `bash test/pkg/fixtures/thirdparty/regen.sh` |
| 只校验 | `bash test/pkg/fixtures/thirdparty/regen.sh --check` |
| 探针 | `test/pkg/pkg17_thirdparty.sh`（由 `test/pkg/run.sh` 调用） |

## 来源与边界

- `pkg/**` 是唯一源；包体只保留证明安装/构建所需的最小面（一个 `ct.pkg` + 一个
  `src/*.h.ct`），不是上游项目的完整功能或源码历史。
- `publisher = demo` / `acme` 是非官方身份；`publisher = ct` 的 `hello` 行只用于
  D-010-B 的“显式索引优先”断言，不代表官方发布。
- `git/**` 是 `pkg/**` 的 vendored bare 快照，由 `regen.sh` 在本地生成；作者、提交者、
  日期、分支与对象格式都写死，重复生成得到同一 commit。
- 所有索引 URL 都是相对路径 `../git/<repo>.git`。探针把 fixture 复制到临时目录后，从
  项目子目录解析这些 URL；另设 `GIT_ALLOW_PROTOCOL=file`，任何 https/ssh 传输都会被
  `git` 直接拒绝。除本地 `git clone` 外不联网。
- 每个用例使用独立的 `HOME` 与 `CT_HOME`，临时目录由 `mktemp -d` 创建，不使用固定
  `/tmp` 路径；可重复执行、可并行执行。

## 包与摘要

| 包 | 版本 | 源目录 | git 快照 | commit | 树 sha256 |
| --- | --- | --- | --- | --- | --- |
| `demo/hello` | `0.1.0` | `pkg/hello` | `git/hello.git` | `6422a33ea00132609f5663b1b715765a66593c1c` | `sha256:09dec29b1b7ed00b87ed6d0d38ffcf256bb5da0eddd3cbe2458d50bab147afb9` |
| `acme/hello` | `0.1.0` | `pkg/acme/hello` | `git/acme-hello.git` | `b948db3a3618f16c3e49fcd01c3189ec6c0e9533` | `sha256:e1b567b2cf66e760ec80922b86ab399dc2d7ab35b9c57281c2ac7e079c07b443` |
| `ct/hello` | `0.1.0` | `pkg/ct/hello` | `git/ct-hello.git` | `efe254fe551ff0b5b287d45e45eefec5c2ec4845` | `sha256:4ebcda16f51b38828a1a995bdb35a1ba404bc5b5f7ad553692d7bcf76255d499` |

`demo/hello` 的 `hello_value()` 返回 `42`，`acme/hello` 返回 `43`，`ct/hello` 返回 `7`；
不同返回值用来证明两个同名 publisher 的 store / cache 没有串包。

## 索引行

| 文件 | 形状 | 用途 |
| --- | --- | --- |
| `index/six` | 六字段 | 正例：`ct get --index` 安装 `demo/hello` |
| `index/five` | 五字段旧行 | 负例：`ct index verify` 按行报 `legacy-five-field`；`ct get` 硬错 |
| `index/bad-digest` | 六字段 + 内容错摘要 | 负例：`ct get` 摘要不符硬错，不写 store / 不改 `ct.lock`；`ct index verify` 只查格式，因此它按结构通过 |
| `index/two-publishers` | 两行同名不同 publisher | D-010-A：裸 `hello` 不可解析；`demo/hello` 与 `acme/hello` 各自可装 |
| `index/ct-row` | 六字段，`publisher = ct` | D-010-B：`ct get --index ... ct/hello` 以索引为准 |

## 消费者

`consumer/` 是一个只依赖 `demo/hello` 的项目：`main.ct` 写 `import hello;` 并打印
`hello 42`。它由 fixture 的六字段行安装后，用 `ct build` 构建并运行。

## 重生成

```sh
bash test/pkg/fixtures/thirdparty/regen.sh
# 按脚本打印的 commit / sha256 更新上面的「包与摘要」表
bash test/pkg/fixtures/thirdparty/regen.sh --check
```

`regen.sh --check` 会重算 `pkg/**` 的树摘要、从 bare 快照的 tag 解出树并比对、
逐字比对五个索引文件，并确认 README 记录了三个 digest 与三个 commit。任何一项漂移
都非零退出。

## golden 规则

- `pkg/**`、`git/**`、`index/**` 与 README 的摘要表一经入库即 golden；改动必须单独提交，
  说明原因与影响面。
- 包内容变化必须 bump `version`，并同步 README 的 sha256 与索引行。
- 不允许“为了让测试变绿”改 fixture；测试期望若必须随 fixture 改，在同一提交里说明。
