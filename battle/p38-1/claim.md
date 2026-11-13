# battle/p38-1 主张席：B sound guard

> 席位：**REQ（主张席）**；主张方案：**B（sound guard）**；当前 HEAD：`0c9320c`。
> 环境：macOS 27.2 / arm64；`cc` = Apple clang 21.0.0（clang-2100.4.1.1）；日期 2026-11-13。
> **本文是主张书与证据，不是判决**。判决归 EDITOR（§7.9），复核归证据席；本席位未改仓库源码、测试、文档，
> 全部实验在 `/tmp/p38b`（源码只读复制），仓库内只新增本文件。
> 证据按主规范 §7.7 E1–E5 组织；夹具全文见 §7，证据席可直接复制重跑。

## 0 方案 B（含一处必要的收紧）

**落点**：`selfhost/ct-ast/backend/emit/Emitter.h.ct` 的 `N_MCALL` 派发分支，在既有「接收者种类允许清单」
（HEAD `4604`–`4609`）之后、trait 解析（`4610`）之前插入一个守卫。

**规则**（`--runtime-checks` 开启时）：

| 接收者链的 hoist 根 | 处置 |
| --- | --- |
| `N_INDEX` | 拒绝：`fail_from` 报 `runtime checks need a stable receiver; bind it to a local first` |
| `N_CALL` 且未物化（`text3` 为空） | 拒绝，同一文案 |
| `N_CALL` 且已物化（`text3` 非空，即 `__ct_tmpN`） | 放行（单次求值，已稳定） |
| `N_VAR` / `N_MEMBER` / `N_ARROW`（根不属上两类）/ `N_INTO_SELF` / `N_INTO` | 放行，与今天一致 |

关闭 `--runtime-checks` 时**零注入、零诊断**，产物逐字节不变（E1-e 实测）。

**两处必须讲清的取舍**（这是本主张的边界，也是与 question.md 字面表述的唯一差异）：

1. **不能只看接收者自身的 kind，必须看 hoist 根。** `hs[pick()].a.area()` 的接收者 kind 是 `N_MEMBER`，
   但根是 `N_INDEX`，同样把 `pick()` 求值两次（E1-b：rc=139）。因此 B 用与 `hoist_scan` 相同的根链走法
   （`Emitter.h.ct:2162-2165`，只穿过 `N_MEMBER`/`N_ARROW`）。若裁判按 question.md 字面「接收者 kind 为
   `N_INDEX` 或 `N_CALL`」判，则 **B-literal 在 chain 夹具上不满足 J-1**（会放行并段错误）；只有 B-root 满足。
   我把这点主动写出来，作为对己方方案的必要修正，而不是换方案——文件数、行数量级都不变（1 文件 / +11 行）。
2. **`N_CALL` 不应一律拒绝。** `make().area()` 已被 `hoist_scan` 物化成 `__ct_tmp0`（`Emitter.h.ct:2168-2197`，
   实测 rc=4 正常）。全拒会误伤一个当前安全且被接受的写法；只拒未物化的 `N_CALL`，用 `text3` 判据
   （`Emitter.h.ct:4600-4603`）即可。若裁判坚持 B 字面全拒，代价是多拒这一个安全形态，仍然 ≤2 文件。

**代价**：1 个文件，`+11 / -0` 行（原型 diff，见 E1-c）。

## 1 E1 — 可复制命令 + 原始输出

### E1-a 从 HEAD 构建 ct-ast（源码只读，产物全在 /tmp）

```console
$ cd /Users/samxx/dsh-ws/ct-lang
$ W=/tmp/p38b; rm -rf $W; mkdir -p $W/l2src $W/astsrc
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o $W/ctc
$ $W/ctc selfhost/l1/ctc.ct -o $W/l1.c
$ cc -Wall -Wextra -std=c99 $W/l1.c -o $W/l1
$ $W/l1 build selfhost/l2/driver.ct -o $W/l2src
$ cc -Wall -Wextra -std=c99 $W/l2src/*.c -o $W/l2
$ $W/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o $W/astsrc
$ cc -Wall -Wextra -std=c99 $W/astsrc/*.c -o $W/ct-ast
BUILD-OK
```

