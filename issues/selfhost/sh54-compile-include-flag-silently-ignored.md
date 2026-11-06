# SH-54 · compile 模式静默丢弃 `-I`，`--help` 仍宣称可用

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | Medium |
| 锚点 | commit `c27da3d`（2026-11-06，`v0.19.1`+1） |
| 站点 | [Driver.h.ct:114](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L114)（usage）、[Driver.h.ct:193-199](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L193-L199)（`-I` 分支） |
| 状态 | 已修（2026-11-06，commit `f612b11`） |

## 现象

`ct compile` / `ct check` 走的是 `Driver.run()`，`-I <dir>` 被消费后直接 `i++` 跳过，
既不写入任何搜索根，也不提示：

```c
if (strcmp(argv[i], "-I") == 0) {
    ...
    i++;   /* accepted for CLI parity; compile mode resolves no imports */
}
```

但同一入口打印的 usage 第一行仍写着 `[-I <dir>]`：

```text
usage: ctc <input.ct> [-o <output.c>] [-I <dir>] [--line|--no-line]
```

build 侧的同名开关会存入 `incdirs` 并参与解析（[Module.h.ct:662](../../selfhost/ct-ast/frontend/module/Module.h.ct#L662)），
第 17 个根报 `ctc: too many -I roots`。因此帮助文本对 compile 的说法与实现相反。

## 现象与复现

```bash
# 1) help 宣称 compile 支持 -I
$ ct --help | head -2
usage: ctc <input.ct> [-o <output.c>] [-I <dir>] [--line|--no-line]

# 2) 无 import 的文件 + 不存在的搜索根：rc=0，且无任何 warning
$ ct compile -I /nonexistent hello.ct -o /tmp/hello.c
$ echo $?
0

# 3) 有 import 时，-I 也无法改变结论（与是否传 -I 无关）
$ ct compile -I test/modules/inc/extra test/modules/inc/main.ct -o /tmp/x.c
test/modules/inc/main.ct:1:1: error: 'import' is not supported in compile mode
$ echo $?
1
```

## 根因

- [Driver.h.ct:193-199](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L193-L199)：`-I` 分支只跳过参数，无赋值、无诊断；
- [Driver.h.ct:114](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L114)：usage 未区分模式，把 build 专属开关列进了 compile 行；
- 与 [SH-24](cli-parser-duplication.md) 同源，但 SH-24 已决「不合并两套解析器」；
  [DOC-25](../docs/doc25-include-roots-asymmetry.md) 只在文档层记录过 compile 不解析 import，
  帮助文本与运行时行为这两处残留未处理。

## 影响

- 用户按 `--help` 传 `-I` 后仍得到同一句 import 报错，无法判断是「搜索根不对」还是「模式不支持」；
- 脚本中给 compile 传 `-I` 的调用永远不生效，且没有任何提示，属于静默失真；
- 与 DOC-65 叠加：文档的 compile 行也没说明 `-I` 无效，用户几乎没有自证途径。

## 修复建议

不合并两套解析器（沿用 SH-24 的处置），只做最小修正：

1. 从 compile/check 的 usage 行删掉 `[-I <dir>]`，build 行保留（[Driver.h.ct:114](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L114)）；
2. `-I` 分支改成向 stderr 打一行 warning 后继续，保持退出码不变（风险最低）：

   ```text
   ctc: warning: -I is ignored by compile mode; imports require 'ct build'
   ```

   若维护者倾向严格化，则改为 `ctc: -I only applies to 'ct build'` 并 `exit 1`，
   但需同步 DOC-65 与所有给 compile 传 `-I` 的脚本/断言；
3. 帮助文本与 README/教程（DOC-65）保持同一口径。

## 验证

- `ct --help` 的 compile/check 行不再出现 `-I`，build 行仍出现；
- 无 import 文件 + 任意 `-I`：输出 warning（严格化时 rc=1），不写坏产物；
- 不传 `-I` 时 compile/check 的输出字节与现状一致；
- 在 `selfhost/check-ast.sh` 增一条 `-I` 探针；`bash selfhost/check-all.sh` 12 道门禁全绿。

## 处置

**认可，采用建议 2 的「保留退出码的 warning」，建议 1 一并落地；严格报错不采纳。**

- usage 的 compile/check 行删掉 `[-I <dir>]`，build 行保留（建议 1）。
- `-I` 分支不再静默 `i++`，改为向 stderr 打一行 warning 后继续：

  ```text
  ctc: warning: -I is ignored by compile mode; imports require 'ct build'
  ctc: warning: -I is ignored by check mode; imports require 'ct build'
  ```

  模式名取自 `Driver.check_mode`，因此两个单文件入口各自说对自己。
- 不选严格报错的理由：`-I` 保留是为了与 `build` 的 CLI 对齐（SH-24 已决「不合并两套解析器」），
  而脚本常把同一组 flags 同时喂给多个入口。把「多传了一个无效 flag」升级成失败，会打断这种组合；
  warning 已消除静默失真，同时不改变任何既有调用的退出码。issue 自身也把这一案标为「风险最低」。
- 负例断言（旧文案没有等价断言可同步，全部为新增）：
  `check-ast.sh` 增 compile `-I` 探针（rc=0 + 逐字 warning），
  `check-semantics.sh` 增 check `-I` 探针（rc=0 + 逐字 warning）。
- 提交：`f612b11`。
