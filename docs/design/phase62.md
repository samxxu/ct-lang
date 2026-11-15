# Phase 62 · 容器下标可写与嵌套链

**状态：完成**（v0.61.0）

| 项 | 值 |
| --- | --- |
| 依据 | [研判](../review/ct-writable-subscript-proposal-review.md) §3 裁定（A1–A7 / W1–W22）；[提案](../proposals/ct-writable-subscript-proposal.md)；[序列](../planning/post-58-phase-sequence.md) |
| 版本位 | `version-minor: 61`；收口 **v0.61.0**（PH-60 跳过，d=1，按 AGENTS §0.3 相位表实算） |
| 只动 | `selfhost/ct-ast/frontend/parse/Expr.h.ct`、`TypeCheck.h.ct`、`frontend/sym/Symbols.h.ct`、`backend/emit/Emitter.h.ct`、`test/ast/**`、`docs/**` |
| 不碰 | `selfhost/l0/**`、`selfhost/l1/**`、`selfhost/l2/**`、`golden/**`、外部包仓 |

## 1. 目标

只做**语句级赋值**的语法糖：

```ct
m[k] = v;              /* Map put */
v[i] = x;              /* Vec set，i >= len 补齐再写 */
doc["a"]["b"] = 1;     /* 嵌套：缺中间 Map 建空，Vec 按 set 补齐 */
```

读侧 `m[k]` / `v[i]` 的类型与零值语义不变；不做真 lvalue，不做 `?[` 写。

## 2. 判据（转写研判 W1–W22）

| # | 判据 |
| --- | --- |
| W1 | `v[i]=x` 在 `i >= len` 时 `len = max(len, i+1)`，`[old_len,i)` 填零值；`i < len` 覆盖 |
| W2 | 空 Vec 写 0 位后 `len == 1`；同位置连续写 `len` 不增 |
| W3 | 负下标：常量编译错误（含位置），动态值运行期 abort（含下标与 len） |
| W4 | `set` 扩容失败 abort，消息区分 header / growth；注入夹具 |
| W5 | `m[k]=v` 缺键插入；NULL 键常量编译错误 / 动态 abort |
| W6 | 嵌套读缺键零值传播；嵌套写按容器规则补齐 |
| W7 | 嵌套写用槽指针，生成 C 不得出现 `Map_get(...)[i] = ...` |
| W8 | 自动创建的中间句柄必须 release（ASan / 引用计数夹具） |
| W9 | 洞释放走统一 `__ct_elem_release`；句柄类型按 `h==0` / `data==0` 跳过 |
| W10 | `has(i)` 对洞返回真，`get` 返回零值，`foreach` 访问洞 |
| W11 | 大跨度只 warning，不 abort / 截断；阈值 `CT_VEC_GROW_WARN_SPAN` 可覆盖 |
| W12 | 只改生成 `.c` 的 static helper，不改 `.h` / `.abi.h` |
| W13 | 更新 `test/ast/142_vec_api` 的 `set(9,1)` 期望为 `len==10` |
| W14 | 既有 `m[k]` / `v[i]` 读、`*m["a"]`、`?[` 零回归 |
| W15 | `check-all` 11 门禁全绿 |

## 3. 任务清单

| # | 任务 | 交付物 | 验收 | effort |
| --- | --- | --- | --- | --- |
| S0 | 红证夹具与读物化 | `test/ast/28x_*`、负例 | 先红，记录退出码 | S |
| S1 | `v[i]=x` | 解析/发射 | W1/W2/W3 | M |
| S2 | `set` 补齐/len/洞释放 | `Vec` 实现与 helper | W1/W9/W13 | M |
| S3 | 单层 `m[k]=v` | Map put 糖 | W5 | S |
| S4 | 嵌套读/写/补齐 | 槽指针、临时句柄 release | W6/W7/W8 | M |
| S5 | 所有权与 golden | ASan、生成 C 检查、文档 | W8–W14 | M |

每项可单独回滚；S1/S2 必须同一提交转绿，避免中间态写坏。

## 4. 前置与风险

- **前置**：`LANG-4`（下标类型错配静默空值）可并行；本卡不依赖 PH-60。
- **风险**：`set` 语义变更影响既有依赖 no-op 的代码，需 D 记录 + release note；
  嵌套临时句柄泄漏必须有 ASan 夹具；大跨度内存风险只 warning。
- **ABI**：静态 helper 只进 `.c`，不改公开头。

## 5. 回滚

按切片 `git revert`；S2 的 `set` 语义与 S1 绑定回滚，不能只退一半。

## 6. 收口记录（2026-11-16，v0.61.0）

- S1/S2/S3：Vec/Map 单层写、`Vec::set` 补齐/负下标/扩容 abort；
- S4：嵌套 Map 写读（`Map::at` 槽指针 + `N_DEREF`），`285_nested_map_write` 输出 7；
- S5：`284_vec_hole` 覆盖洞的 has/get/release；ASan 构建下 285 无内存错误；`at` 只进 `.c` static；
  大跨度 warning 阈值 1024；
- `check-ast` 1450/0，`check-all` 11/11。
