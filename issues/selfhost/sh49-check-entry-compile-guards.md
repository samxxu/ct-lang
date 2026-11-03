# SH-49 · `ct check` 继承了编译模式的两道输出前置守卫

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | Low |
| 锚点 | commit `db4cae4`（2026-11-03，`v0.19.0`） |
| 文件 | [Driver.h.ct:240-262](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L240-L262)；check 早退块在 [L304-L311](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L304-L311) |
| 状态 | 已修复（本轮，2026-11-03） |

## 现象

`ct check` 复用 `compile_main`，但 check 的早退块排在 `.m.ct` 守卫与默认输出路径解析**之后**：

```text
240  … if (.m.ct) { "a .m.ct unit produces no output; import it from a .ct unit"; return 1; }
256  if (!out) { if (default_output(...) != 0) { "output path too long"; return 1; } }
304  /* `ct check` (19.4): … */
307  if (self->m->check_mode) { emit; return nwarn > 0; }
```

两个后果：检查模式并不产生输出，却要先满足输出侧的约束。

## 证据

```
$ ct-ast check m.m.ct
ctc: a .m.ct unit produces no output; import it from a .ct unit
rc=1
```

- `ct check` 从不 `fopen(out)`（`:312` 之后才是编译发射），所以「produces no output」这句对 check 不成立；
  用户无法判断是「check 不支持 `.m.ct`」还是「这个单元本身有问题」。
- 同理，输入路径长到 `default_output` 溢出时，check 会以 `output path too long` 失败，
  而它根本不需要输出路径（该分支只在未给 `-o` 时触发）。

## 影响

低：正常 `.ct` 单元不受影响。但错误信息指向错误的原因，且 `.m.ct` 与超长路径是本可以正常「检查」
（至少给出准确拒绝理由）的两种输入。

## 修复建议

把 check 早退块前移到 `:240` 之前（解析完参数、`check_mode` 已置位即可），即：

1. 解析参数 → `if (check_mode) { parse; emit; return nwarn > 0; }` → 再做 `.m.ct` 守卫与输出路径解析；
2. 若决定 check 不支持 `.m.ct`，早退块里单独给一句 `ctc: ct check accepts a .ct unit, not a .m.ct unit`；
3. 保持「check 不写任何文件」的现有断言（`check-semantics.sh` 已覆盖）。

## 验证

修复后：`ct-ast check m.m.ct` 的报文指向 check 的输入限制；把输入路径构造到 `default_output` 溢出长度，
`ct check` 不再报 `output path too long`；`bash selfhost/check-semantics.sh` 仍 8/8。

## 处置

**认可「两个守卫不该作用于 check」，不采纳「前移早退块」的具体做法。**

前移早退块会把 parse 循环再复制一份到守卫之前，而真正的问题只是两个 `return 1` 在 check 下没有意义。
改为给两道守卫加条件，效果与被前移完全相同，改动面更小：

- `.m.ct` 守卫包进 `if (!self->m->check_mode)`，见
  [Driver.h.ct:247-257](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L247-L257)。于是 `.m.ct`
  在 check 下是**合法输入**（声明与默认体正是要检查的东西），而不是像建议 2 那样换成一句
  「check 只接受 `.ct`」——它本可以检查。
- 输出路径解析改为 `if (!out && !self->m->check_mode)`，并注明 SH-49，见
  [Driver.h.ct:258-266](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L258-L266)。
- 编译路径行为不变：`compile` 仍以 `a .m.ct unit produces no output` 拒绝 `.m.ct`，仍解析默认输出。

验证（`check-semantics.sh` 新增两条断言，两向都钉住）：

```
ok    check: a .m.ct declaration unit is a valid input (SH-49)
ok    compile: .m.ct is still rejected as a build-only input
```

`check: no C artefact is written` 仍为绿（`ct check -o x.c` 后 `x.c` 不存在）。
