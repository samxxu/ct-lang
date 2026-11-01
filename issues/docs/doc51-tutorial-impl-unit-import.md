# DOC-51 · 教程 §7 的跨单元示例把普通 `.ct` 当可 import 单元，照抄必失败

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **High**（教程主路径示例按字面无法构建，且与 language-spec 的明确规则相反） |
| 锚点 | commit `61e35e4`（`v0.16.1`，2026-11-01） |
| 文件 | [tutorial.md:250-266](../../docs/tutorial.md#L250-L266)、[:724-740](../../docs/tutorial.md#L724-L740)、[language-spec.md:20](../../docs/language-spec.md#L20) |
| 状态 | 已修（2026-11-01）：`docs/tutorial.md` §7 中英改为 `impl_dog.h.ct`，并补「承载 `impl` 的单元要写成 `.h.ct` 才能被 import」 |

## 现象

教程 §7 用「三个单元 + 跨单元 impl + vptr 派发」讲模块化，三个文件分别写成 `shapes.h.ct`、
`impl_dog.ct`、`main.ct`，其中 `main.ct` 写 `import impl_dog;`（[:266](../../docs/tutorial.md#L266)，
英文侧 [:740](../../docs/tutorial.md#L740)）。

ct-ast 只允许 import `.h.ct`：`language-spec.md:20` 的对照表明写「L2 接受普通 `.ct`（附加式产 `.h`），
ct-ast 拒绝并提示 `only a .h.ct unit can be imported: rename 'x.ct' to 'x.h.ct'`」。
于是照抄示例的第二步 `ct build -I . main.ct -o build` 直接失败。

## 证据

按教程三段原文（去掉与 `.h` 无关的细节）复现：

```text
$ cat main.ct
import shapes;
import impl_dog;
int main(void) { dog_get()->hi(); return 0; }

$ ct build -I /tmp/chk1 /tmp/chk1/main.ct -o /tmp/chk1/out
ctc: only a .h.ct unit can be imported: rename 'relay.ct' to 'relay.h.ct'
$ echo $?
1
```

（上例的 relay 是最小单元名；同一规则对 `impl_dog` 生效。）

把 `impl_dog.ct` 改名为 `impl_dog.h.ct`、其余不动，示例即可通过：

```text
$ ct build -I /tmp/chk5 /tmp/chk5/main.ct -o /tmp/chk5/out
cc -std=c99 /tmp/chk5/out/main.c /tmp/chk5/out/shapes.c /tmp/chk5/out/impl_dog.c -o a.out
$ echo $?
0
$ /tmp/chk5/app
woof 7
```

顺带订正一处第三方评估的偏差：该报告称「同一个 `.ct` 单元自编 `ct build` 又会被拒绝
（`cannot build a .h.ct unit`）」，实测不成立——`ct build -I <dir> <unit>.h.ct -o <out>` 返回 0
并吐出 `.c/.h`；真正被拒绝的是 **compile（单文件）模式**遇到 `import`
（`error: 'import' is not supported in compile mode`），与后缀无关。修复本条时不要照抄那句错误提示。

## 影响

- 教程是新手唯一的主线路径，这一页是模块化入口；照抄即失败会让读者以为「编译器坏了」。
- 同页的要点「跨单元只走指针 + vptr」本身正确，坏掉的只是单元后缀。

## 修复建议

1. 中文 [:250](../../docs/tutorial.md#L250) 与英文 [:724](../../docs/tutorial.md#L724) 的注释/文件名
   改成 `impl_dog.h.ct`（这是实测可行的最小改动，`.h.ct` 只多发布一个
   `pub struct Dog *dog_get(void);`，与示例语义一致）；
2. 在该页「要点」里补一句：**承载 `impl` 的单元要写成 `.h.ct` 才能被 import；普通 `.ct` 不发布接口**
   （把 `language-spec.md:20` 的规则前置到教程）；
3. 若不愿改后缀，则把 `impl` 并进 `main.ct` 并删掉 `import impl_dog;`——但那样就丢掉了本页
   「impl 与 vtable 都是 static、只在本单元可见」的教学点，推荐第 1 种。

## 验证

- 按修复后的三段源码执行 `ct build -I . main.ct -o build && cc build/*.c -o app && ./app`，
  应输出 `woof 7`；
- 中英两侧命令与输出保持一致；`bash selfhost/check-ast.sh` 与九关不受影响（只动文档）。

## 关联

- [DOC-52](doc52-line-pipeline-scope-stale.md)：同一页 §11 的另外三处过期陈述
- 规则出处：`language-spec.md:20`（import 对照表）、[§6.2](../../docs/language-spec.md#L1463)
