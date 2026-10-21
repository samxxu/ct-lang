# SH-9 · ct-ast 解析期诊断缺文件名与列号，与四份文档的 `file:line:col: error:` 不符

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast）/ docs |
| 严重度 | **Medium** |
| 锚点 | commit `dde0dda`（2026-10-21） |
| 文件 | [selfhost/ct-ast/frontend/parse/](../../selfhost/ct-ast/frontend/parse/)、[README.md:68](../../README.md#L68)（英文 [:509](../../README.md#L509)）、[docs/tutorial.md:388](../../docs/tutorial.md#L388)（英文 [:789](../../docs/tutorial.md#L789)）、[docs/glossary.md:81](../../docs/glossary.md#L81)（英文 [:243](../../docs/glossary.md#L243)）、[AGENTS.md:104](../../AGENTS.md#L104) |
| 状态 | ⬜ 未修复（2026-10-21 复核：解析期与驱动期共用同一个 `errmsg` 缓冲，`cannot open the input file` 之类驱动错误也从这里出；正确定位需要先把两条错误通道分开，属独立议题） |

## 现象

安装入口 `ct` 的**解析期**报错只有 `ctc: line N: …`，没有文件名、没有列号：

```text
$ ct bad.ct -o bad.c
ctc: line 2: expected an expression (at ';')
$ echo $?
1
```

同一个二进制在**语义期**（重复 trait / struct、`map` 绑定）却输出 `file:line:col: error:`。两类诊断
格式不统一，而文档对外的描述是后者。

## 证据

`bad.ct` 内容：

```c
int main(void) {
  int x = ;
  return 0;
}
```

三层对比：

| 编译器 | 输出 |
| --- | --- |
| L0 | `exit=0`（L0 不解析函数体，透传） |
| L2 | `exit=0`（同） |
| ct-ast | `ctc: line 2: expected an expression (at ';')` |

文档侧声明「错误格式为 `文件:行:列: error: 描述`」的位置：`README.md:68`（英文 `:509`）、
`docs/tutorial.md:388`（英文 `:789`）、`docs/glossary.md:81`（英文 `:243`）、`AGENTS.md:104`。

## 影响

- 多单元 `build` 时无法判断错误来自哪个输入文件；编辑器/工具按 `file:line:col` 解析日志会失败。
- 语义期与解析期混用两种格式，用户难以形成稳定预期。

## 修复建议

1. **改代码（推荐）**：解析期 `die` 也带上输入路径与列号，复用语义期已有的格式化入口；驱动层错误
   （`ctc: unknown option …`）保持现在的 `ctc:` 前缀——两者本就不同类。
2. **改文档**：若坚持解析期只用 `ctc: line N:`，则在 README / tutorial / glossary 明确区分
   「语法错误」与「语义错误」两种格式。

注意 `test/errors` 的断言依赖 `文件:行:列: error:` 前缀（只测 L0），`check-ast.sh` 的负例断言若改动
格式需一并同步。

## 验证

- 上面的 `bad.ct`：诊断包含输入路径与列号（方案 1），或文档已明确区分两类格式（方案 2）。
- 回归面：`bash selfhost/check-ast.sh`、`bash selfhost/check-all.sh` 八关全绿。