### E1-b HEAD 行为：`--runtime-checks` 下副作用接收者静默段错误

夹具源码见 §7（`index_side.ct` = `arr[pick()].area()`；`chain_side.ct` = `hs[pick()].a.area()`；
`call_side.ct` = `make().area()`；`plain_index.ct` = `arr[i].area()`）。原始输出（`set -x` 轨迹，未改写）：

```console
$ cd /tmp/p38b
$ ./ct-ast build --emit-c --runtime-checks fx/index_side.ct -o fx/idxdir
cc -std=c99 -I fx/idxdir fx/idxdir/index_side.c -o a.out
$ cc -Wall -Wextra -std=c99 fx/idxdir/index_side.c -o fx/idxdir/idx
$ ./fx/idxdir/idx
bash: line 15: 84182 Segmentation fault: 11  ./fx/idxdir/idx
rc=139
$ ./ct-ast build --emit-c --runtime-checks fx/chain_side.ct -o fx/chd
cc -std=c99 -I fx/chd fx/chd/chain_side.c -o a.out
$ cc -Wall -Wextra -std=c99 fx/chd/chain_side.c -o fx/chd/ch
$ ./fx/chd/ch
bash: line 15: 84188 Segmentation fault: 11  ./fx/chd/ch
rc=139
$ ./ct-ast build --emit-c --runtime-checks fx/plain_index.ct -o fx/pid
cc -std=c99 -I fx/pid fx/pid/plain_index.c -o a.out
$ cc -Wall -Wextra -std=c99 fx/pid/plain_index.c -o fx/pid/pi
$ ./fx/pid/pi
rc=7
$ ./ct-ast build --emit-c --runtime-checks fx/call_side.ct -o fx/calldir
cc -std=c99 -I fx/calldir fx/calldir/call_side.c -o a.out
$ cc -Wall -Wextra -std=c99 fx/calldir/call_side.c -o fx/calldir/call
$ ./fx/calldir/call
rc=4
```

两处 rc=139 时 **stderr 为空**：没有 `null vtable` 消息，也没有 `文件:行`。根因在产物里可直接看到
（`fx/idxdir/index_side.c`，一行内 `pick()` 出现两次，一次给 guard、一次给 `self`）：

```c
return ((struct Area_vtbl *)__ct_vt_guard((void *)(arr[pick()]).vt, __FILE__, 28, "area"))->area((arr[pick()]).self);
```

`chain_side.ct` 对应行（`hs[pick()].a.area();`，接收者 kind 是 `N_MEMBER`、根是 `N_INDEX`）：

```c
return ((struct Area_vtbl *)__ct_vt_guard((void *)(hs[pick()].a).vt, __FILE__, 30, "area"))->area((hs[pick()].a).self);
```

结论（E1 层）：J-1 的「被接受派发遇空 vtable 必须 abort 带位置」在 HEAD 上不成立于 `N_INDEX` 根接收者；
`plain_index`（`arr[i]`，无副作用）今天正确；`call_side`（`N_CALL` 已物化）今天正确。

### E1-c B 原型：/tmp 源码副本 + 11 行补丁

```console
$ cp -R selfhost/ct-ast /tmp/p38b/proto
$ # 在 Emitter.h.ct 的 4604-4609 允许清单之后插入：
$ cd /tmp/p38b && python3 - <<'PY'
p='/tmp/p38b/proto/backend/emit/Emitter.h.ct'
s=open(p).read()
anchor='''                return self->fail_from(n, "method receiver must be a variable, an element, a call or a field chain");
'''
ins=anchor+'''            if (self->runtime_checks && *self->runtime_checks) {
                int rr = self->arena->nodes[n].a;
                while (rr >= 0 && (self->arena->nodes[rr].kind == N_MEMBER
                                   || self->arena->nodes[rr].kind == N_ARROW))
                    rr = self->arena->nodes[rr].a;
                if (rr >= 0 && self->arena->nodes[rr].kind == N_INDEX)
                    return self->fail_from(n, "runtime checks need a stable receiver; bind it to a local first");
                if (rr >= 0 && self->arena->nodes[rr].kind == N_CALL
                    && !self->arena->nodes[rr].text3[0])
                    return self->fail_from(n, "runtime checks need a stable receiver; bind it to a local first");
            }
'''
s=s.replace(anchor,ins); open(p,'w').write(s); print("patched")
PY
patched
$ rm -rf protosrc && mkdir -p protosrc
$ ./l2 build -I /tmp/p38b/proto /tmp/p38b/proto/main.ct -o /tmp/p38b/protosrc
$ cc -Wall -Wextra -std=c99 /tmp/p38b/protosrc/*.c -o /tmp/p38b/ct-ast-proto
PROTO-OK
```

