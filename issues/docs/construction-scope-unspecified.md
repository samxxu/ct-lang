# DOC-21 · construction.md 自称「描述现状」却未标适用编译器，且两处描述在 ct-ast 上不成立

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Low** |
| 锚点 | commit `dde0dda`（2026-10-21） |
| 文件 | [docs/construction.md:5-8](../../docs/construction.md#L5-L8)、[:16-18](../../docs/construction.md#L16-L18)、[:62](../../docs/construction.md#L62) |
| 状态 | ✅ 已修复（2026-10-21，`docs/construction.md` 补「适用范围」，字段数组条目标注 L0/L2 与 ct-ast 的分叉） |

## 现象

`docs/construction.md` 开头声明性质为「**机制说明（描述现状）**」，正文却以 L0 的实现细节为主语：

- `:16-18`：「现在的实现里，vptr 只在**一处**被写入：`try_var_decl()` 处理『行首的结构体变量声明』时…」
- `:62`：「明确不处理（保持透传，并记为限制）：…**字段数组** `Person xs[3]`」

实测：

- `try_var_decl` 只存在于 `selfhost/l0/ctc.c`（2 处），ct-ast 里**没有**这个函数；安装入口 `ct` 的对象
  构造由 `backend/emit/Init.h.ct` 负责。
- struct 类型的**数组字段**在 ct-ast 已支持（`test/acceptance` 的 `p18_struct_array_field` 是基线项，
  `docs/language-spec.md §6` 也这么写）。

## 影响

文档没有标注它描述哪一层，读者无法判断这些结论对安装入口是否成立；与 DOC-18 的「§4.8 与 §6 相反」
叠加后，会让人以为 ct-ast 也不支持数组字段。

## 修复建议

1. 在文件开头补一句适用范围，例如：「本文描述 **L0** 的构造点语义；ct-ast 的实现位置与放宽项见
   language-spec §6」。
2. `:62` 的「字段数组」条目改为「L0 / L2 不处理；ct-ast 已支持（逐元素写 vptr）」——与 DOC-18 的口径一致。

## 验证

- 全文不再出现无编译器限定的「不处理 / 仍不支持」结论。
- 文档改动不影响门禁（`bash selfhost/check-all.sh` 保持八关全绿）。
