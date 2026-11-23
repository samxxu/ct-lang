# SH-110 · 修复动态派发的一行链（SH-73）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 发射 / 动态派发） |
| 定性 | **bugfix**（所有者 2026-11-21 裁定 SH-73 为 bug） |
| 严重度 | High |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [SH-73](sh73-temp-receiver-dynamic-dispatch.md)；[外部评审 §4-A3](../../docs/reviews/2026-11-21-v088-external-review-eval.md) |
| 状态 | verified |
| 处置证据 | **accepted（2026-11-23 所有者放开：v1.0 入口优先；绿证/逐字节对照已在库，待 REV 复核后转 verified；负责人 DEV）** |

## 现象

接口值上的方法调用结果不能再作下一跳接收者：

```ct
return h.tap(1)->status();          /* 当前拒绝 */
return h.tap(1)->tap(2)->status();  /* 当前拒绝 */
return x.tuned(1).status();         /* 固有 impl 返回接口后直接接调用，也拒绝 */
```

静态宿主链（[examples/47](../../examples/47_chain_factory/src/main.ct)）可以跑；
被拒的是**动态派发路径**。

## 修复前置：判据卡

动 `Emitter` 前先写清三条，并作为本 issue 的子验收：

1. **求值顺序**：接收者表达式在每个 `->`/`.` 处只求值一次，顺序与源码从左到右一致；
2. **临时值生命周期**：接收者方法返回的接口值/结构体值物化到临时量，临时量活到整条链结束；
3. **接收者形态**：哪些 `N_MCALL` 结果可物化（值/指针/接口），哪些仍拒绝（如返回数组/函数指针）。

## 实现范围

- `selfhost/ct-ast/backend/emit/Emitter.h.ct:5021`：接收者形态判定纳入 `N_MCALL` 结果；
- `Emitter.h.ct:2326`：提升位置从“语句行首/赋值右值”扩展到链式调用的中间跳；
- 接口返回值的装箱目标推断（避免“cannot infer the type to box”）；
- `docs/language-spec.md` §4.5 / §4.10.1 / §4.21：更新允许形态与求值顺序；
- golden 与 `--emit-c` 跨编译器一致性门禁：只对包含该形态的用例更新期望。

## 验收

1. 上面三条复现全部编译、运行正确；接收者只求值一次、顺序不变；
2. `h.tap(1)->status()` 的临时接口值在 ASan 下无悬垂；
3. 静态宿主链（examples/47）行为不变；
4. 不含该形态的既有语料生成 C 逐字节不变；
5. 仍应拒绝的形态（数组/函数指针接收者等）保持硬错，并补负例；
6. 双 job（host + Linux x64）跑 `check-all`、`check-ast`、`check-warnings`、ASan/UBSan；
7. 文档同步；单提交回滚。

## 非目标

- 不放开所有表达式接收者；只放开方法调用结果作下一跳；
- 不改静态宿主链/`map` 派发；
- 不新增语法；`$name` 物化仍可用；
- 不把 SH-73 的历史分析删掉（保留为评估记录）。

## 风险

| 风险 | 缓解 |
| --- | --- |
| 求值顺序变化 | 判据卡 + 只求值一次的门禁用例 |
| 临时接口值悬垂 | ASan + 生命周期用例 |
| golden 大改 | 只更新包含新形态的用例；其余逐字节不变 |
| 与 v1-PH-0 抢窗口 | 独立 bugfix 切片，单提交回滚 |

## 关联

