# battle/static-dispatch-1 · 反证席（REVIEW）

| 项 | 值 |
| --- | --- |
| 主张 | 反证：R1 只能做同单元子集；R2a 已修、R2b 是设计拒绝；R3b 已被 1.16.0/PH-67 取代 |
| 基线 | HEAD `c5d42b91`（v0.65.1）；`ct` 由该提交源码自举为 `/tmp/ctbattle/ct`（`ct v0.65.1`） |
| 环境 | macOS arm64 / Apple clang；探针在 `/tmp/ctbattle`，仓库只新增 `battle/static-dispatch-1/` |
| 口径 | 只认实测产物与仓库原文；提案基线 v0.63.2 的旧句不当作现状 |

## E1 复现命令与原始输出

```console
$ cd /tmp/ctbattle
$ ./ct r1.ct -o r1.c && grep -n '__greeter_vptr' r1.c | tail -2
30:    struct Person p = { .name = "A" , .__greeter_vptr = &Person_Greeter_vtable};
31:    p.__greeter_vptr->greet(&p);

$ ./ct build /Users/samxx/dsh-ws/ct-lang/test/modules/split/main.ct \
      -I /Users/samxx/dsh-ws/ct-lang/test/modules/split --emit-c -o split >/dev/null
$ grep -n 'vptr->hi\|static void Dog_Speak_hi' split/main.c split/impl_dog.c
split/main.c:15:    __ct_tmp0->__speak_vptr->hi(__ct_tmp0);
split/impl_dog.c:16:static void Dog_Speak_hi(void *self) {

$ ./ct /Users/samxx/dsh-ws/ct-lang/test/ast/239_local_iface_return/prog.ct -o iface.c
$ cc -Wall -Wextra iface.c -o iface && ./iface
0 201
$ grep -n 'malloc' iface.c
36:        struct Res *__ct_box = (struct Res *)malloc(sizeof *__ct_box);

$ ./ct chain1.ct -o chain1.c && cc chain1.c -o chain1 && ./chain1; echo "chain1_rc=$?"
201

$ ./ct mchain.ct -o mchain.c; echo "mchain_rc=$?"
mchain.ct:9:1: error: method receiver must be a variable, an element, a call or a field chain
mchain_rc=1

$ ./ct inherent.ct -o inherent.c && grep -n 'Counter_get' inherent.c
21:    return Counter_get(&__ct_tmp0);
```

**读法**：

- `r1.c`：同单元具体接收者仍走 `p.__greeter_vptr->greet(&p)`，R1 的“现状”句成立。
- `split/main.c`：跨单元 `dog_get()` 返回 `struct Dog *`（具体），仍走 `__speak_vptr->hi`；而
  `impl_dog.c` 的 `Dog_Speak_hi` 是 `static`。所以“纯发射端直呼”在跨单元不成立。
- SH-75 夹具输出 `0 201`（不是提案写的 200），且修复方式是 `malloc` 盒子；悬垂读已消失，隐藏分配仍在。
- `chain1.ct` 的自由函数结果作接收者已经可用（生成 `__ct_tmp0`，输出 201）。
- `mchain.ct` 的“方法结果作接收者”仍被拒（SH-73），与自由函数结果不是同一条限制。
- `inherent.ct` 的固有方法结果作接收者已可用（`Counter_get(&__ct_tmp0)`）；固有 `impl` 本身就是零 vtable
  的静态方法绑定，提案“唯一的零成本派发逃生口是 `.m.ct`”不成立。

## E2 锚点与原文

