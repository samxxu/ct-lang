# SH-75 · 非 `self` 的局部 struct 返回接口值：装箱取局部地址，静默悬垂

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast codegen / 装箱） |
| 严重度 | **High / P0**（静默 UB：`ct`、`cc`、运行全部 rc=0，读到的值是错的） |
| 锚点 | `v0.44.1`（`fb55985c` 之后复核，2026-11-15） |
| 文件 | [Stmt.h.ct:2070-2092](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L2070-L2092)、[Emitter.h.ct:3707-3740](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3707-L3740)、[Emitter.h.ct:4818-4827](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L4818-L4827) |
| 状态 | **fixed**（`b5797cbf`，2026-11-15；回归 `test/ast/239_local_iface_return` + ASAN UAR 用例） |

## 现象

`Resp make(...)` 返回块作用域的 `Res r`，装箱发射成 `(void *)&r`：这个地址在
`return` 离开时就是被调栈帧。`ct` / `cc` / 运行都不报错，`res.status()` 读到的是
别的东西。

## 最小复现

`test/ast/239_local_iface_return/prog.ct`（节选）：

```c
trait Resp { int status(); }
struct Res { int s; } use Resp;
impl Resp for Res { int status() { return self->s; } }

Resp make(int v, void **slot) { Res r; r.s = v; *slot = (void *)&r; return r; }

int main(void) {
    void *slot = 0;
    struct Res *stale;
    Resp res = make(201, &slot);
    stale = (struct Res *)slot;
    if (res.self == slot) stale->s = 200;
    printf("%d %d\n", res.self == slot, res.status());
    return 0;
}
```

修复前（`ct-ast` rc=0、`cc` rc=0、运行 rc=0）：

```text
1 200
```

生成 C：

```c
return (struct Resp_iface){ (void *)&r, &Res_Resp_vtable };
```

期望 `0 201`（`.self` 不再等于被调栈帧，状态仍是 201）。

ASAN（编译期 `-fsanitize-address-use-after-return=always`）修复前抓到：

```text
ERROR: AddressSanitizer: stack-use-after-return ... WRITE of size 4
... in make ...
SUMMARY: AddressSanitizer: stack-use-after-return
exit 134
```

默认 ASAN 选项看不到这条（`docs/planning/requirements-pool.md` REQ-CI-2），所以
夹具里额外用 `detect_stack_use_after_return` 与编译期插桩复现。

## 根因

`maybe_box` 对局部 struct 值给出 `aux` bit0 = 0，N_BOX 发射 `&<operand>`
（[Emitter.h.ct:4818-4827](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L4818-L4827)）。
SH-74 只把 impl 的 `self` 归到指针一侧；其他局部值仍取地址。

## 修复

1. 解析 `return` 时（[Stmt.h.ct:2070-2092](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L2070-L2092)），
   在局部变量的符号行还在作用域里时，把「返回块作用域 struct 的对象装箱」
   标到 N_BOX 的 `aux` bit3（值 8）。`self` 排除（它已是指针，走 SH-74 的
   `(void *)_self`）；`static` 局部、参数、文件作用域全局都不标。
2. 发射 `return` 时（[Emitter.h.ct:3707-3740](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3707-L3740)）
   对这个标记发：

```c
{
    extern void *malloc(__SIZE_TYPE__);
    struct Res *__ct_box = (struct Res *)malloc(sizeof *__ct_box);
    *__ct_box = r;
    return (struct Resp_iface){ (void *)__ct_box, &Res_Resp_vtable };
}
```

**生命周期归谁**：堆对象归接口值本身，寿命是**整个进程**。编译器没有 owner
句柄，也没有接口析构槽（加槽会改所有 vtable / 接口 struct 的 ABI），所以不做
自动释放；这是项目既有的取舍「宁可漏放，不可错放」（`docs/memory-guide.md`）：
泄漏可被 LeakSanitizer 看见，悬垂不能。调用方**不释放**（也无处释放）；要避免
增长，就把对象放到全局/静态或由调用方持有，而不是在函数里造局部再返回。
后续若引入接口所有权标记，这里应改成显式释放。

**生成物影响**：只有「`return <块作用域 struct>;` 且函数返回接口」这一形态变化。
全量单文件夹具 253 份、模块夹具 30 份逐字节对比，仅本夹具与
`237_iface_ret_self`（它的 `send()` 也返回局部 `Res`）变化；其余 0 变化。

## 验收

- `test/ast/239_local_iface_return`：输出 `0 201`；
- `check-sanitizers.sh` 对这条夹具追加 UAR 插桩运行，必须无报告；
- `bash selfhost/check-all.sh` 11 关全绿、fixpoint 成立。

## 关联

- [SH-74](sh74-impl-iface-return-self-codegen.md)：同族，`self` 那一半
- [SH-72](sh72-iface-method-return-box.md)：让这类返回值能在调用点消费，本条才有实际危险
