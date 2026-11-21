---
id: SH-106
title: "Str 借用视图逃逸（返回局部/String owner 的视图）无 lint，悬垂只在运行期暴露"
status: open
area: selfhost
severity: P2
opened: 2026-11-21
confirmed-by: battle/ct-guide-1
---

# SH-106 · `Str` 视图逃逸没有编译期告警

## 来源

[battle/ct-guide-1 判决](../../battle/ct-guide-1/verdict.md) §3、F4/F5；
[language-spec §4.70](../../docs/language-spec.md#L2885-L2927)；
[test/ast/p79_places.sh:184](../../test/ast/p79_places.sh#L184)（`E79-6` 只覆盖 `T[]`）。

## 结论

`Str` 是借用视图（`{char *data; int len;}`，无 Drop）。当前 v0.84.1 对下列两种逃逸
**既不报错也不告警**，`ct check` / `ct check --types` 均静默：

1. 返回局部 `String` 的视图（owner 在函数出口释放）；
2. 从临时接收者取视图（临时量的 owner 在全表达式结束后释放）。

`T[]` 切片已有 `E79-6 slice escape` 警告，`Str` 没有对应检查。结果就是：C 程序员按
“借一张纸条”的心智写代码，编译器不拦，运行期读到已释放 buffer；没有 ASan 时可能静默通过。

## 复现（`ct v0.84.1`）

```ct
/* /tmp/str_escape.ct */
Str f(void)
{
    String s = str_dup("x");   /* 非 immortal：owner 在 f 出口 release */
    return s.as_str();
}

int main(void)
{
    Str v = f();
    return v.byte_at(0) == 'x' ? 0 : 1;   /* 读已释放 buffer */
}
```

```console
$ ct build /tmp/str_escape.ct
'cc' ... '.ctbuild/str_escape.c' '-o' 'a.out'     # exit 0
$ ct check /tmp/str_escape.ct
$ ct check --types /tmp/str_escape.ct
                                                  # 静默
```

同一仓库内的 `test/ast/p79_places.sh:184` 对 `T[]` 返回局部切片给出
`warning: ... slice escape`；`Str` 走不到该检查。

## 期望

- 编译期：对”返回局部 owner 的 `Str` 视图”给出与 `E79-6` 同级的 **warning**
  （文案含 `borrowed 'Str' view escapes`），不升级为硬错；
- 编译期：对“从临时接收者取视图并立即返回/存储”给出同类 warning；
- 设置 `/* ct: allow-escape */` 或显式 `retain`/`to_string` 的写法可豁免；
- 跨函数转手的形态仍归契约 + ASan（不承诺跨过程分析）。

## 非目标

- 不做完整借用检查器（D-014 / spec §4.68 已明确）；
- 不改变 `Str` 的 ABI、不引入 Drop；
- 不覆盖 `ref`/`out` 的跨过程逃逸。

## 验收

- 新探针覆盖“返回局部 String 视图”“临时接收者视图”两例，挂 `check-ast`；
- `p79_places` 的 `T[]` 行为不变；
- 文档（[guide-for-c-programmers](../../docs/guide-for-c-programmers.md) 的“残余风险诚实清单”）与告警文案一致。

## 关联

- [battle/ct-guide-1](../../battle/ct-guide-1/question.md) F4/F5
- [D-014](../../docs/decisions/D-014.md)（契约 + lint）
- [SH-101](sh101-p79-slice-element-borrow.md)（切片元素借用）
