# P-7.4-2：旧 owning `Str` 仅限定名 `std::str::Str`，裸名 `Str` 是借用

baseline: c3f2e0ea

> 日期：2026-11-20；DEV（隔离原型 `/tmp/p74`，由 [run.sh](run.sh) 重建）
> 原型补丁：[prototype.patch](prototype.patch)；D-013 §1.3 要求该项以隔离原型闭合。
> 主仓未改 `selfhost/**`、`lib/std/**`、`test/**`。

## 0. 结论

| 项 | 结果 |
| --- | --- |
| 同单元并存（裸 `Str` 借用 + `std::str::Str` owning） | **通过**：build 模式与 compile 模式各一次，输出一致 |
| 限定名解析（类型、函数、方法） | **通过**：`std::str::Str`、`std::str::str_from`、`std::str::str_len`、`sub.release()` |
| 迁移正例（旧消费者只加限定名，语义不变） | **通过**：`legacy_len(std::str::Str)` 与未迁移写法同值 |
| 裸名是借用（无 `release`） | **通过**：负例硬错 `no method 'release' for type 'struct Str'` |
| 限定名指向旧类型（无借用的 `as_str`） | **通过**：负例硬错 `no method 'as_str' for type 'struct std_str_Str'` |
| 原始输出 / 退出码 | §3、§4；脚本退出码 0，4 passed / 0 failed |

## 1. 原型改动（只读原型树）

| 文件 | 改动 |
| --- | --- |
| `lib/std/StrLegacy.h.ct`（新增） | 把 HEAD 的旧 `Str.h.ct` 原样迁到 `namespace std::str;`，C 名变为 `std_str_Str`，与裸名 `Str` 不冲突 |
| `selfhost/ct-ast/frontend/module/Module.h.ct` | 内建层从 4 个文件扩到 5 个（`Vec`/`Option`/`Result`/`Str`/`StrLegacy`）；`builtin_live_for` 只在消费者源码含 `std::str` 时让旧单元存活 |
| `selfhost/ct-ast/tool/driver/Driver.h.ct` | compile 模式同样拼接第 5 个单元；解析内建层时保存并恢复 `sym->ns`，避免 `namespace std::str` 泄漏到用户单元 |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct` | builtins 数组 4→5（原实现静默丢弃第 5 个单元） |
| `test/p74/coexist/**` | 正例 + 2 个负例 + 期望输出 |

限定名解析复用了既有模块机制，没有新增名称解析分支：`namespace std::str;` 的导出类型在
`resolve_type` 里按 `std::str::Str` 命中，函数按 `Qual::fn` 命中。

## 2. 命令

```console
$ cd /tmp/p74-evidence            # run.sh 从 c3f2e0ea + prototype.patch 建出
$ CT_STD_DIR=$PWD/lib/std test/p74/.build/ct-ast build --emit-c --allow-c-boundary \
      -I . test/p74/coexist/main.ct -o /tmp/co
$ cc -Wall -Wextra -std=c99 -I /tmp/co /tmp/co/*.c -o /tmp/co/prog
$ /tmp/co/prog

$ CT_STD_DIR=$PWD/lib/std test/p74/.build/ct-ast --allow-c-boundary \
      test/p74/coexist/main.ct -o /tmp/co/merged.c      # compile 模式
$ cc -Wall -Wextra -std=c99 /tmp/co/merged.c -o /tmp/co/merged && /tmp/co/merged

$ CT_STD_DIR=$PWD/lib/std test/p74/.build/ct-ast --allow-c-boundary \
      test/p74/coexist/neg_release_view.ct -o /tmp/n.c       # 期望非 0
$ CT_STD_DIR=$PWD/lib/std test/p74/.build/ct-ast --allow-c-boundary \
      test/p74/coexist/neg_legacy_borrow_api.ct -o /tmp/n.c  # 期望非 0

$ bash test/p74/coexist.sh        # 四项一起跑，CT_AST 指向同一二进制
```

## 3. 原始输出

正例（build 模式；compile 模式输出逐字节相同）：

```console
$ /tmp/co/prog
view len=5 cp=101
legacy len=5 byte=e
legacy same=0
legacy slice len=3 first=e
legacy concat len=8
migrated sum=5 borrow sum=5
view char_len=5 view as_str len=5
$ echo $?
0
```

`cc -Wall -Wextra -std=c99` 编译 4 个产物单元（`Vec.c`/`Str.c`/`StrLegacy.c`/`main.c`），
stderr 为 0 字节；compile 模式生成的单个 `.c` 同样零警告。

负例 1（裸名 `Str` 没有 `release`，它是借用）：

```console
$ test/p74/.build/ct-ast --allow-c-boundary test/p74/coexist/neg_release_view.ct -o /tmp/n.c
test/p74/coexist/neg_release_view.ct:5:1: error: no method 'release' for type 'struct Str'
$ echo $?
1
```

负例 2（限定名解析到旧 owning 类型，没有借用 API）：

```console
$ test/p74/.build/ct-ast --allow-c-boundary test/p74/coexist/neg_legacy_borrow_api.ct -o /tmp/n.c
test/p74/coexist/neg_legacy_borrow_api.ct:7:1: error: no method 'as_str' for type 'struct std_str_Str'
$ echo $?
1
```

整体 harness：

```console
$ CT_AST=test/p74/.build/ct-ast bash test/p74/coexist.sh
PASS coexist build mode (both types, qualified names, warning-free)
PASS coexist compile mode (merged layer, warning-free)
PASS neg_release_view (rejected: no method 'release')
PASS neg_legacy_borrow_api (rejected: no method 'as_str')
summary: 4 passed, 0 failed
$ echo $?
0
```

## 4. 迁移正例的具体形状

`test/p74/coexist/main.ct` 在同一函数里同时持有两种句柄：

```ct
Str view = "hello";                        /* 裸名：借用，无 Drop */
std::str::Str owned = std::str::str_from("hello");   /* 旧 owning，限定名 */
owned.release();                           /* 旧方法仍可用 */
```

迁移正例 `legacy_len(std::str::Str s)` 只把旧签名的 `Str` 改成 `std::str::Str`，函数体
`std::str::str_len(s)` 与迁移前同值；同一单元里 `borrow_len(Str)` 走新借用，二者并存。

## 5. 限制（不得读成全量通过）

1. **兼容单元的加载是原型级**：第 5 个内建单元固定是 `lib/std/StrLegacy.h.ct`，不是产品目录布局；
   产品化时旧 `std::str::Str` 应在 ct-pkg 的 `std` 包里，本原型只证名称解析与并存机制。
2. **旧单元的存活判定是文本扫描**：`unit_src_has(path, "std::str")`；产品需要正式 import/消费清单。
3. **compile 模式的 namespace 保存/恢复是新加的原型逻辑**：`sym->ns` 在多个内建单元间保存/恢复；
   产品实现应把「每单元 namespace」做成模块层的正式属性。
4. **只测了一个旧 API 子集**（`str_from`/`str_len`/`str_slice`/`str_concat`/`str_compare`/`release`），
   没有测 `.m.ct`/shim/`Option<Str>` 等旧消费者（P-7.4-3 列清单，P-7.4-6 留 S5b）。
5. 窗口结束后删除旧类型不在本原型范围。