原型 diff（HEAD 工作树 vs /tmp 副本；`+` 行共 11，`-` 行 0）：

```diff
@@ -4607,6 +4607,17 @@
                 && rk != N_MEMBER && rk != N_ARROW && rk != N_INTO_SELF
                 && rk != N_INTO)
                 return self->fail_from(n, "method receiver must be a variable, an element, a call or a field chain");
+            if (self->runtime_checks && *self->runtime_checks) {
+                int rr = self->arena->nodes[n].a;
+                while (rr >= 0 && (self->arena->nodes[rr].kind == N_MEMBER
+                                   || self->arena->nodes[rr].kind == N_ARROW))
+                    rr = self->arena->nodes[rr].a;
+                if (rr >= 0 && self->arena->nodes[rr].kind == N_INDEX)
+                    return self->fail_from(n, "runtime checks need a stable receiver; bind it to a local first");
+                if (rr >= 0 && self->arena->nodes[rr].kind == N_CALL
+                    && !self->arena->nodes[rr].text3[0])
+                    return self->fail_from(n, "runtime checks need a stable receiver; bind it to a local first");
+            }
             if (!self->arena->nodes[n].text[0])
                 return self->fail_from(n, "cannot resolve the method trait (unknown receiver type)");
```

### E1-d 原型行为（原始输出）

```console
$ ./ct-ast-proto build --emit-c --runtime-checks fx/index_side.ct -o p_idx2
fx/index_side.ct:28:1: error: runtime checks need a stable receiver; bind it to a local first
$ ./ct-ast-proto build --emit-c --runtime-checks fx/chain_side.ct -o p_ch2
fx/chain_side.ct:30:1: error: runtime checks need a stable receiver; bind it to a local first
$ ./ct-ast-proto build --emit-c --runtime-checks fx/plain_index.ct -o p_pi2
fx/plain_index.ct:18:1: error: runtime checks need a stable receiver; bind it to a local first
$ ./ct-ast-proto build --emit-c --runtime-checks fx/call_side.ct -o p_call2
cc -std=c99 -I p_call2 p_call2/call_side.c -o a.out
$ ./p_call2/call
rc=4
$ ./ct-ast-proto build --runtime-checks --outdir p_219 test/ast/219_runtime_guard/prog.ct -o /tmp/p38b/p_219.bin
'cc' -std=c99 -I 'p_219' 'p_219/prog.c' '-o' '/tmp/p38b/p_219.bin'
$ ./p_219.bin
test/ast/219_runtime_guard/prog.ct:18: runtime check: null vtable in call to 'area'
rc=134
```

- 两个拒绝用例的退出码：`rc=1`；诊断恰一行、带 `文件:行:列: error:`；被拒时输出目录为空（未写 `.c`）。
- `make().area()` 仍构建并运行（rc=4）——收紧后的 `N_CALL` 判据没有误伤已物化形态。
- `219_runtime_guard` 原有的空 vtable 守卫仍工作：rc=134 + 位置 + `null vtable`。
- `plain_index`（`arr[i]`）被拒（rc=1）：这是 B 的**已知成本**，见 §4/E5。

三个既有探针用原型二进制重跑：

