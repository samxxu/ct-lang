# SH-74 · impl 方法返回接口值时生成 `&_self`：指向被调栈帧且多一层间接

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast codegen / 装箱） |
| 严重度 | **High**（静默 UB：exit 0，指针指向已返回栈帧；实测解引用读到错误值） |
| 锚点 | `v0.44.1`（`13db6cad`，2026-11-15 复核） |
| 文件 | [Parser.h.ct:2939-2944](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2939-L2944)、[TypeCheck.h.ct:266-290](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L266-L290)、[TypeCheck.h.ct:610-612](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L610-L612)、[Emitter.h.ct:4800-4808](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L4800-L4808) |
| 状态 | **fixed**（`d6e82e25`，2026-11-15；回归 `test/ast/237_iface_ret_self`）。同族残留「返回非 `self` 的局部」已由 [SH-75](sh75-local-iface-return-dangling.md) 修复（`b5797cbf`） |

## 现象

trait 方法在 impl 内 `return self;`、且该 trait 方法声明返回同一接口类型时，生成的 C 是：

```c
struct Req *_self = (struct Req *)self;
return (struct HttpRequest_iface){ (void *)&_self, &Req_HttpRequest_vtable };
```

`_self` 是函数内的局部**指针变量**，`&_self` 是它的地址：既指向返回后失效的栈帧，又把
`self` 多套了一层间接（接口值的 `self` 字段指向 `struct Req *` 槽，而不是 `struct Req` 对象）。

## 最小复现

`/tmp/ctr/B/src/main.ct`：

```c
trait HttpResponse { int status(); }
trait HttpRequest {
    HttpRequest header(char *k, char *v);
    HttpResponse send();
}
struct Req { int s; } use HttpRequest;
struct Res { int s; } use HttpResponse;

impl HttpRequest for Req {
    HttpRequest header(char *k, char *v) { (void)k; (void)v; return self; }
    HttpResponse send() { Res r; r.s = 200; return r; }
}
impl HttpResponse for Res { int status() { return self->s; } }

int main(void) { Req x; x.s = 1; HttpRequest req = x; req.send(); return 0; }
```

```text
$ ct src/main.ct -o out.c ; echo $?
0
$ grep -n "&_self" out.c
35:    struct Req *_self = (struct Req *)self;
38:    return (struct HttpRequest_iface){ (void *)&_self, &Req_HttpRequest_vtable };
$ cc -std=c99 out.c -o out && ./out ; echo $?
0
$ cc -std=c99 -fsanitize=address -O0 out.c -o out.asan && ./out.asan ; echo $?
0
```

（`send()` 的返回值被丢弃，所以这里只证明「错误形状被无条件发射」；实际解引用见下一节。）

## 可触发路径（不是「消费即报错」）

§3 的 `HttpResponse res = req.send();` 会先报 `cannot infer the type to box`，所以文档认为
「一旦消费即悬垂」；但接口值的 `.self` 字段可以正常做字段访问，绕过了那条装箱检查：

```c
#include <stdio.h>
trait HttpRequest { HttpRequest header(char *k, char *v); int status(); }
struct Req { int s; } use HttpRequest;
impl HttpRequest for Req {
    HttpRequest header(char *k, char *v) { (void)k; (void)v; return self; }
    int status() { return self->s; }
}
int read_int(void *p) { return *(int *)p; }
int main(void) {
    Req x; x.s = 42; HttpRequest req = x;
    void *p = req.header("Accept", "application/json").self;
    printf("self-from-return = %p\n", p);
    printf("object-address   = %p\n", (void *)&x);
    printf("deref as int     = %d (expected 42)\n", read_int(p));
    return 0;
}
```

```text
$ ct src/main.ct -o out.c ; echo $?
0
$ cc -std=c99 out.c -o out && ./out ; echo $?
self-from-return = 0x16ef2e1e0
object-address   = 0x16ef2e250
deref as int     = 1861411328 (expected 42)
0
```

返回值不是 `&x`，而是 `header` 栈帧里 `_self` 槽的地址；解引用读到的是该指针的低 32 位。

## 根因

