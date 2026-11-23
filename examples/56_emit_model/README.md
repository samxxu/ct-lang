# 56_emit_model —— 机器可读模型的近相样例

| 项 | 值 |
| --- | --- |
| 能力 | `ct-ast <input> --emit-model -`（`ct.model` schema v1） |
| 源码 | `prog.ct`（一个 struct、一个函数、一次调用） |
| 门禁 | `test/run.sh` 的 near-phase 层断言 schema 与 `Point` / `add` 均在模型里 |

模型是给工具链消费者的只读投影：字段名、可见性、返回值与行号都在 JSON 中，
不改变生成 C 的字节。
