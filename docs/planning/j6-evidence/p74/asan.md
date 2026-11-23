# P-7.4-7（去 `box<String>`）：A.3.1–A.3.3 + ASan/UBSan

> 命名注记（LANG-24 Stage A）：本文件是历史快照，正文保留当时的 `box<T>` 拼写；v1.0 起规范拼写为 `Box<T>`（见 docs/language-spec.md §1.2）。


baseline: c3f2e0ea

> 日期：2026-11-20；DEV（隔离原型 `/tmp/p74`，由 [run.sh](run.sh) 重建）
> 原型补丁：[prototype.patch](prototype.patch)；[D-013](../../../decisions/D-013.md) §1/§3。
> 主仓未改 `selfhost/**`、`lib/std/**`、`test/**`。`box<String>` 子项按 D-013 移出，本文件不含。

## 0. 结论

| 项 | 结果 |
| --- | --- |
| A.3.1 16 字节句柄 + 8 字节头 | **通过**：`sizeof(String)=16`、`sizeof(Str)=16`、`sizeof(header)=8`、`alignof(String)=8` |
| A.3.2 复制/Drop 协议（参数/返回/字段/`Vec<String>`/own+delete） | **通过（显式协议）**：每条位置都有 `refs=` 轨迹；ASan/UBSan 干净 |
| A.3.2 的**自动** retain 插入（按值传参/返回/字段，D-013 Q5） | **未覆盖**：属 C-6/S5a `p80_layout` 的编译器改动；本文件只证 ABI/协议，不声称自动插入已做 |
| A.3.3 字面量视图 / immortal / `String` 有 Drop、`Str` 无 Drop | **通过**：`refs=-1` 不释放；`delete` 走 Drop；`delete` 借用 `Str` 硬错 |
| ASan（`-fsanitize=address`） | **通过**：abi/trace/api 三份 stderr 0 字节；故意 UAF 必被抓 |
| UBSan（`-fsanitize=undefined`） | **通过**：trace/api 两份 stderr 0 字节 |
| 原始输出 / 退出码 | §3；harness `8 passed, 0 failed`，退出码 0 |

## 1. 原型改动

| 文件 | 改动 |
| --- | --- |
| `lib/std/Str.h.ct` | 保留 P-7.3 的 `String`/`Str` 布局与 Drop；新增 `str_slice`/`str_dup`、U16 类型、`Map<String,V>` 块（见另外三份证据） |
| `test/p74/asan/abi.ct` | A.3.1 布局 + immortal 字面量 |
| `test/p74/asan/trace.ct` | A.3.2/A.3.3 的 refs 轨迹（参数、返回、字段、Vec、own/delete、字面量） |
| `test/p74/asan/uaf_probe.ct` | ASan 灵敏度探针（故意释放后读） |
| `test/p74/asan/neg_borrow_no_drop.ct` | 借用 `Str` 无 Drop 的负例 |

`trace.ct` 用**显式**协议：保留 by-value 句柄的 callee 调 `retain()`，调用方在丢弃自己那份时
`release()`；这正是 A.3.2 的 ABI 语义。自动插入（D-013 §3 的便利语义）是 C-6 在 S5a 的
`p80_layout` 里要落的产品行为，本隔离原型不改这块编译器逻辑。

## 2. 命令

```console
$ cd /tmp/p74-evidence
$ CT_STD_DIR=$PWD/lib/std test/p74/.build/ct-ast --allow-c-boundary \
      test/p74/asan/abi.ct -o /tmp/abi.c
$ cc -Wall -Wextra -std=c99 /tmp/abi.c -o /tmp/abi && /tmp/abi

$ CT_STD_DIR=$PWD/lib/std test/p74/.build/ct-ast --allow-c-boundary \
      test/p74/asan/trace.ct -o /tmp/trace.c
$ cc -Wall -Wextra -std=c99 /tmp/trace.c -o /tmp/trace && /tmp/trace

$ cc -Wall -Wextra -std=c99 -fsanitize=address -g /tmp/trace.c -o /tmp/trace_asan
$ ASAN_OPTIONS=detect_leaks=0 /tmp/trace_asan          # expect exit 0, stderr empty
$ cc -Wall -Wextra -std=c99 -fsanitize=undefined -g /tmp/trace.c -o /tmp/trace_ub
$ /tmp/trace_ub                                        # expect exit 0, stderr empty

$ CT_STD_DIR=$PWD/lib/std test/p74/.build/ct-ast --allow-c-boundary \
      test/p74/asan/uaf_probe.ct -o /tmp/uaf.c
$ cc -Wall -Wextra -std=c99 -fsanitize=address -g /tmp/uaf.c -o /tmp/uaf
$ ASAN_OPTIONS=detect_leaks=0 /tmp/uaf                  # expect non-zero + heap-use-after-free

$ CT_AST=test/p74/.build/ct-ast bash test/p74/asan.sh
```

## 3. 原始输出

### 3.1 A.3.1（abi）

```console
$ /tmp/abi
sizeof(String)=16
sizeof(Str)=16
sizeof(header)=8
alignof(String)=8 alignof(header)=4
literal_refs=-1 empty_refs=-1
literal_len=3 empty_len=0 borrow_len=3
owned_len=3 owned_refs=1
literal_after_release=-1 empty_after=-1 live=1
owned_after_release=0 live=0
$ echo $?
0
```