```console
$ bash test/ast/p37_rt_probe.sh /tmp/p38b/ct-ast-proto
p37_rt_probe: OK
rc=0
$ bash test/ast/p37_probe.sh /tmp/p38b/ct-ast-proto
p37_probe: OK
rc=0
$ bash test/ast/p38_probe.sh /tmp/p38b/ct-ast-proto
p38_probe: OK
rc=0
```

### E1-e 关闭开关：产物逐字节不变（HEAD 二进制 vs 原型二进制）

```console
$ for n in index_side chain_side call_side plain_index; do
>   mkdir -p oh_$n op_$n
>   ./ct-ast build --emit-c fx/$n.ct -o oh_$n
>   ./ct-ast-proto build --emit-c fx/$n.ct -o op_$n
>   cmp -s oh_$n/$n.c op_$n/$n.c; echo "off[$n] cmp rc=$?"
> done
off[index_side] cmp rc=0
off[chain_side] cmp rc=0
off[call_side] cmp rc=0
off[plain_index] cmp rc=0
$ cmp -s o219h/prog.c o219p/prog.c; echo "off[219] cmp rc=$?"
off[219] cmp rc=0
```

补充：**off 模式下 `index_side` 同样 rc=139**（`./offbin/idx_off` → `Segmentation fault: 11`，rc=139）。
这不是 B 引入的，而是 HEAD 发射器在 off 路径也把接收者写两遍（`Emitter.h.ct:4632-4637`）。
B 只承诺 J-1 的 `--runtime-checks` 范围；off 的双求值属于既有行为，不在 B 的改动面（见 §9 边界）。

### E1-f compile 模式不受影响

```console
$ ./ct-ast fx/index_side.ct -o cm_head.c && ./ct-ast-proto fx/index_side.ct -o cm_proto.c
$ cmp -s cm_head.c cm_proto.c && echo "compile-mode byte-identical"
compile-mode byte-identical
$ ./ct-ast fx/index_side.ct -o cm_head2.c; echo "compile rc=$?"
compile rc=0
```

## 2 E2 — HEAD `0c9320c` 的 `file:line` 锚点

### 2.1 支持 B 的锚点

