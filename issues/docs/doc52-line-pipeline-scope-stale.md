# DOC-52 · 「跨行语句 / 单行函数体 / 注释续行不重写」在 ct-ast 上均不成立

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Medium（把已不存在的硬约束写成「硬要求」，会误导写法与排障方向） |
| 锚点 | commit `61e35e4`（`v0.16.1`，2026-11-01） |
| 文件 | [tutorial.md:463-470](../../docs/tutorial.md#L463-L470)、[:947-951](../../docs/tutorial.md#L947-L951)、[language-spec.md:1467](../../docs/language-spec.md#L1467)、[:1468](../../docs/language-spec.md#L1468)、[:1481](../../docs/language-spec.md#L1481) |
| 状态 | 已修（2026-11-01）：`docs/tutorial.md` §11 与 `docs/language-spec.md` §6.2 的对应条目标注「仅 L2」，删除「一行一句是硬要求」，并补「ct-ast 不保留源码注释」 |

## 现象

教程 §11「会踩的坑」开头声明「全部有 language-spec §6 的原文依据」，其中三条描述的是**按行改写**
管线的限制，而主线的 ct-ast 是 AST 管线：

| 位置 | 原文 | ct-ast 实际 |
| --- | --- | --- |
| tutorial §11-2（[:466-467](../../docs/tutorial.md#L466-L467)） | 「跨行的语句不重写……一行一句是硬要求」 | 跨行方法调用正常派发 |
| tutorial §11-3（[:468](../../docs/tutorial.md#L468)） | 「块注释只保护第一行……续行里照常改写」 | 整段注释连同其中代码一起被丢弃 |
| tutorial §11-4（[:470](../../docs/tutorial.md#L470)） | 「单行函数体不处理」 | 单行体内的方法调用照常派发 |
| spec §6.2（[:1467](../../docs/language-spec.md#L1467)） | 「跨行的方法调用语句不重写（按行处理）」 | 同上 |
| spec §6.2（[:1468](../../docs/language-spec.md#L1468)） | 块注释续行被当普通代码行改写 | ct-ast 不保留注释 |
| spec §6.2（[:1481](../../docs/language-spec.md#L1481)） | 「单行函数体不处理，与 Phase 0 的按行改写一致」 | 同上 |

这几条并非笔误：L2 冻结后仍是行重写，ct-ast 换成 AST 后自然解除了这些限制，但文档没跟。
英文侧同文同义（[:947-951](../../docs/tutorial.md#L947-L951)：「One statement per line is a hard requirement」等），
修复时中英需同改。

## 证据

跨行调用（tutorial §11-2 的反例）：

```text
$ cat x.ct
int main(void)
{
    struct P p = { .n = 1 };
    p
        .hi(2);
    if (p.n) { p.hi(3); }
    return 0;
}
$ ct x.ct -o x.c && cc -std=c99 x.c -o x && ./x
hi 2
hi 3
```

单行函数体（§11-4 的反例，函数头、构造与调用同处一行）：

```text
$ ct one.ct -o one.c ; echo $?
0
$ sed -n '/int main/,/^}/p' one.c
int main(void) {
    struct P p = { .n = 1 , .__greet_vptr = &P_Greet_vtable};
    p.__greet_vptr->hi(&p, 4);
    return 0;
}
$ ./one
hi 4
```

注释（§11-3 的反例）：

```text
$ cat cm.ct
int main(void)
{
    struct P p = { .n = 1 };
    /*
    p.hi(9);
    */
    p.hi(2);
    return 0;
}
$ sed -n '/int main(void) {/,/^}/p' cm.c
int main(void) {
    struct P p = { .n = 1 , .__greet_vptr = &P_Greet_vtable};
    p.__greet_vptr->hi(&p, 2);
    return 0;
}
```

注释整段消失、其中的 `p.hi(9);` 既没被改写也没留下痕迹；连顶层 `/* before main */`
与行尾 `/* trailing */` 也一样（实测 `c2.ct` 的生成物里一条注释都没有）。

## 影响

- 「一行一句是硬要求」会让读者写出不必要的畸形代码，或在跨行写法成功时怀疑编译器行为；
- 注释被静默丢弃这一点**没有任何文档说明**，对把版权头 / 禁用标记写在 `.ct` 里的项目是意外行为。

## 修复建议

1. 把 spec §6.2 的三条（`1467` / `1468` / `1481`）标注适用范围：**仅 L2（冻结的行重写管线）**；
   或直接移入「L2 与 ct-ast 的分叉」小节（§4 已有同类对照表）；
2. tutorial §11 第 2、3、4 条同步：改成「L2 的限制，ct-ast 不适用」，并删掉「一行一句是硬要求」；
3. 在 spec §6.2 补一条现状说明：**ct-ast 不保留源码注释**（生成物只带溯源 banner），
   若将来要保留需单独立项；
4. §11 开头「全部有 language-spec §6 的原文依据」这句随之核对，避免再次出现「文档引文档、两边都过期」。

## 验证

- 改完后 tutorial 与 spec 中不再出现「跨行不重写 / 单行不处理 / 续行被改写」的绝对表述；
- 三个探针（跨行、单行、注释）在文档里给出的结论与实测一致；
- 只动文档，九关不受影响。

## 关联

- [DOC-51](doc51-tutorial-impl-unit-import.md)：同一页 §7 的 import 后缀问题
- [DOC-31](doc31-tutorial-c-forms-unsupported.md)：同类「教程说不行、实际早支持」的前例
