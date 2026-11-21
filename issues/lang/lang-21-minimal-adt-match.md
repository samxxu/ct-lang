# LANG-21 · 最小 ADT / `match`（PH-84 需求）

| 项 | 值 |
| --- | --- |
| 模块 | lang（语言特性） |
| 定性 | 需求（v1-pre 前置语言能力） |
| 严重度 | High（重写 42.8k 行前需要） |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [v1-release-plan §2.3](../../docs/planning/v1-release-plan.md)、[D3 裁定](../../docs/reviews/2026-11-21-v1-campaign-eval.md) |
| 状态 | **reopened**（2026-11-21，REV-PH-84：typedef ADT 的别名不能作 `match` 主语；`pub typedef` 跨单元 tag 名发射非法 C。最小复现见 [REV 复核](../../docs/reviews/2026-11-21-phase84-rev-verdict.md) §3） |

## 背景与目标

ct-ast 重写要把 `node->kind` 的 tag 判别 + `switch` 换成**穷尽 `match`**。为此需要最小 ADT：
名义和类型、构造器负载、穷尽检查、变量绑定。它只为重写服务，不做通用模式匹配。

## 范围（D3-A）

- 名义和类型（sum type）声明与构造器；
- 构造器负载（定长字段；若 spike 证明需要变长负载，允许在 A 内增补该**单一**形态）；
- `match` 表达式/语句，按构造器分支并绑定负载变量；
- 穷尽检查：漏分支编译错；
- 与既有 `enum`/struct 的共存与迁移规则（不破坏既有代码）。

## 非目标（v1.1+ 增量提案）

- 泛型 ADT；
- or 模式、守卫、字面量模式、嵌套/结构体模式；
- 与 `Option`/`Result` 的替代关系（它们仍是内建 struct）。

## 验收

1. 重写切片中全部 tag 判别可**机械替换**为穷尽 `match`；
2. 漏分支进 golden 负例（编译错，给位置）；
3. 合法语料零误报；既有测试套件全绿；
4. spec/tutorial 有最小示例；冻结清单登记；
5. 若 spike 暴露 A 不足，增补单一节点形态需记录理由，不升级为泛型/全功能。

## REV 复核（2026-11-21，`d863fedb`）

**结论：reopened。** PH-84 的 E84-1/2/4/6/7/8 核心行为通过；typedef ADT 形态在
`match` 与跨单元两处失败。完整证据见
[PH-84 REV 复核](../../docs/reviews/2026-11-21-phase84-rev-verdict.md) §3。

### F1 · `Alias` 不能作 `match` 主语

spec §4.73 / 卡 D84-1 写明 `typedef enum Shape { … } Alias;` 的 tag 和别名都命名
同一个和类型；实际同单元与跨单元都拒绝别名主语：

```ct
typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;
int area(Alias a)
{
    match (a) {                       /* alias_match.ct:7:5 */
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
    }
    return 0;
}
```

```console
$ <d863fedb 归档构建>/ct-ast check alias_match.ct
alias_match.ct:7:5: error: match needs an ADT value, but 'Alias' is not an ADT
ctc: 1 error(s) generated
exit=1
$ … check alias_ptr.ct
alias_ptr.ct:5:5: error: match needs an ADT value, but 'Alias *' is not an ADT
```

### F2 · `pub typedef` 跨单元：tag 名发射非法 C

`lib/lib.h.ct` 写 `pub typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;`，
消费者用 tag 名 `Shape` 构造/匹配时，ct 接受但生成物仍写 `Shape`，头文件只有
`typedef struct lib_Shape … lib_Alias;`：

```console
$ <d863fedb>/ct-ast build --emit-c prog.ct -o out
cc -std=c99 -I out out/prog.c out/lib.c -o a.out
ct build exit=0
$ grep -n 'Shape\|Alias' out/prog.c out/lib.h
out/prog.c:6:int area(Shape);
out/prog.c:8:int area(Shape s) {
out/lib.h:9:typedef struct lib_Shape {
out/lib.h:20:} lib_Alias;
$ cc -Wall -Wextra -std=c99 out/*.c -o out/prog.bin
prog.ct:3:10: error: unknown type name 'Shape'
cc exit=1
```

**期望**：`Alias` 与 tag 同为一个和类型，二者作 `match` 主语都应通过；`pub typedef`
跨单元应发布/映射 tag 的 C 名（或编译期拒绝），不得发射非法 C。修复需补
`p84_syntax`（别名主语）与 `p84_layout`（`pub typedef` 跨单元）的最小红/绿。

## 关联

- [v1 路线](../../docs/planning/v1-release-plan.md) §2.3
- [2026-11-21 评估](../../docs/reviews/2026-11-21-v1-campaign-eval.md)