| 锚点 | 原文 / 事实 | 支持 / 反对 |
| --- | --- | --- |
| [test/modules/split/main.expected.c:16](../../test/modules/split/main.expected.c#L16) | `__ct_tmp0->__speak_vptr->hi(__ct_tmp0);` | 支持 R1 的“现状”；**反对“纯发射端覆盖跨单元”** |
| [test/modules/split/impl_dog.expected.c:13](../../test/modules/split/impl_dog.expected.c#L13) | “`Dog_Speak_hi` itself stays static here -- callers dispatch through the vptr” | 跨单元方法符号不可见 |
| [selfhost/ct-ast/backend/emit/Emitter.h.ct:2407](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2407) | `hoist_rvalue` 已存在 | R2b 的机制不新，成本主要在规则而非从零造 |
| [issues/selfhost/sh75-local-iface-return-dangling.md:9](../../issues/selfhost/sh75-local-iface-return-dangling.md#L9) | “**fixed**（`b5797cbf`，2026-11-15；回归 `test/ast/239_local_iface_return`）” | **反对 R2a 的“仍未修”** |
| [README.md:62](../../README.md#L62) | “实测 `200`，期望 `201`” | **不利于己方**：README 仍是旧句，提案据此立论 |
| [issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md:8](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md#L8) | “状态：保持（有意限制）……**延后**” | R2b 是设计拒绝，不是漏实现 |
| [AGENTS.md:33](../../AGENTS.md#L33) | `spec:begin version=1.16.0` | R3b 的旧偏移模型已被 1.16.0 取代 |
| [docs/design/phase67.md:1](../../docs/design/phase67.md#L1) | “phase ID 迁移与文档漂移审查（规划卡，不执行）” | 版本/ID 收敛已有在册承接 |
| [docs/planning/v1-release-plan.md:47](../../docs/planning/v1-release-plan.md#L47) | “`v1.0.0` 是 MAJOR；按 phase-numbering-major-reset 用 `v1-PH-0`，`MINOR=0`” | 新 MAJOR 不用旧偏移 |
| [docs/roadmap.md:147](../../docs/roadmap.md#L147) | “稳定子集清单……属文档治理，不占 Phase 编号” | **R3a 仍是真缺口**（唯一对提案有利的强锚点） |
| [docs/planning/post-58-plan.md:190](../../docs/planning/post-58-plan.md#L190) | “待裁定（不自行决定）” | 提案引用的“待裁定”已部分被后续裁定覆盖 |

## E3 代价量化

- **R1 同单元**：调用点从“载入 vptr + 间接调用”改为直接调用；不改 ABI，不动符号表，代价小。可先做。
- **R1 跨单元**：必须把 `<S>_<T>_<m>` 从 `static` 改为导出（每个方法一个外部符号），或维持 vptr。
  导出会扩 C ABI 面、增符号冲突风险，且与“接口方法只经 vtable”的既有设计相反；不是“纯发射端”。
- **R1 判据**：全 golden 的 `__.*_vptr->` 无法机械区分“接口值”与“具体接收者”；`split/main` 就是一个
  “具体接收者 + 必须 vptr”的反例。J1 必须改成夹具级断言，不能做全语料 regex。
- **R2a**：悬垂读已修；硬错会破坏 `239_local_iface_return` 与 `237_iface_ret_self`（两者都靠物化返回），
  还要改 ASAN UAR 用例与文档。当前物化是显式取舍“宁可漏放，不可错放”（[SH-75](../../issues/selfhost/sh75-local-iface-return-dangling.md)）。
  `--freestanding` 已在无 `--alloc` 时硬错，嵌入式场景已有出口；托管模式要不要硬错是设计决策，不是 P0。
- **R2b**：SH-73 估计 100–300 行，且改所有动态派发调用点的临时值提升规则；会改既有 golden 的生成形状。
  提案的 J1“README 代码块原样 build”与“断点 1 仍在”自相矛盾：断点 1（`.m.ct` 不能 import `.h.ct`）不解，
  代码块就 build 不了。
- **R3a**：文档任务，不占 phase；但“硬门禁红 / 用户签字 / 任意 patch”的授权级别与 AGENTS §6/§8 的
  phase 冻结、G8、deviation 重复，必须映射到既有门禁，不能另造一套。
- **R3b**：1.16.0 已定 `v<M>-PH-<n>`、`MINOR == n`、旧号段迁移 `v0-PH-*`；PH-67 正在规划迁移。提案的
  “接受偏移并机器化 / 1.0 重对齐”已被取代，按旧模型落地会与 PN-1…PN-11 冲突。
- **R3c**：包仓索引页在外部仓；CT 的边界是“只登记、不代改”（AGENTS §9.8 DB-5 / §9.10）。本仓不能创建它。

## E4 对主张席最强论点的回应（steelman）

主张席最强的是：**R1 的 vptr 开销在 Cortex-M0 上真实；R2a 的“隐藏 malloc”确实违背零隐藏分配；R3a 的
稳定子集清单确实缺**。反证席承认这三点：

- R1 的同单元子集值得做，且不需要 ABI 变更；应把“跨单元”拆出去单独裁定。
- R2a 的“隐藏 malloc + 进程寿命盒子”是真问题；但它已被 SH-75 记录为取舍，且 `--freestanding` 已给
  嵌入式硬错出口。要改托管模式的行为，应走设计决策/迁移，不应当 P0 补丁。
- R3a 应作为文档任务受理；但三档清单的“授权级别”要复用既有门禁，不要新增第二套权限体系。

## E5 范围与风险

- 本轮只评估提案，不改 `selfhost/**`、`test/**`、`lib/**`、`docs/language-spec.md`。
- 证据限制：提案原文在 `/tmp` 副本；`test/modules/split` 的 `.expected.c` 是 v0.62.0 旧 banner，但本轮
  用 HEAD 重编的 `split/main.c` 复核了同一行为；R2b 的 README 代码块未逐字搬进夹具（断点 1 明确阻止）。
- 风险：R1 若按“全 golden”判据推进，会把跨单元夹具逼成导出方法，产生未评估的 ABI 变更；
  R2a 若硬错，会破坏两个已修夹具；R3b 若按旧偏移推进，会与 1.16.0 的编号规则打架。