`cc -Wall -Wextra -std=c99` stderr 0 字节。

### 3.2 A.3.2 + A.3.3（trace）

```console
$ /tmp/trace
keep refs=1 live=1
param take_len=4 refs_after=1
keep_param refs=2 live=1
after_param_copy_release keep=1
make_local len=2 refs=1 live=2
after_local_release live=1
nonlocal refs=2 keep=2
after_src_release got=1
field refs=2 keep=2 live=1
field_after_release keep=1
vec push keep=2 vec_len=1
vec elem len=2
vec_release keep=1
after_keep_release live=0
ptr before_delete refs=1 live=1
ptr after_delete p_null=1 live=0
literal refs=-1 empty refs=-1
literal after release=-1 empty=-1
$ echo $?
0
```

轨迹与 A.3 的对应：

| 位置 | 轨迹行 | 结论 |
| --- | --- | --- |
| by-value 参数（只读） | `param take_len=4 refs_after=1` | 不额外持有；callee 只读不 retain |
| by-value 参数（保留） | `keep_param refs=2` → `after_param_copy_release keep=1` | callee 显式 `retain()`；释放自己的那份后源仍是 1 |
| 返回（本地 move） | `make_local len=2 refs=1 live=2` → `after_local_release live=1` | 返回局部句柄是 move，不额外 retain |
| 返回（非本地） | `nonlocal refs=2 keep=2` → `after_src_release got=1` | retain→return→release 的形状 |
| 字段赋值 | `field refs=2 keep=2` → `field_after_release keep=1` | 字段持有自己的一份 |
| `Vec<String>` 元素 | `vec push keep=2` → `vec_release keep=1` | 元素 glue retain/release 各一次 |
| own + delete | `ptr before_delete refs=1` → `after_delete p_null=1 live=0` | `impl Drop for String` 真被调用 |
| 字面量/空串 | `literal refs=-1 empty refs=-1`，release 后仍 -1 | immortal，不释放只读区 |

### 3.3 ASan / UBSan

```console
$ cc -Wall -Wextra -std=c99 -fsanitize=address -g /tmp/trace.c -o /tmp/trace_asan
$ ASAN_OPTIONS=detect_leaks=0 /tmp/trace_asan
$ echo $?
0
$ wc -c < /tmp/trace_asan.stderr
0
$ cc -Wall -Wextra -std=c99 -fsanitize=undefined -g /tmp/trace.c -o /tmp/trace_ub
$ /tmp/trace_ub
$ echo $?
0
$ wc -c < /tmp/trace_ub.stderr
0
```

`api_matrix/prog.ct` 在两种 sanitizer 下也各跑一次（U16 payload 是 `uint16_t *`，对齐问题最容易
在这里暴露），stderr 均 0 字节、stdout 与期望逐字节相同。

灵敏度探针（证明 ASan 真的覆盖这些分配）：

```console
$ ASAN_OPTIONS=detect_leaks=0 /tmp/uaf
=================================================================
==6351==ERROR: AddressSanitizer: heap-use-after-free on address 0x6020000009b8 ...
READ of size 1 at 0x6020000009b8 thread T0
SUMMARY: AddressSanitizer: heap-use-after-free ...
$ echo $?
134
```

### 3.4 负例（借用 `Str` 无 Drop）

```console
$ test/p74/.build/ct-ast --allow-c-boundary test/p74/asan/neg_borrow_no_drop.ct -o /tmp/n.c
test/p74/asan/neg_borrow_no_drop.ct:7:1: error: struct 'Str' does not use trait 'Drop'
$ echo $?
1
```

### 3.5 整体 harness

```console
$ CT_AST=test/p74/.build/ct-ast bash test/p74/asan.sh
PASS abi ()
PASS trace ()
PASS trace (-fsanitize=address -g)
PASS trace (-fsanitize=undefined -g)
PASS api (-fsanitize=address -g)
PASS api (-fsanitize=undefined -g)
PASS asan sensitivity (post-release read -> heap-use-after-free)
PASS neg_borrow_no_drop (borrowed Str owns nothing, no Drop)
summary: 8 passed, 0 failed
$ echo $?
0
```

## 4. 限制（逐条，不得读成「自动 retain 已做」）

1. **自动 retain 插入未做**：by-value 复制仍是普通 struct 拷贝；callee 要保留时显式 `retain()`。
   这是 C-6（D-013 §3）在 S5a `p80_layout` 的产品工作，本文件不声称已完成。
2. **ASan 只声明 UAF/越界，不声明泄漏**：macOS 的 ASan 不支持 `detect_leaks=1`；泄漏侧用原型内的
   `ct_str_live_count()`/`ct_u16_live_count()` 计数（`live=0` 收尾）。
3. **`box<String>` 按 D-013 移出**；`Vec<String>` 已覆盖，`Map<...,String>` 的 value glue 没在本文件跑。
4. **U16 的 live 计数**只在 `ct_u16_alloc`/`release` 里维护；`Map` key 的内联分配不计入（见 `map_str.md`）。
5. 单线程；refcount 是非原子 `int`，没有线程安全承诺（D-013 §3）。
6. ASan/UBSan 是 Apple clang 21 一次实测；换编译器需重跑 `test/p74/asan.sh`。
