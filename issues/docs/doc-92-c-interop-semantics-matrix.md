# DOC-92 · C 互操作语义矩阵

| 项 | 值 |
| --- | --- |
| 模块 | docs（C 互操作） |
| 定性 | 文档缺口 |
| 严重度 | Medium |
| 锚点 | v0.88.3（2026-11-22，外部架构评估） |
| 文件 | [guide-for-c-programmers](../../docs/guide-for-c-programmers.md)、[stable-subset](../../docs/stable-subset.md)、[language-spec](../../docs/language-spec.md) |
| 状态 | open |
| 处置证据 | **已立项（v1.1；并入现有文档，不新建平行规范）** |

## 现象

“CT 与 C 亲和”是核心卖点，但哪些 C 语义被原样接受、哪些在 strict 边界被禁、哪些必须走 shim，
分散在 spec / guide / battle 里；新用户无法一页查清。

## 期望

一张 **C Interop Semantics Matrix**，并入 `guide-for-c-programmers` 附录（`stable-subset` 链过去），
每行四列：**语义项 / CT 行为 / 边界（透传 · strict 禁区 · shim）/ 权威节 + 证据**。

至少覆盖：

1. 指针与空指针；
2. `const` / `volatile`；
3. 数组与指针衰变（`T a[]` 弃用口径）；
4. struct 布局、padding、alignment；
5. enum 与整数转换；
6. bit-field；
7. 函数指针与调用约定；
8. variadic；
9. `setjmp` / `longjmp`；
10. `restrict`；
11. 宏与预处理器（strict 边界）；
12. attribute / section / interrupt；
13. inline assembly；
14. C++ 头文件兼容范围（明确“不承诺”）。

## 非目标

- 不新建一份平行规范；矩阵只做索引与判定，语义仍以 spec 节号为准；
- 不承诺 C++ 兼容；
- 不改变任何 strict 边界或生成物。

## 验收

- 每行都有权威节号与至少一条证据（测试/探针/ADR）；
- 无 `TBD` 行；无法判定的项标 `unknown` 并写阻塞依据；
- `check-docs` 链接与节号可解析；
- 无代码改动。

## 排期

v1.1；与 [DOC-91](doc-91-c-shim-contract.md) 同批评估。
