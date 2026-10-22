# SH-20 · `map` 仍强制要求一个已声明的实例，命名空间级绑定不可用

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | Medium |
| 锚点 | commit `224c08f`（Batch 2 收尾，2026-10-22） |
| 文件 | [selfhost/ct-ast/frontend/parse/MapBuild.h.ct](../../selfhost/ct-ast/frontend/parse/MapBuild.h.ct)（`parse` 的 instance 段） |
| 状态 | 文档化 + 诊断改进（2026-10-22）：`void *h;` 占位宿主写入 spec，错误信息直接给出该写法；合成宿主留待语法决策 |

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

## 修复建议（若后续批次解冻语法）

两条路线，代价递增：

1. **允许省略 instance**：`map trait Writer for hal::netlib { ... }`，编译器合成一个
   `static void *__map_<trait>_<unit>` 作为宿主；装箱路径 `Writer w = netlib;` 不成立，
   只能用 `Writer w = <合成宿主>;` 或新增「命名空间即实例」的装箱语法。
2. **命名空间本身作为实例**：`Writer w; w = hal;` 之类需要新的表达式语义，超出 Batch 2 范围。

在语法未定之前，建议在 `language-spec.md` §4.10 明确写出「实例可以是 `void *` 占位变量」这一
绕法，并给一个一行示例；否则用户会以为命名空间级绑定已经支持。

## 验证

修复后：上面的 `hal/lib.ct` 必须编过；新增 `test/ast/25_map_instance_free`。
文档补丁：`language-spec.md` 中英各一节，`check-all.sh` 全绿。
