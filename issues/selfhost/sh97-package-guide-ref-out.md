---
id: SH-97
title: "package-guide 未记录 ref/out 的 C 边界与 ABI 形态"
status: open
area: selfhost
severity: P2
opened: 2026-11-20
confirmed-by: REV-PH-78
---

# SH-97 · package-guide 缺 `ref`/`out`

## 来源

[PH-78 收口复核](../../docs/reviews/2026-11-20-phase78-rev-verdict.md) B3（E78-6 的
spec/package-guide 同步）。

## 现象

`docs/package-guide.md` 的 §5「C ABI 静态库」没有 `ref`/`out` 字样，包作者读不到
`pub int bump(ref int x)` 在 ABI 头里是 `int bump(int *);`；`p78_docs.sh` 也只断言
spec §4.68 与 tutorial §15，不检查 package-guide。

## 期望

- package-guide §5 写明 `ref`/`out` 的 C 边界：ABI 头发射普通 `T *`，调用方传
  `&value`，`out` 的定值/初始化只在 CT 源层检查；
- `p78_docs.sh` 覆盖 package-guide 的该段。

## 红证（baseline `ca3354a5`）

```console
$ CC=cc sh test/ast/p78_docs.sh
FAIL p78/docs: package-guide does not document ref/out at the C ABI boundary
exit=1
```

## 处置

（待实现提交回填：`fixed` 主张、提交 sha、绿输出。）
