# SH-20 · `map` 曾强制要求一个已声明的实例（2026-10-22 已修）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | Medium |
| 锚点 | commit `224c08f`（Batch 2 收尾，2026-10-22） |
| 文件 | [selfhost/ct-ast/frontend/parse/MapBuild.h.ct](../../selfhost/ct-ast/frontend/parse/MapBuild.h.ct)（`parse` 的 instance 段） |
| 状态 | 已修（2026-10-22，SH-20）：`map trait T for namespace A::B { … }` + `T::A::B` 装箱，`self` 为 NULL；无需占位宿主 |

## 现象

第三方诉求 (2) 的原话是「`map` 支持命名空间级绑定，不必先造空 struct 实例」。
Batch 2 让实例可以写成限定名（`hal::uart1`），但**实例本身仍必须是已声明的变量**：

```ct
namespace hal;
trait Writer { int write(char *buf, int len); }

map trait Writer for instance hal::netlib {
    write(buf, len) -> hal_net_write;
}
```

```
$ ct build hal/lib.ct -o out
hal/lib.ct:8:43: error: map instance 'netlib' is not a declared variable
```

## 证据

| 写法 | 结果 |
| --- | --- |
| `map trait Writer for instance hal::uart1`（`struct Uart uart1;` 已声明） | 通过 |
| `map trait Writer for instance hal::netlib`（未声明） | `map instance 'netlib' is not a declared variable` |
| `map trait Writer for instance dummy` + `void *dummy;` | 通过（`void *` 可以充当实例，见 `/tmp/b2` S4） |

后一条是现行绕法：**一行 dummy 全局**。它可用，但仍是「先造实例」，且 `void *dummy` 会成为
生成物里一个无意义的符号（`static void *dummy;` 或 `extern`）。

## 影响

- 纯函数式 C 库（socket、epoll、zlib）没有「对象」可挂，绑定 trait 时必须伪造一个宿主变量。
- 生成物里多一个未使用的全局，`-Wall -Wextra` 下无害，但读者会问它是什么。
- 命名空间级的「一组函数 → 一个 trait」这种最自然的绑定形态仍然写不出来。

## 最终方案（2026-10-22 落地）

采纳「命名空间宿主 + `Trait::ns` 装箱」，**不**合成 `static void *__map_*` 宿主：

```ct
namespace hal;
pub trait Writer { int write(char *buf, int len); }
int hal_write(char *buf, int len) { return len + buf[0]; }

map trait Writer for namespace hal {
    write(buf, len) -> hal_write(buf, len);
}

Writer w = Writer::hal;      /* (struct hal_Writer_iface){ (void *)0, &hal_Writer_vtable } */
```

- 没有对象，`self` 恒为 `NULL`；被绑函数不得解引用首参（经包装函数转交）。
- 符号前缀：宿主路径 `::`→`_` 得 `h`，trait C 名为 `tr`；`tr` 以 `h_` 开头则 `p = tr`，否则
  `p = h_tr`。包装函数 `p_<方法>`、vtable `p_vtable`（上例即 `hal_Writer_write` / `hal_Writer_vtable`）。
- 命名空间宿主禁用直绑（没有 `self` 可交）：`a namespace host has no self: bind with a wrapper call`。
- `Trait::ns` 只能作接口值：`a namespace host value is only usable as an interface value`；
  找不到 map 报 `no map binds trait 'T' to namespace '<宿主路径>'`。
- 跨单元：`pub trait` 即导出 vtable（`extern` 进 `.h`，定义在声明 map 的单元），无实例可判。
- `--emit-map` 的每条 map 增加 `"host": "instance" | "namespace"`。

原「一行 `void *netlib;` 占位宿主」绕法仍然可用，但已不必要。

## 验证

- `test/ast/26_ns_host/`（单单元装箱并调用，输出 `68`）。
- `test/ast/errors/ns_host_no_map.ct`、`test/ast/errors/ns_host_direct.ct`（两条诊断的精确消息断言）。
- `test/modules/ns_host/`（`pub` trait 跨单元：`writer.h` 出 `extern`、`writer.c` 定义、
  消费单元 NULL 装箱并运行）。
- `bash selfhost/check-ast.sh` 与 `selfhost/check-warnings.sh` 全绿；`language-spec.md` §4.10 中英对称更新。
