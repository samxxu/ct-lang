# battle/p38-1 判决书（EDITOR）

| 字段 | 值 |
| --- | --- |
| battle | p38-1（guard 副作用接收者 + switch 嵌套 defer） |
| judge | EDITOR |
| 锚定 HEAD | `0c9320c` |
| 证据 | `battle/p38-1/verify.json` V1–V4；claim/counter 的 E1 原始输出 |
| 判决 | **A `rejected`；B 接受，按 B′ 收紧后生效；C `rejected`** |

## 0 判决

1. **A 不成立（J-1）**：`arr[pick()].area()` 在 `--runtime-checks` 下被编译器接受，运行 rc=139、stderr 空（V1）。E37-3 与 language-spec 没有排除副作用接收者；documentation 不能改变编译器的接受集，不能把 J-1 改成“有条件绿”而不勘误冻结判据。
2. **B 成立，但必须按 B′ 落地**：不能“接收者 kind 是 N_INDEX 就全拒”（会误伤 `arr[0].area()`、`gs[0].greet()`，V2），也不能“N_CALL 全拒”（会误伤已 hoist 的 `make().area()`）。B′ 规则：
   - 从接收者沿 `N_MEMBER`/`N_ARROW` 取根；若根是 `N_CALL` 且 `text3` 非空（已物化）→ 放行；未物化 → 拒绝。
   - 若根是 `N_INDEX`：只有索引/基址子树含 `N_CALL`/`N_POST`/`N_PRE`/`N_ASSIGN` 时拒绝；常量/变量下标放行。
   - 其余稳定接收者（`N_VAR`/`N_MEMBER`/`N_ARROW` 根安全）放行。
   - 拒绝文案：`runtime checks need a stable receiver; bind it to a local first`，`fail_from` 位置（`file:line:1`；列 1 是项目既有局限，J-5 按“位置存在”通过，文档注明列限制）。
   - `switch` 内 defer 保持 v1 全面禁止（含 case 内嵌套块/循环体）；补嵌套块负例。
3. **C 不成立（J-4）**：全量 hoist + case/fallthrough defer 语义 >100 行，另开 phase；当前 v1 不需要。
4. **执行条件**：B′ 必须配 3 个夹具（`arr[pick()]` 拒绝、`arr[0]`/`gs[0]` 放行、`make()` 放行）+ `p37_rt_probe`；off 产物逐字节不变；全量 `check-all` 绿；随后才可谈 v0.38.0。版本 bump 时 cache key 的 `CTC_VERSION` 变化会覆盖旧缓存策略。

## 1 判据矩阵

| 判据 | A | B′ | 依据 |
| --- | --- | --- | --- |
| J-1 安全契约 | **不成立**（V1） | **成立**（拒绝不稳定接收者；放行稳定） | V1/V2/V3 |
| J-2 E38 全绿 | 成立（不动代码） | 需全量门禁 + 新夹具 | V4；待执行 |
| J-3 off 不变 | 成立 | 成立（只在 on 分支） | V4 |
| J-4 成本 | 文档/测试多文件 | 1 文件 + 夹具/文档；无解析器大改 | V3 |
| J-5 可诊断 | 无新诊断 | `file:line:1`；列限制记录 | V3 |

## 2 反对意见保留

- A 的文档化路线不是零成本：E37-3 需勘误，且“无副作用”不足以覆盖“两次求值结果不同”的纯表达式；本庭不采纳 A。
- B′ 仍不能保护 `arr[pick()]` 之外所有动态构造；v1 以“拒绝不稳定接收者”作为前置条件，写在 language-spec。
- 本判决不改 `v0.37.0` tag；tag 内的旧缺陷另案处理。
