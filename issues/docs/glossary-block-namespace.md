# DOC-10 · 术语表仍把 namespace 写成块式，编译器已拒绝

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **High** |
| 锚点 | commit `4ef8b68`（2026-10-21） |
| 文件 | [docs/glossary.md](../../docs/glossary.md#L33)、[:195](../../docs/glossary.md#L195) |
| 状态 | ✅ 已修复（2026-10-21；验证见 [issues/README.md](../README.md) 的「Phase 12 复审」一节） |

## 现象

术语表（中文第 33 行、英文第 195 行）把命名空间语法记为：

> `namespace A::B { … }` —— 唯一可嵌套构造；符号加 `A_B_` 前缀

## 证据

- 提交 `45b68e7 refactor(selfhost): reject block-scoped namespaces` 起，ct-ast 明确拒绝块式书写。
  实测（同一输入分别喂 L2 与 ct-ast）：

  ```text
  $ ct-ast block.ct -o /tmp/block.c ; echo $?
  ctc: line 1: a namespace is file-scoped: write 'namespace A::B;' (at '{')
  1
  ```

- `AGENTS.md` 亦写明「块式 namespace 语法必须禁止，仅允许分号式 `namespace A::B;`」。
- 对照 `test/modules/**` 与 `selfhost/ct-ast/**` 的真实源码，全部是分号式。

## 影响

术语表自称「命名与措辞的唯一对照表」，编辑器作者与新用户会按块式书写，直接被编译器拒绝；且与 AGENTS 的硬约束互相矛盾。

## 修复建议

中英两处统一改为：

```text
namespace A::B;   （文件级；块式书写会被拒绝）
```

并在括号内点明「块式 `{ … }` 会报 `a namespace is file-scoped`」。

## 验证

`grep -n 'namespace .*{' docs/glossary.md` 不再命中语法示例；术语表与 `AGENTS.md`、编译器行为三者一致。
