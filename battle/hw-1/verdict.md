# battle/hw-1 判决

> **状态：`closed`**（2026-11-16；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **结论：以 A 为骨架，吸收 B 的符号面判据。** P0 先修；PH-64 扩为“freestanding + 按需单元 + allocator + const vtable”；pilot 在 PH-64 后做，不占 phase 号。

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 | **P0 独立成立；范围扩大** | 数组/`[]`/局部/文件作用域/多维全部复现坏 C；`const` 标量与数组都丢 vptr，显式派发 `run rc=139`。P0 必须含 const 标量；多维在 `ct` 阶段硬错。语义零变化，但 P0 是 fix → v0.62.1，L0/L1 的 50 个 golden 产物各变 1 行 banner。 |
| J-2 | **采 A：P0 → PH-64 → pilot** | pilot 在对象层可证明无堆 trait 程序 `-nostdlib` 可链接，但本机无目标板；H0 冻结版本会让 pilot 只验证 pre-PH-64 输出，无法验证最终契约。先把 PH-64 的可机械验收面固定，再上板验证，返工更少。 |
| J-3 | **采 B 的符号面判据，否定容器名单** | 容器名单不 sound：`Str` 在 `--alloc` 下可干净，`Option/Result` 实例化却发 `fprintf/abort`；`Vec` 还有非分配符号。验收应为“每单元 `nm -u` ⊆ 允许集”，按目标工具链固定/归一化。默认允许集只含编译器内建 + `--alloc`；容器不按名字禁用。 |
| J-4 | **采 A：const vtable 全量** | 定义 + `__vptr` + `vt` 三处成套改 const 后零告警、布局不变、跨 TU 链接/运行通过；条件 const 会让 `.h` 类型随模式变化，且没有带来 golden 优势（ct-ast 的 `.c/.h` 本就不进 golden）。代价是 7 条 gate 断言/17 个发射点，不是 golden。 |
| J-5 | **pilot 不占 phase 号；PH-64 失败即 no-go** | pilot 是验证项目；PH-64 是生成契约。失败/通过写入需求文档的退出条件，不把 pilot 当 phase。 |
| J-6 | **新需求文档必须逐条 REQ** | 每项含优先级、验收、依赖、来源、状态；不把提案里的“建议”写成“已承诺”。 |

## 2 采纳

1. **P0 patch（v0.62.1）**：数组/`[]`/const 标量/const 数组的 vptr 静态初始化；带初值数组不再发 constructor；多维 trait 数组硬错；`cc -Wall -Wextra` 零告警；只改 ct-ast，新夹具进 `test/ast`；50 个 L0/L1 banner golden 随版本更新。
2. **PH-64（v0.63.0，d=1）**：
   - `--freestanding`：不隐式拉 std 单元；不隐式带 libc/heap；无 constructor；全局 trait 数组无初值 → 硬错并给可照抄的初值形态；
   - **按需单元**：`Vec/Option/Result/Str` 不再无条件进场；只按实际使用/实例化拉取；
   - **`--alloc`**：至少映射 `malloc/free`，可选 `realloc/calloc`；是否可用由每单元 `nm -u` 与允许集决定，不按容器名单；
   - **const vtable**：定义与 `__vptr`/`vt` 成套 const；
   - 门禁新增 baremetal 段，文档三节。
3. **硬件 pilot（不占 phase）**：PH-64 收口后做 P0（UART/GPIO/状态机）→ P1（ISR/DMA）；A1–A10 验收；失败 no-go。
4. **文档边界**：CT 类型检查是部分/opt-in；目标 C 编译器 + 静态分析仍是必需；安全认证/tool qualification 另案；`layout(plain)` 暂不立语法，先把“镜像结构体不得 adopt trait”写进文档。

## 3 否定/修正

- **否定“按容器名单禁”**：`Str` 可干净、`Option/Result` 反而不干净；名单无法机械验收。
- **否定“Option/Result 是纯值、freestanding 可用”**：实例化即发 `fprintf/abort`；必须走允许集或硬错。
- **否定“条件 const”**：无 golden 收益，且跨模式头文件类型会变；全量 const 成本更低。
- **否定“四单元无条件进场”**：仅在 `CT_STD_DIR`/cwd `lib/std`/输入旁 `../lib/std` 可发现时才发；但 pilot 不能依赖这个隐式路径，PH-64 必须显式按需。
- **否定“P0 可只做数组”**：const 标量同样丢 vptr 并可段错误，必须同修。
- **修正版本**：PH-64 是 v0.63.0（MINOR 63，d=1），不是“MINOR 64，d=1”；AGENTS §0.3 的 `d` 表述须先修。

## 4 证据限制

- 无目标板/ARM 工具链：pilot 的可启动镜像与 A1–A10 目标证据只能作为需求，不在本判决中宣称已通过。
- `nm -u` 的符号名受 `-O2`/FORTIFY 影响，允许集需按工具链固定或归一化；这是 PH-64 的验收实现要求。
- P0 的 50 banner golden 是版本 token 变化，不是语义变化；收口必须区分这两类差异。