- [SH-73](sh73-temp-receiver-dynamic-dispatch.md)
- [examples/47_chain_factory](../../examples/47_chain_factory/src/main.ct)
- [language-spec §4.10.1](../../docs/language-spec.md#4101-链式构建器范式权威定义与两档路径)
- [DOC-86](../../issues/docs/doc-86-readme-v088-rewrite.md)：README §0.1 等本修复后再改述

## 处置（REV/REQ，2026-11-22）

**结论：`deferred`（bug 确认，v0-PH-87/88 未覆盖；落 `v1-PH-0`）。** 用干净归档 HEAD `38cd4ae4`
重建 ct-ast v0.88.2，按本条前两种形态复跑（第三种 `x.tuned(1).status()` 同属 `N_MCALL` 接收者，
由同一拒绝点覆盖），仍硬错：

```ct
trait HttpRequest {
    int status();
    HttpRequest tap(int n);
}
struct Req { int s; } use HttpRequest;
impl HttpRequest for Req {
    int status() { return self->s; }
    HttpRequest tap(int n) { self->s = self->s + n; return self; }
}
int main(void) {
    Req x; x.s = 1;
    HttpRequest h = x;
    return h.tap(1)->status();
}
```

```console
$ ct-ast build chain.ct -o out            # h.tap(1)->status()
chain.ct:27:1: error: method receiver must be a variable, an element, a call or a field chain
$ echo $?
1
$ ct-ast build chain2.ct -o out2          # h.tap(1)->tap(2)->status()
chain2.ct:27:1: error: method receiver must be a variable, an element, a call or a field chain
$ echo $?
1
```

**是否已由 v0-PH-87/88 覆盖：否。** v0-PH-87（解析器/检查器按 kind 切片）与 v0-PH-88（发射器 76 个
`em_*` 切片、`MAX_IO_CALLS` 扩容）都没有改变「`N_MCALL` 结果作接收者一律拒绝」的形态规则；
本条在 v0.88.0（`verify880` 二进制）与 v0.88.2（HEAD 重建）上同样复现。`examples/47` 的静态宿主
链仍可跑，被拒的只是动态派发路径。

**去向/触发**：独立 bugfix 切片，落 `v1-PH-0`（`v1-release-plan.md` V1-C3：SH-73 解除 +
README §0.1 三断点闭环）；负责人 DEV；High。开工前先按本条「修复前置：判据卡」写清求值顺序、
临时值生命周期、可物化形态三项，再改发射器；补 ASan 用例与「不含该形态语料逐字节不变」断言。
本批只改台账，不动 `Emitter.h.ct`。

## 处置（DEV，2026-11-23）：判据卡与红证

**判据卡**：[docs/design/sh110-dispatch-chain.md](../../docs/design/sh110-dispatch-chain.md) 先落库，钉住求值顺序、临时值
生命周期与可物化接收者形态（值/指针/接口可物化；数组/函数指针仍硬错）。

**红证（`baseline: a0ce8ef1`）。** 用该提交重建的 ct-ast 跑新探针：

```console
$ sh test/ast/p110_dispatch_chain.sh .temp/b/ct-ast
FAIL p110/chain: the three chain forms were refused
  chain.ct:24:1: error: method receiver must be a variable, an element, a call or a field chain
FAIL p110/chain: the chain was not materialised
  no __ct_tmp in the generated C
ok   dispatch_chain_compound_recv keeps its diagnostic
ok   dispatch_chain_fnptr_recv keeps its diagnostic
ok   dispatch_chain_array_recv keeps its diagnostic
$ echo $?
1
```

基线里三形态全被拒；负例已在基线给出位置化硬错，修复不得把它们放开。状态字段保持
`deferred` 不动，由 REV 复核后改词。

**绿证（`c9837490` 的红提交之后，ct-ast 重建）。** 探针全绿：

```console
$ sh test/ast/p110_dispatch_chain.sh .temp/tmp-chain/green/ct-ast
ok   three chain forms compile, run, and keep the evaluation order
ok   the chain is materialised into temporaries
ok   dispatch_chain_compound_recv keeps its diagnostic
ok   dispatch_chain_fnptr_recv keeps its diagnostic
ok   dispatch_chain_array_recv keeps its diagnostic
$ echo $?
0
```

**三形态与临时量。** `test/ast/293_dispatch_chain` 生成的 C 片段：

```c
struct HttpRequest_iface __ct_tmp0 = h.vt->tap(h.self, 1);
return __ct_tmp0.vt->status(__ct_tmp0.self);
/* two hops, then the inherent impl: */
struct HttpRequest_iface __ct_tmp1 = h.vt->tap(h.self, 2);
struct HttpRequest_iface __ct_tmp2 = __ct_tmp1.vt->tap(__ct_tmp1.self, 3);
return __ct_tmp2.vt->status(__ct_tmp2.self);
struct HttpRequest_iface __ct_tmp3 = Req_tuned(x, 4);
return __ct_tmp3.vt->status(__ct_tmp3.self);
```

**ASan/UBSan。** 同一夹具的产物在 `-fsanitize=address,undefined` 下运行，输出 `2 7 11 2 14 12`，
`asan_rc=0`，无悬垂报告。

**逐字节不变。** 用 `a0ce8ef1` 重建的基线与修复后 ct-ast 分别编译 `test/ast/*/prog.ct`、
`test/cases/*.ct`、`examples/*/src/main.ct`（排除本用例），305 个可编译单文件产物逐字节相同：
`compared=305 same=305 diff=0`。

状态：**2026-11-23 所有者放开为 `open`**。绿证与逐字节对照已在库，待 REV 复核后转 `verified`；
合入后 48 小时内触发 README §0.1 重测。

## 复核（REV，2026-11-23）

`p110_dispatch_chain`：三形态编译/运行、每跳只求值一次、负例仍硬错、ASan rc=0；
判据卡 `docs/design/sh110-dispatch-chain.md`；既有 305 语料 C 逐字节不变。
