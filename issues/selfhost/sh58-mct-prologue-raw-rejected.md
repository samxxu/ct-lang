# SH-58 · `.m.ct` 前导区只允许 `#include` / `#define`，`#ct-raw` 不能省掉 shim

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 解析器） |
| 严重度 | Info |
| 锚点 | `v0.19.1`（2026-11-06） |
| 文件 | [frontend/parse/Parser.h.ct:790-796](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L790-L796) |
| 状态 | 已关闭（有意限制；文案已改进，commit `64f27f3`） |

## 现象

`.m.ct` 的前导区白名单只有 `#include` 与 `#define`。因此映射模块的实现只能落在同基名的
`<Trait>.shim.h`（`static inline`）里；想在 `.m.ct` 里用 `#ct-raw` 直接带一段 C 会被拒绝：

```text
$ ct build -I . --emit-c use_thing.ct -o out
./probe/Thing.m.ct:1:1: error: a .m.ct unit allows only #include and #define in its prologue; put the C implementation in <base>.shim.h
ctc: 1 error(s) generated
```

这与 [SH-56](sh56-map-method-arity-unchecked.md) 不同：它是**硬错误**，不存在「以为是 A、实际是 B」。
登记在这里只是因为它是 std 模块形态（「一个模块 = `.m.ct` + `.shim.h`」）的直接成因，读者和工具作者
常以为 `#ct-raw` 能把它压成单文件。

## 最小复现

```ct
/* probe/Thing.m.ct */
#ct-raw
static int helper(int n) { return n + 1; }
#ct-endraw

namespace probe;

pub trait Thing {
    int touch();
}

map trait Thing for type char * {
    touch(s) -> helper(s.len());
}
```

从任一消费方 `import probe::Thing;` 构建即可复现上面的报文。

## 影响

- 映射模块最少两个文件，shim 的实现按消费方各复制一份（`static inline`）；
- 想把 C 实现和 trait 声明放同一文件的尝试会得到一条位置正确、原因明确的错误。

## 期望行为

保持硬错误。可选改进：报文补一句替代路径（`put the implementation in Thing.shim.h`），
与 SH-55 的「拒绝文案要给替代路径」同一原则。

## 处置（2026-11-07，评审建议关闭）

关闭，行为不变：`.m.ct` 前导区禁 `#ct-raw` 是**有意限制**（std 的「`.m.ct` + `.shim.h`」形态成因），
不是待修缺陷。评审建议的「报文给出替代路径」已由 `64f27f3` 落地：

```text
error: a .m.ct unit allows only #include and #define in its prologue; put the C implementation in <base>.shim.h
```

`check-ast.sh` 的负例断言同步收紧为整句。