- [Parser.h.ct:2939-2944](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2939-L2944) 把 impl 内的 `self`
  登记为 `struct Req`（**无 `*`**），而发射器把它物化为指针变量 `_self`。声明类型与 C 名称不一致。
- 装箱器用 `concrete_struct(expr_type(self))` 判定源操作数是否指针
  （[TypeCheck.h.ct:266-290](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L266-L290)），拿到非指针 →
  `aux` bit0 = 0。
- [Emitter.h.ct:4800-4808](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L4800-L4808) 在 bit0 = 0 时
  发射 `&<operand>`，于是成为 `&_self`。同一路径对普通变量是正确的（`p` → `&p`、`q: T *` → `q`），
  只有 impl 的 `self` 落进错误分类。

## 影响面

- 任何「trait 方法返回本 trait（或其他接口）接口值」且实现体 `return self;` 的包都会命中；ct-http
  的 `header()` / `timeout()` / `send()` 都是这个形状。`self` 这一半已由 `d6e82e25` 修复；
  SH-72 修复后调用点消费已可达，因此**非 `self` 的局部返回**（下节「残留」）成为同族里唯一还悬垂的形态。
- 不破坏已有样例：`test/`、`examples/` 中没有任何期望产物包含 `&_self`（`test/archive/cases/22_drop.expected.c`
  的 `&_self->in` 是另一条路径）。

## 修复建议

1. **最小改动**：在 `maybe_box` 判定源操作数时，把 impl 内的 `self` 视为「已是指针」，令 `aux` bit0 = 1；
   生成 `(void *)_self`。不动 `self` 的声明类型，避免波及字段访问与其它返回路径。
2. 或者把 [Parser.h.ct:2941-2943](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2941-L2943) 的 `stype`
   补成 `"struct %s *"`；需要回归 `self->f`、`&self`、`return self` 等既有用法。
3. 顺带核对自由函数里 `return <局部 struct>;` 生成的 `&x`：那是「接口只借用对象」语义下的悬垂，
   不是本条的 `&_self` 错误，但同样应当有文档或诊断约束（另案处理，不在本条扩范围）。

## 验收

- 上述最小复现的生成物不再出现 `&_self`，而是 `(void *)_self`；
- 新增一条 ASAN 夹具（接口方法返回接口值 + 调用点消费），断言运行输出而非只看退出码；
- `bash selfhost/check-all.sh` 十一关全绿；既有 golden 零变化（`--emit-c` 一致性门禁不受影响）。

## 残留：返回非 `self` 的局部接口值

**已由 [SH-75](sh75-local-iface-return-dangling.md) 修复**（`Stmt.h.ct` 在解析期标记、`Emitter.h.ct`
在 `return` 处改发堆拷贝），本条保留原因与旧产物做对照。

`d6e82e25` 只把 impl 内的 `self` 识别为已是指针。同一条装箱路径遇到**普通局部**时仍取地址：

```c
impl Req for R {
    Resp send() {
        S s;
        s.code = 200 + self->h;
        return s;                       /* 期望 201 */
    }
}
```

```c
/* 生成的 C */
return (struct Resp_iface){ (void *)&s, &S_Resp_vtable };
```

`ct compile` rc=0、`cc` rc=0、运行 rc=0，但 `res.status()` 读到悬垂栈帧：实测输出
`status=200`（期望 `201`；UB，值不保证稳定）。自由函数工厂 `HttpRequest f(void) { … return req; }`
同样发射 `return (…){ (void *)&req, … };`。

**现状**：SH-75（`test/ast/239_local_iface_return`）已把这一半改成堆拷贝，夹具输出
`0 201`；`test/ast/237_iface_ret_self` 里的 `send()` 因此在全量对比中成为另一处预期变化。

## 关联

- [SH-72](sh72-iface-method-return-box.md)：调用点消费已修（`5ff69ac3`），本条与它无先后依赖
- [SH-73](sh73-temp-receiver-dynamic-dispatch.md)：若放开临时值接收者，会新增一条消费路径
- [docs/language-spec.md §4.10.1](../../docs/language-spec.md#L649)：逐段状态已按修复后的实测重写
- 外部来源：`ct-http/docs/review/ct-http-0.1.0-blockers.md` §5（2026-11-15 独立复核）
