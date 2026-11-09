# DOC-24 · 教程称普通 `.ct` 会生成 `.h`，与 batch 30 规则和 README 相反

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **High** |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [docs/tutorial.md](../../docs/tutorial.md#L78)（中文）、[docs/tutorial.md](../../docs/tutorial.md#L1090)（英文） |
| 状态 | 已修（`94815d7`，2026-11-09 回填） |

## 现象

教程第一条命令就写着：

```text
ct hello.ct -o hello.c        # 生成 hello.c 与同名 hello.h
```

batch 30 已把产物规则改为「**只有 `.h.ct` 单元写 `.h`**」，普通 `.ct` 输入只产出 `.c`。
README 的 CLI 表（[README.md:54](../../README.md#L54)、[README.md:55](../../README.md#L55)）写的是正确口径，
教程与 README 自相矛盾。

## 证据（探针）

```bash
$ /tmp/a/ct-ast hello.ct -o hello.c
$ ls hello.c hello.h
hello.c
ls: hello.h: No such file or directory
```

源码规则见 [check-ast.sh](../../selfhost/check-ast.sh) batch 30 段（`only a .h.ct unit writes a .h`），
以及 `test/ast/` 的 split 用例对产物集合的断言。

## 影响

新手按教程第一次执行就会去找一个不存在的 `hello.h`，容易误判为安装或编译器损坏；教程自称
「每条命令都可直接粘贴」，这条命令的实际结果与注释不符。

## 修复建议

两处注释改为「生成 hello.c（仅当输入为 `.h.ct` 时才同时写 `.h`）」，并在正文第一次解释产物时补一句
batch 30 规则；中英各一份，保持对称。

## 验证

`grep -n "hello.h" docs/tutorial.md` 不再命中误导性描述；按教程手工执行命令，产物集合与文档一致。

## 处理（2026-10-31）

已修复：教程中英两处改为「普通 `.ct` 只写 `.c`；只有 `.h.ct` 写 `.h`」。

- 修复提交：`94815d7`（`docs(spec): dispose of the 2026-10-31 audit findings`）。
- 验证证据：`docs/tutorial.md` 中文（`:78`）与英文（`:1090`）两处注释均已改为「仅 `.h.ct` 写 `.h`」；
  2026-11-09 复跑 `bash selfhost/check-all.sh`，11 道门禁全绿。
