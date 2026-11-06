# SH-55 · `import` 拒绝文案不给替代路径，`ct check` 复用时报错身份错位

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | Low |
| 锚点 | commit `c27da3d`（2026-11-06，`v0.19.1`+1） |
| 站点 | [Parser.h.ct:811-815](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L811-L815)（守卫）、[Driver.h.ct:92](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L92)（`check_mode`） |
| 状态 | 已修（2026-11-06，commit `83f3776`） |

## 现象

compile 与 check 对 `import` 都报同一句：

```text
error: 'import' is not supported in compile mode
```

- `ct check` 走的不是 compile，但输出仍自称 compile mode，身份错位；
- 文案只说明「不支持」，没有给出替代路径（`ct build`），也没有说明 `-I` 属于 build；
- 守卫在判断 `.ct` / `.h.ct` 之前触发，两种输入得到完全相同的句子。

## 复现

```bash
$ ct compile test/modules/inc/main.ct -o /tmp/x.c; echo $?
test/modules/inc/main.ct:1:1: error: 'import' is not supported in compile mode
1

$ ct check test/modules/inc/main.ct; echo $?
test/modules/inc/main.ct:1:1: error: 'import' is not supported in compile mode
1

$ printf 'import util;\n\nint main(void) { return 0; }\n' > /tmp/m.h.ct
$ ct compile /tmp/m.h.ct -I test/modules/inc/extra -o /tmp/m.c; echo $?
/tmp/m.h.ct:1:1: error: 'import' is not supported in compile mode
1
```

对照：同一夹具用 `ct build -I test/modules/inc/extra test/modules/inc/main.ct` 可正常解析并产出
`main.c` / `util.c` / `util.h`。

## 根因

- [Parser.h.ct:811-815](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L811-L815) 只读 `*self->build_mode`：

  ```c
  if (!*self->build_mode)
      return self->sup->fail("'import' is not supported in compile mode");
  ```

- `check` 与 `compile` 共用 `Driver.run()`，`build_mode` 在这两条路径上都是 0；
  区分二者的 `check_mode` 已在 [Driver.h.ct:92](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L92)
  和 [Driver.h.ct:101-104](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L101-L104) 置位，
  但没有传给 Parser，也没有参与文案选择。
- 文案硬编码 `compile mode`，且不包含补救动作。

## 影响

- 诊断不可执行：用户看到报错后仍不知道应该改用 `ct build`，也不知道 `-I` 只在 build 生效；
- 与 [README.md:40](../../README.md#L40) / [DOC-62](../docs/doc62-check-import-undocumented.md) 的口径冲突：
  文档说 `ct check` 拒绝 import，工具却说是 compile mode；
- 与 [SH-54](sh54-compile-include-flag-silently-ignored.md) 同一处入口，修文案时可一并处理。

## 修复建议

让 Parser 能区分 check 与 compile（增加一个 mode 字段或直接把 `check_mode` 传入），并使用可执行文案：

- compile：

  ```text
  'import' requires multi-file mode: use 'ct build'
  ```

- check：

  ```text
  'import' requires multi-file mode: use 'ct build' to check the module graph
  ```

若不想扩字段，至少统一为中性且可执行的单句（消除 `ct check` 输出里的身份错位）：

```text
'import' requires multi-file mode: use 'ct build'
```

文案修改需同步 `check-ast.sh` / `check-semantics.sh` 的逐字断言。

## 验证

- `ct compile` 与 `ct check` 分别输出各自文案，均包含 `ct build`，且都不再出现与当前命令不符的模式名；
- `.ct` 与 `.h.ct` 的拒绝路径仍一致（守卫位置不变）；
- 更新 [check-ast.sh:2341-2348](../../selfhost/check-ast.sh#L2341-L2348) 与
  [check-semantics.sh:107-121](../../selfhost/check-semantics.sh#L107-L121) 的逐字断言，
  并补一条 check 专用断言；`bash selfhost/check-all.sh` 12 道门禁全绿。

## 处置

**认可，采用「模式感知文案」方案；两句建议文案均落地。**

- Parser 增加 `check_mode` 指针（`ct_parse_bind` 第 7 参数，`Driver` 传入 `&m->check_mode`），
  守卫按真实模式选句：
  - compile：`'import' requires multi-file mode: use 'ct build'`
  - check：`'import' requires multi-file mode: use 'ct build' (ct check is single-unit)`
- check 句用括号说明「为什么 check 不行」，而不是建议里的 `to check the module graph`：
  `ct check` 根本没有多单元模式，指向 `ct build` 的图更准确；同时两句共享同一前缀，
  compile 侧的文案仍可被 `grep` 精确匹配，`check-ast.sh` 也能用「含前缀且不含 check 后缀」
  把两个入口区分开。
- 断言同步：`check-ast.sh` 改为逐字断言 compile 句且显式排除 check 后缀；
  `check-semantics.sh` 改为逐字断言 check 句（原来的 `not supported in compile mode` 已删除）。
- 守卫位置未动，`.ct` 与 `.h.ct` 的拒绝路径仍一致。
- 提交：`83f3776`。