| 锚点 | 内容（引原文关键行） | 为什么支持 B |
| --- | --- | --- |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct:4606-4609` | `if (rk != N_VAR && rk != N_INDEX && rk != N_CALL` / `&& rk != N_MEMBER && rk != N_ARROW && rk != N_INTO_SELF` / `&& rk != N_INTO)` → `fail_from(... "method receiver must be ...")` | 这是所有 iface 派发接收者的唯一收口；B 就在其后加 11 行，不动解析器/节点/产物。同类 `fail_from` 用法已在此处存在，文案风格与位置可复用。 |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct:4620-4637` | `__ct_vt_guard((void *)(` → `emit_expr(n.a)`（4624）→ `)->vt, __FILE__, %d, "area")` → `emit_expr(n.a)`（4630）→ `)->self` | guard 与调用各自 `emit_expr` 一次接收者：`arr[pick()]` 被求值两次，guard 看元素 0、调用派发元素 1。这是 rc=139 的直接根因，也是 B 要拒绝的对象。 |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct:2162-2165` | `root = nodes[n].a;` / `while (root >= 0 && (kind == N_MEMBER \|\| kind == N_ARROW)) root = nodes[root].a;` | hoist 只穿过 `N_MEMBER`/`N_ARROW` 找根；`N_INDEX` 永不物化，所以下标接收者本质上不稳定。B 用同一根链判定，保证「被拒的正是不会被物化的那类」。 |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct:4600-4603` | `if (self->arena->nodes[n].text3[0] && n != self->raw_call) { fputs(text3); return 0; }` | `text3` 非空 = 已物化为 `__ct_tmpN`，可作为「`N_CALL` 已稳定」的机械判据；B 用它避免全拒 `N_CALL`。 |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct:1257` | `if (self->runtime_checks && *self->runtime_checks) {`（`__ct_vt_guard` 定义注入处） | guard 全部注入都挂在同一个指针上；B 的判断同源，off 路径结构上不可能被改到。 |

### 2.2 不利于 B（或对 B 不利）的锚点

| 锚点 | 内容（引原文关键行） | 为什么不利于 B / 怎么处理 |
| --- | --- | --- |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct:2168-2197` | `if (nodes[root].kind == N_CALL) { ok = sym->find_func(nodes[root].text2) >= 0; ... }` → `snprintf(nodes[root].text3, MAX_TEXT, "__ct_tmp%d", ...)` | `N_CALL` 根已被物化、当前安全（实测 `make().area()` rc=4）。B 字面「`N_CALL` 一律拒」属过度拒绝。已在 §0 收紧为只拒未物化者。 |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct:4632-4637` | `else { emit_expr(n.a); ... fprintf("->vt->%s("); emit_expr(n.a); ... }` | **off 路径同样双求值**（实测 off rc=139）。B 只守住 flag 内契约；A 可据此说「sound」名不副实。回应见 §5：J-1 明确限定在 `--runtime-checks`，且 off 的既有行为不是本次增量的回归。 |
| `selfhost/ct-ast/frontend/parse/ParseSupport.h.ct:125-137` | `int fail_at(int line, const char *msg)` … `self->errcol = 1;` | emitter 侧 `fail_from` 只带 line，经 `fail_at` 后**列固定为 1**。所以 B 的诊断是 `file:line:1:`，形状满足 J-5，但不指向接收者列。属精度局限，不是编造。 |
| `battle/p38-1/question.md:18` | 「`--runtime-checks` 下拒绝接收者种类为 `N_INDEX`/`N_CALL` 的派发」 | 字面按「接收者种类」判会漏掉 `hs[pick()].a.area()`（kind=`N_MEMBER`、根=`N_INDEX`，实测 rc=139）。B-literal 不满足 J-1；B-root 才满足。这是我的方案与题面字面的差异，主动登记。 |

## 3 E3 — 可证伪预测

P1–P7 均已用 `/tmp` 原型一次性验证；P8 未跑，单独标注。「实测」列即验证结果，证据席换环境重跑应一致。

| ID | 预测（若 B 成立，命令 → 应得） | 实测 |
| --- | --- | --- |
| P1 | HEAD 二进制：`ct-ast build --emit-c --runtime-checks fx/index_side.ct` 退出 0；运行产物 **rc=139 且 stderr 为空** | ✅ rc=139，stderr 空（E1-b） |
| P2 | 打上 B-root 补丁后同命令 → **rc=1**，stderr 恰 `fx/index_side.ct:28:1: error: runtime checks need a stable receiver; bind it to a local first`，且不写 `.c` | ✅（E1-d，目录为空） |
| P3 | `hs[pick()].a.area()`（kind=`N_MEMBER`、根=`N_INDEX`）→ **rc=1**，位置 `fx/chain_side.ct:30:1` | ✅（E1-d）；**若字面 kind 判定则此条应为 rc=139，B-literal 被此条证伪** |
| P4 | 已物化 `make().area()` → 仍 rc=0 构建、运行 rc=4（B 不误伤） | ✅（E1-d） |
| P5 | off 构建 4 个夹具 + `219_runtime_guard` → 与 HEAD **逐字节相同**（`cmp` rc=0） | ✅（E1-e） |
| P6 | `219_runtime_guard` 在 `--runtime-checks` 下仍 rc=134，stderr 含 `prog.ct:18` 与 `null vtable` | ✅（E1-d） |
| P7 | 既有三个探针 `p37_rt_probe.sh` / `p37_probe.sh` / `p38_probe.sh` 以原型二进制运行均 `OK`、rc=0 | ✅（E1-d） |
| P8（未跑，预测） | `bash selfhost/check-all.sh` 全绿：flag-on 夹具只有 `219`（`a.area()`，N_VAR）与 `examples/41_runtime_checks`（`shape.area()`，N_VAR）；corpus 主循环与自举不动点均不带该 flag，不受 B 影响 | **未跑**（本席位预算内未跑全量；显式标注，不冒充通过） |

**一枪证伪 B 的条件**（见 §8）：若存在「B-root 接受、却仍双求值/静默崩溃」的夹具，或 P2/P3/P5/P6 任一条不成立，B 即不成立。

## 4 E4 — 代价量化

| 项 | 量化 |
| --- | --- |
| 改动文件数 | **1**：`selfhost/ct-ast/backend/emit/Emitter.h.ct`（≤2 满足） |
| 行数 | **+11 / -0**（原型 diff 实测；落在 `4609` 之后，含 2 个 `if` 与一个 5 行 `while`） |
| 结构改动 | 无新语法、无新 CLI、无新节点种类、无解析器改动、无 scope/emit 顺序改动 |
| on 产物 | 被拒程序不写 `.c`；被放行程序与 HEAD 的 guard 产物一致（仅 patch 点前移不改变发射内容） |
| off 产物 | 4 夹具 + `219` 逐字节相同（E1-e）；compile 模式逐字节相同（E1-f） |
| 既有门禁 | 实测 `p37_probe` / `p37_rt_probe` / `p38_probe` 全 OK；`check-all` 未跑（见 P8） |
| 回退步骤 | 删除该 11 行块，或 `git revert` 该提交；无数据/产物/缓存迁移；回退后 off/on 产物与 HEAD 完全一致 |
| 残余风险 | ① `wc -l` 无法区分「无副作用下标」：`arr[i].area()` 也会被拒（实测 rc=1），只能靠用户按文案绑定局部；② 列固定 1；③ warm `.ctcache`：若同一 outdir 已有旧产物，缓存可能跳过 emit 而绕过新诊断——负例必须用全新 outdir（版本 bump 到 0.38.0 会换 key，`tool/cache/Cache.h.ct:6` 注释与 `version` 字段） |
| 与 A / C 对比 | A = 0 行；B = 1 文件/11 行；C = 发射器物化 + case 作用域/fallthrough（>100 行，另开 phase） |

## 5 E5 — 对 A 最强论点的 steelman 与回应

**A 的原文（question.md:17）**：

> **A（接受边界）**：文档化“接收者不得有副作用”，`switch` 内（含嵌套块）一律禁止 defer；不改代码，按现状收口。

**Steelman（把 A 说到最强）**：

1. **这是已登记的 v1 边界，不是本相引入的回归。** phase38 §9.1 已把「guard 下非 hoist 副作用接收者仍按既有两次求值」列为 v1 边界；`--runtime-checks` 是调试开关、默认关闭，E37-3 的契约本来只覆盖「空 vtable 派发 abort」，而本例的 vtable 非空、只是取错元素。把它当 PH-38 的收口阻塞项，可能是扩大了解释。
2. **B 在 flag 内引入编译期硬错，属于「行为变更」，而它只覆盖一半。** 同样的双求值在 off 模式也存在（E1-e：off rc=139），B 不修 off；结果是「开 debug 开关反而编译不过、关掉照旧崩」。文档化「接收者不得有副作用」至少对两种模式一致。
3. **B 会误伤安全写法。** `arr[i].area()`（E1-d 实测被拒 rc=1）没有任何副作用，却要改写源码；这是对既有 flag 用户的 source-breaking change，而 `--runtime-checks` 的价值恰在于「不改源码就能加断言」。
4. **零代码 = 零风险、零门禁、零回退。** 文档一条限制的成本接近 0；B 要新增文案、负例、门禁段落、与 `N_CALL` 物化机制的耦合，还要在两种接收者语义之间维护一个「哪些 kind 稳定」的表。

**回应（逐条，且承认 A 对的部分）**：

1. **J-1 是本次 battle 的判据，不是我的引申。** question.md:31 明确写「任何**被接受**的 vtable 派发遇到空 vtable 必须 abort 并带 `文件:行`，不得静默段错误」，且通过方式直接点名 `arr[pick()]` 清零夹具；A 预测 rc=139、B 预测 rc=1。A 的 steelman 第 1 条实际上是在论证「J-1 不该这么写」，那是改判据，不是满足判据。§9.1 的「v1 边界」只说明它被**记录**过，不说明它满足 E37-3；把两者混为一谈正是这轮 battle 要裁的点。
2. **B 的范围与 J-1 同宽，off 不在 J-1 内。** J-1 的量化词是「`--runtime-checks` 下」；B 的 off 产物逐字节不变（E1-e）正是 J-3 的要求。若 A 认为 off 也要 sound，那是 C 或新 phase 的范围（需发射器物化），B 不冒充解决。B 的收益不是「所有构建都安全」，而是「安全开关打开时，程序不再一边声称有 guard、一边静默段错误」。
3. **误伤是保守判定的必然代价，且文案把修复路径直接写给用户。** 编译器无法在不做表达式副作用分析的前提下区分 `arr[i]` 与 `arr[pick()]`；B 选择「宁拒绝、不静默」，诊断就是 `bind it to a local first`——一条可机械执行的改法。`arr[i].area()` 被拒确实不理想；若裁判要求把误伤压到最小，可把 `N_INDEX` 判据收窄为「下标子树含 `N_CALL`/`N_MCALL`」，但那是启发式、会重新打开漏网口子，我不推荐作为 v1。
4. **B 的增量成本实测是 11 行、1 文件，A 的「零风险」并不成立：** 现状是「flag 打开时对一类被接受程序给出**错误的安全承诺**」，这是记忆安全层面的静默失败（rc=139 无消息），而不是文档措辞瑕疵。11 行换掉一个静默段错误，且三个既有探针与 off 逐字节不变（E1-d/E1-e），风险/收益比远好于 A 所述。A 的「零门禁」也只对——B 需要 1 条负例（旧实现 rc=0/新实现 rc=1），这条负例本身就是 J-5 的交付物。

## 6 判据 J-1…J-5 逐条（我方主张）

| ID | B 是否满足 | 证据 / 说明 |
| --- | --- | --- |
| J-1 E37-3 安全契约 | **满足（B-root）；B-literal 不满足** | 根为 `N_INDEX` 或未物化 `N_CALL` 的派发被拒（rc=1，带位置），不再有「被接受且静默段错误」的形态；`make().area()` 已物化故放行且安全（E1-d）。chain 夹具证明字面 kind 判定会漏（E1-b），故 B 必须按根链判。 |
| J-2 E38 全绿 | **部分举证** | `p37_probe`/`p37_rt_probe`/`p38_probe` 实测 OK；corpus 主循环与自举不动点不带 `--runtime-checks`（`check-ast.sh:507`、`5781`）；flag-on 门禁夹具均为 `N_VAR`（`test/ast/219_runtime_guard/prog.ct:18` 的 `a.area()`、`examples/41_runtime_checks/prog.ct:20` 的 `shape.area()`）。全量 `check-all` **未跑**，不冒充。 |
| J-3 不新增语法/CLI，off 产物不变 | **满足** | 无新语法/CLI/节点；off 4 夹具 + 219 逐字节相同（E1-e）；compile 模式逐字节相同（E1-f）。 |
| J-4 成本/风险 | **满足** | 1 文件、+11/−0（E1-c）；无解析器大改；删除 11 行即回退；残余风险 §4 明列。 |
| J-5 可诊断、可测试 | **基本满足** | 拒绝为 `file:line:1: error: <文案>`，恰一行、不写 `.c`；新负例：旧实现 rc=0（或运行段错误）、新实现 rc=1 且位置匹配（E1-b vs E1-d）。局限：列固定为 1（`ParseSupport.h.ct:136`），非接收者精确列。 |

## 7 夹具全文（供证据席复制）

`fx/index_side.ct`：

```c
#include <string.h>

trait Area {
    int area();
}

struct Square { int n; } use Area;

impl Area for Square {
    int area() { return self->n; }
}

int g_i = 0;

int pick(void)
{
    g_i = g_i + 1;
    return g_i - 1;
}

int main(void)
{
    Square s = { .n = 7 };
    Area arr[2];
    arr[0] = s;
    arr[1] = s;
    memset(&arr[1], 0, sizeof arr[1]);
    return arr[pick()].area();
}
```

`fx/chain_side.ct`：

```c
#include <string.h>

trait Area {
    int area();
}

struct Square { int n; } use Area;

impl Area for Square {
    int area() { return self->n; }
}

struct Holder { Area a; int pad; }

int g_i = 0;

int pick(void)
{
    g_i = g_i + 1;
    return g_i - 1;
}

int main(void)
{
    Square s = { .n = 7 };
    Holder hs[2];
    hs[0].a = s;
    hs[1].a = s;
    memset(&hs[1].a, 0, sizeof hs[1].a);
    return hs[pick()].a.area();
}
```

`fx/call_side.ct`：

```c
#include <string.h>

trait Area {
    int area();
}

struct Square { int n; } use Area;

impl Area for Square {
    int area() { return self->n; }
}

int g_i = 0;

Area make(void)
{
    Area a;
    Square s = { .n = 9 };
    g_i = g_i + 1;
    if (g_i == 1) {
        a = s;
    } else {
        memset(&a, 0, sizeof a);
    }
    return a;
}

int main(void)
{
    return make().area();
}
```

`fx/plain_index.ct`：

```c
trait Area {
    int area();
}

struct Square { int n; } use Area;

impl Area for Square {
    int area() { return self->n; }
}

int main(void)
{
    Square s = { .n = 7 };
    Area arr[2];
    arr[0] = s;
    arr[1] = s;
    int i = 0;
    return arr[i].area();
}
```

重跑骨架（与 E1 相同）：

```console
$ W=/tmp/p38b; mkdir -p $W/fx
$ # 写入上面 4 个夹具后：
$ $W/ct-ast     build --emit-c --runtime-checks $W/fx/index_side.ct -o $W/idxdir   # HEAD: rc=0
$ $W/ct-ast-proto build --emit-c --runtime-checks $W/fx/index_side.ct -o $W/pidx   # 原型: rc=1 + 位置
```

> 注：`build --emit-c` 的 `-o` 是**目录**，目录须预先存在/可为空；负例请用全新目录，避免 `.ctcache` 命中旧产物而假绿（§4 残余风险 ③）。

## 8 我方失效条件（可被证伪清单）

1. **B-root 漏网**：存在接收者根不属 `{N_INDEX, 未物化 N_CALL}`、却在 `--runtime-checks` 下被接受并双求值/静默崩溃的夹具 → J-1 不成立（这一条已在设计期抓到一次：`hs[pick()].a.area()`；B 由此改成根链判定）。
2. **off 漂移**：任一 off 产物或 compile 产物与 HEAD 不逐字节相同 → J-3 不成立。
3. **门禁被打红**：若 flag-on 的既有门禁夹具含 `N_INDEX`/`N_CALL` 根接收者，B 会把它变成 rc=1 → J-2 不成立。当前实测两处 flag-on 夹具均为 `N_VAR`；证据席可复核。
4. **缓存假绿**：负例若在 warm outdir 上命中旧产物而返回 rc=0 → 夹具无效（不是 B 错），必须换新目录。
5. **价值判断（不在证据层）**：若裁判认为「文档化已知边界」足以作为 PH-38 的 v1 收口（A），则 B 的 11 行收益被视为超范围；这要按 J-1 的原文判，而不是按风险偏好判。

## 9 边界声明

- B 只主张 **`--runtime-checks` 开启时**的编译期拒绝；不主张修复 off 模式的双求值（实测 off 也 rc=139，属发射器既有形态，超出本 battle 的 J-1 范围；要修就是 C）。
- B 对 `switch` 内 defer **维持现状**（question.md:18 的 B 也只说 guard 接收者），不涉及 L38-4 的放宽。
- B 的 `N_CALL` 判定采用「未物化才拒」的收紧版；若裁判要按字面全拒，仍满足 ≤2 文件，只是多拒一个当前安全形态。
- 本文件仅为**主张与证据**，不是判决；生效范围、是否 `upheld`、以及是否需要在 `docs/decisions/` 落决策记录，均由 EDITOR 按 §7.9/T5 裁定。
