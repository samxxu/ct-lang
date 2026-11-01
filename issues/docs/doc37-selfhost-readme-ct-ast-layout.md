# DOC-37 · `selfhost/README.md` 中文表仍是 ct-ast 三文件旧布局，且门禁清单漏 `check-warnings.sh`

| 项 | 值 |
| --- | --- |
| 模块 | docs（selfhost 说明） |
| 严重度 | Medium |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [selfhost/README.md:18](../../selfhost/README.md#L18)、[:27-29](../../selfhost/README.md#L27-L29)、[:81-83](../../selfhost/README.md#L81-L83) |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

1. 中文源码表把 ct-ast 写成三个文件：

   > `ct-ast/{main.ct,Pkg.h.ct,Diag.h.ct}` ｜ … `main.ct` 是 driver + 编译核心，`Pkg.h.ct` 是包管理器，
   > `Diag.h.ct` 是告警存储与错误计数

   实际是 20 个分组单元（`frontend/{lex,module,parse,sym,type}`、`backend/{emit,mem}`、
   `runtime/arena`、`tool/{cache,diag,driver,pkg}`），且 `main.ct` 只做绑定与分派
   （同文件英文行 :53 与 [main.ct:2-8](../../selfhost/ct-ast/main.ct#L2-L8) 都这么写）。
   `Pkg.h.ct` / `Diag.h.ct` 现已位于 `tool/pkg/`、`tool/diag/`。

2. 脚本清单（中 :27-29，英 :81-83）只列 `check-goldens · check-archive · check-m2a · ct-tour · check-ast`，
   漏掉 `check-warnings.sh`——它是 `check-all.sh` 的第 9 关。

## 证据

```text
$ find selfhost/ct-ast -name '*.ct' | wc -l
20
$ ls selfhost/ct-ast/tool/pkg/Pkg.h.ct selfhost/ct-ast/tool/diag/Diag.h.ct
…
$ sed -n '80p' selfhost/check-all.sh
run_gate "9) generated C warning-free (-Wall -Wextra)" bash selfhost/check-warnings.sh
```

## 建议

中文表整行替换为与英文 :53 等价的描述（分组单元 + `main.ct` 只绑定分派），并列出 `tool/{pkg,diag,cache}`；
两处脚本清单补 `check-warnings.sh`，或改成「`check-*.sh` / `ct-tour.sh`，逐个见 README §5」以免再漏。
