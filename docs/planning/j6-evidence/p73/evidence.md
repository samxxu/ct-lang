# P-7.3 证据：S5 `String` / `Str` 最小垂直切片（J-6）

> 命名注记（LANG-24 Stage A）：本文件是历史快照，正文保留当时的 `box<T>` 拼写；v1.0 起规范拼写为 `Box<T>`（见 docs/language-spec.md §1.2）。


> 日期：2026-11-20
> 执行：proto-p73（隔离副本 `/tmp/p73`）
> 基线：主仓 `dff5a0dfc0ee1698d538bf95d07ce39084b75b03`（隔离副本基线提交 `9449031`）
> 原型提交：`9e533a8`（仅在 `/tmp/p73`，主仓未 commit）
> 范围：P-7.3 最小切片，不是 P-7.4 全量；**没有修改主仓源码**，主仓只落本报告与 patch 两个文件。

## 0. 结论摘要

| 项 | 结论 |
| --- | --- |
| P-7.3 最小垂直切片（String 句柄 + 字面量 `Str` + A.3.1/A.3.3） | **通过**：6 个正例、6 个负例、ASan、build 模式全部实测通过 |
| A.3.1（16 字节句柄 + 8 字节头） | **通过** |
| A.3.2（复制/Drop 协议） | **部分通过**：显式 `copy()`/`retain()`/`release()`、`Vec<String>` 元素 glue、`own`/`delete` 实测；**未覆盖**参数/返回/字段的自动 retain、`box<String>`、`Map<...,String>` |
| A.3.3（字面量视图 / immortal / String 有 Drop） | **通过** |
| 旧 `std::str::Str` | **未覆盖**：原型用新 `String`/`Str` 替换了 `lib/std/Str.h.ct`，旧 owning `Str` 及其消费者不在本轮 |
| J-6 能否据此过 P-7.3 | **可以记 P-7.3 通过（最小切片）**；不能据此把 A.3 全量或 P-7.4 记为通过 |

一句话：句柄、字面量、不可变下标、`.data`/`cstr()`、refs=-1、ASan 无 UAF 都有原始输出；缺失的是“自动复制 retain / 字段 / `box<String>`”这半张 A.3.2。

## 1. 环境与基线

```console
$ uname -m
arm64
$ cc --version
Apple clang version 21.0.0 (clang-2100.4.1.1)
Target: arm64-apple-darwin27.2.0
$ sw_vers
ProductName:            macOS
ProductVersion:         27.2.1
BuildVersion:           26B131

$ git -C /Users/samxx/dsh-ws/ct-lang rev-parse HEAD
dff5a0dfc0ee1698d538bf95d07ce39084b75b03
$ git -C /tmp/p73 log --oneline -2
9e533a8 prototype: P-7.3 String/Str minimal vertical slice
9449031 baseline copy for P-7.3 prototype
```

隔离副本由主仓 HEAD 的拷贝建立，未带 `.git`，随后在 `/tmp/p73` 内 `git init` 以便生成 patch；基线提交 `9449031` 就是主仓 `dff5a0df` 的工作树内容。

## 2. 复现命令

```console
$ rm -rf /tmp/p73
$ mkdir -p /tmp/p73
$ git -C /Users/samxx/dsh-ws/ct-lang archive dff5a0df | tar -x -C /tmp/p73
$ cd /tmp/p73
$ git apply /path/to/docs/planning/j6-evidence/p73/p73.patch
$ bash test/p73/run.sh
```

`run.sh` 自己构建 L0 → L1 → L2 → ct-ast，不依赖工作树里已有的二进制；`CT_STD_DIR=/tmp/p73/lib/std` 指向原型的内建层。主仓上只执行过 `git apply --check`（只读），没有真正应用：

```console
$ git -C /Users/samxx/dsh-ws/ct-lang apply --check /tmp/p73/p73.patch
# 退出码 0，无输出
```

## 3. 原型的改动

| 文件 | 作用 |
| --- | --- |
| `lib/std/Str.h.ct` | 新 `String`（16 字节 `{ptr,len}`，`use Drop`）、新借用 `Str`、8 字节 `ct_str_hdr`、UTF-8 基本解码、`as_str`/`data`/`cstr`/`len`/`byte_at`/`codepoint_at`/`get`/`slice`/`retain`/`release`/`copy`、`U16String` 占位类型 |
| `frontend/parse/Expr.h.ct` | `lit_coerce()`：`String` 字面量 → immortal 编译器静态块（`N_STR aux=1`），`Str` 字面量 → 借用视图（`aux=2`）；`.data` 合成为只读 `Str` 视图；裸 `String` 的 struct 拼写归一化 |
| `frontend/parse/Stmt.h.ct` | 局部/全局/赋值/`return` 的字面量绑定；`s.ptr[...]` / `.ptr =` 的不可变硬错；语句层 `assign_ok` 复位 |
| `frontend/parse/Parser.h.ct` | 文件作用域 `String g = "x"` / `Str g = "x"` 的同一绑定 |
| `frontend/type/TypeCheck.h.ct` | `N_STR` 的静态类型在 `aux=1/2` 时回答 `String`/`Str` |
| `backend/emit/Emitter.h.ct` | 每个 `String` 字面量输出 `{ ct_str_hdr h = {-1,0}; char d[...] }` 静态块；`N_STR aux=1/2` 输出对应 handle |
| `frontend/module/Module.h.ct` | `String` / `U16String` 触发内建 `Str.h.ct` 的 liveness |
| `tool/driver/Driver.h.ct` | compile 模式 `layer_wanted` 认 `String` / `U16String` |
| `test/p73/**` | 6 个正例、6 个负例、ASan 敏感度探针、`run.sh` 与 expected 输出 |

代码规模：`git diff --stat 9449031 HEAD` 为 **29 个文件、+1003/−111**（含夹具）；patch 1480 行。ABI 字节：`String`=16、`Str`=16、`ct_str_hdr`=8；每个 `String` 字面量静态块 = 8 + `sizeof(literal)`（含末尾 NUL）。

## 4. 原始输出

### 4.1 总 harness

```console
$ bash test/p73/run.sh
== toolchain ==
PASS bootstrap chain L0 -> L1 -> L2 -> ct-ast
== positives ==
PASS abi (compile + warning-free cc + expected stdout)
PASS methods (compile + warning-free cc + expected stdout)
PASS drop (compile + warning-free cc + expected stdout)
PASS cstr (compile + warning-free cc + expected stdout)
PASS vec (compile + warning-free cc + expected stdout)
PASS drop_ptr (compile + warning-free cc + expected stdout)
== build mode ==
PASS build mode (separate Str.c/drop.c, warning-free, same stdout)
== ASan drop ==
PASS drop under ASan (no UAF/overflow; live counter reaches 0)
== ASan sensitivity (expected failure) ==
PASS ASan sensitivity (deliberate post-release read -> heap-use-after-free)
== negatives ==
PASS neg_immutable (rejected: read-only subscript)
PASS neg_data_write (rejected: read-only subscript)
PASS neg_data_assign (rejected: assignment target is not assignable)
PASS neg_data_cstr (rejected: expected 'const char *', got 'struct Str')
PASS neg_utf16 (rejected: UTF-16 string literal is not implicit)
PASS neg_ptr_write (rejected: String/Str is immutable)

summary: 16 passed, 0 failed
# 退出码 0
```

### 4.2 正例输出（每项都经 `-Wall -Wextra -std=c99` 零警告编译）

`abi.ct`（`test/p73/abi.ct:10-16` 的 `_Static_assert`）：

```console
sizeof(String)=16
sizeof(Str)=16
sizeof(header)=8
literal_refs=-1 empty_refs=-1
literal_len=5 empty_len=0
header_gap=8
after_release_refs=-1 empty_refs=-1
after_release_len=5 live=0
view_refs_are_none=5
```

`methods.ct`（UTF-8 基本 1–4 字节；`s[1]` 是 2 字节 `é` 的单码点 `Str`）：

```console
len=14 char_len=9
bytes=104 195 169
cps=104 233 19990
one_len=2 one_cp=233 one_byte0=195
view_len=14 view_cp1=233 data_len=14
sub_len=2 sub_cp=233
copy_len=1 copy_refs=1 live=1
live_after=0
```

`drop.ct`（refs 轨迹；`live` 是原型内的存活堆块计数）：

```console
lit_refs=-1 live=0
lit_after_refs=-1 len=3 live=0
b_refs=1 live=1
c_refs=2 b_refs=2 live=1
b_after_refs=0 len=0 c_refs=1 live=1
c_after_refs=0 len=0 live=0
ret_refs=-1 live=0
owned_refs=1 len=3 live=1
owned_after_refs=0 live=0
```

`vec.ct`（`Vec<String>` 元素 retain/release）：

```console
before_push a=1 live=1
after_push a=2 vec_len=1 live=1
element_len=3
after_vec_release a=1 live=1
after_a_release a=0 live=0
```

`drop_ptr.ct`（`own String *` + `delete` 走 `impl Drop for String`）：

```console
before_delete refs=1 live=1
after_delete p_is_null=1 live=0
```

`cstr.ct`（子视图 `.data` 后一字节不是 NUL；`cstr()` 才补 NUL）：

```console
cstr=abc strlen=3 nul=0
sub_cstr=ab strlen=2 nul=0
data_len=2 raw_after=99
```

### 4.3 负例（全部在 ct-ast 阶段硬错，退出码非 0）

```console
$ ct-ast --allow-c-boundary neg_immutable.ct
neg_immutable.ct:6:6: error: type 'String' has a read-only subscript: declare 'void set(K, V)' in impl String
ctc: 1 error(s) generated

$ ct-ast --allow-c-boundary neg_data_write.ct
neg_data_write.ct:6:11: error: type 'Str' has a read-only subscript: declare 'void set(K, V)' in impl Str
ctc: 1 error(s) generated

$ ct-ast --allow-c-boundary neg_data_assign.ct
neg_data_assign.ct:6:12: error: assignment target is not assignable

$ ct-ast --allow-c-boundary neg_data_cstr.ct
neg_data_cstr.ct:13:20: error: type mismatch: 'c_len' argument 1: expected 'const char *', got 'struct Str'
ctc: 1 error(s) generated

$ ct-ast --allow-c-boundary neg_utf16.ct
neg_utf16.ct:5:1: error: a UTF-16 string literal is not implicit; use U16String.from_utf8()
ctc: 1 error(s) generated

$ ct-ast --allow-c-boundary neg_ptr_write.ct
neg_ptr_write.ct:6:0: error: String/Str is immutable: '.ptr' is a raw implementation field; use s[i] (read-only Str) or cstr()
ctc: 1 error(s) generated
```

### 4.4 ASan

正例 `drop.ct` 用 `-fsanitize=address -g` 编译并运行，stderr 为空，退出码 0；同时 `live` 计数从 1 回到 0。为证明 ASan 确实生效，`uaf_probe.ct` 故意保存 `a.ptr`，`a.release()` 后读该字节，ASan 必须报错：

```console
==22356==ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000978 ...
READ of size 1 at 0x602000000978 thread T0
SUMMARY: AddressSanitizer: heap-use-after-free uaf_probe.c:425 in main
```

（macOS 的 ASan 不支持 `detect_leaks=1`，会直接报 “detect_leaks is not supported on this platform”；因此泄漏侧用原型内的 `ct_str_live_count()` 计数，ASan 侧只声明 UAF/越界，不声明 leak sanitizer。）

## 5. A.3 逐项结论

| 项 | 结论 | 证据 |
| --- | --- | --- |
| P-3.1 / A.3.1 16 字节句柄 + 8 字节头 | **通过** | `sizeof(String)=16`、`sizeof(Str)=16`、`sizeof(header)=8`、`header_gap=8`；`_Static_assert` 在 `test/p73/abi.ct:10-16`；`header_size(String)=round_up(8,1)=8`（`_Alignof(String)==8`、`_Alignof(char)==1`） |
| P-3.2 / A.3.2 复制/Drop 协议 | **部分** | 显式 `copy()`/`retain()`/`release()` 轨迹见 `drop.ct`；`Vec<String>` 元素 glue 见 `vec.ct`；`own String *` + `delete` 见 `drop_ptr.ct`；ASan 正例。**未覆盖**：按值参数/返回/字段的自动 retain、`box<String>`、`Map<...,String>` |
| P-3.3 / A.3.3 字面量视图 / immortal / String 有 Drop | **通过** | `String` 字面量 `refs=-1`，`release()` 后仍为 -1 且 `live=0`；`Str` 无 `use Drop`；`String` 有 `impl Drop for String`，`delete` 实测 |
| P-3.4 `.data`/`cstr()`（任务额外要求） | **部分通过** | `.data` 是只读 `Str` 视图，无隐式 `char *`；子视图 `.data` 后字节非 NUL；`cstr()` 补 NUL；`neg_data_cstr`/`neg_data_assign`/`neg_data_write` 硬错。`printf` 场景没有做专门 lint，靠 `Str` 无 `char *` 转换 |
| P-3.5 C 边界 | **未覆盖** | 只做了 `cstr()`；`.m.ct`/shim/`.h.ct`/`extern` 的 `char *` 全链路未做 |
| P-3.6 跨仓 dry-run | **未覆盖** | 旧 `std::str::Str` 未保留，消费者清单未做 |
| P-3.7/P-3.8 UTF-16 | **未覆盖** | `U16String` 只是占位 nominal 类型；唯一行为是“字面量不隐式转换”的负例，没有 `from_utf8`/`char_code_at`/`len` code unit |

## 6. 任务清单逐项

| 任务项 | 结论 |
| --- | --- |
| 1. `String` owning 16 字节 + 8 字节头；字面量构造；`Str` 借用；`as_str()`；`.data`/`.cstr()`；`len`/`byte_at`/`codepoint_at` | **通过**（`.data` 为只读 `Str` 视图，见 §7 偏离） |
| 2. `String` 不可变；`s[i]=...` 硬错；`String[i]` 返回单码点 `Str` 视图 | **通过**（`s[1]` 返回 2 字节 `é` 视图；`s[0]='x'`、`s.data[0]='x'`、`s.ptr[0]='x'` 均硬错；ASCII 以外的 UTF-8 基本 1–4 字节已实现） |
| 3. ABI 静态断言/运行时打印；`refs=-1` 不释放；drop 后无 UAF | **通过**（`abi.ct` + `drop.ct` + ASan；`uaf_probe` 证明 ASan 会抓到释放后读） |
| 4. ≥4 正例 + ≥5 负例 | **通过**：6 个正例 + build 模式 + ASan 正例；6 个负例（不可变写、`.data` 写、`.data` 重赋值、`.data` 当 C 字符串、隐式 UTF-16、原始 `.ptr` 写） |
| 5. 旧 `std::str::Str` | **未覆盖**：原型直接替换了旧 `lib/std/Str.h.ct`；依赖旧 owning `Str` 的既有 `test/ast` 用例未回归（见 §7） |

## 7. 简化、偏离与未覆盖（不得读成“通过”）

1. **旧 `Str` 被替换**：`lib/std/Str.h.ct` 在原型里就是新 `String`/`Str`；旧 owning `Str`、`str_from`/`str_slice` 等函数、`Map<Str,V>` 的 key 块都不再存在。P-7.3 明确可跳过旧类型，但这也意味着既有测试套件没有全绿；本报告只声明 P-7.3 夹具通过。
2. **A.3.2 只到显式协议**：按值传参/返回/字段赋值是普通 struct 拷贝，**不会自动 retain**；调用方要用 `copy()`/`retain()`。`String` 的 `use Drop` 只覆盖 `own`/`delete` 和宿主字段 glue，不改变普通局部变量的复制语义。
3. **`box<String>`、`Map<...,String>` 未做**；`Vec<String>` 做了元素 retain/release（`vec.ct`）。
4. **refcount 是普通 `int`，非原子**；没有线程安全承诺。
5. **UTF-8 解码只做基本 1–4 字节**：不校验 overlong/非法序列；越界 `byte_at` 返回 0，`codepoint_at` 返回 -1；没有 `char_at` 的 `Option` 软访问。
6. **`.data` 的类型是只读 `Str` 视图**，不是 `char *`。这是相对提案拼写的原型偏离：好处是 `.data` 不能被隐式当 NUL 字符串用，`neg_data_cstr` 能硬错；代价是 `printf("%s", s.data)` 这类写法没有专门的 ct 诊断（C 侧也不会通过，因为 `Str` 是 struct）。P-7.4 需要决定最终是 `const char *` + lint，还是保留视图类型。
7. **字面量绑定只覆盖声明/赋值/`return`/全局初始化**；函数实参位置（`f("x")` 且形参是 `String`）和 struct 字段初始化器（`Record { "x" }`）没有做 expected-type 绑定。
8. **原始字段逃逸**：`s.ptr[...]` 写被硬错拦截，但 `char *p = s.ptr; p[0] = 'x';` 这种指针逃逸无法防止，属于提案 §5 的“作者责任/契约水位”。
9. **`cstr()` 返回 malloc 的副本，调用方负责 `free`**；没有所有权类型，没有 `String.from_cstr`。
10. **`U16String` 占位**：没有 UTF-16 值、工厂或方法；只保留“隐式字面量转换 = 硬错”的负例。

## 8. 可证伪预测与失败时替代方案

**若以下任一出现，本任务应判失败**（都已实测未出现）：

- `sizeof(struct String) != 16` 或 `sizeof(struct ct_str_hdr) != 8` → A.3.1 失败；
- `String s = "x"; s[0] = 'y';` 被接受 → 不可变性失败；
- 字面量 `String` 的 `refs() != -1`，或 `release()` 后 `live` 计数变化 → immortal 失败；
- `drop.ct` 的 `live` 收尾不为 0，或 ASan 报 UAF/越界 → Drop 失败；
- `U16String u = "x";` 被接受 → 隐式 UTF-16 负例失败。

**若后续要求 A.3.2 全绿**：在 `String`/`Str` 上补“按值复制自动 retain”的 glue（参数/返回/字段），并做 `box<String>`；这会引入 move/copy 语义，不能在当前最小切片里诚实声称。

**若既有测试必须全绿**：不能直接替换 `lib/std/Str.h.ct`，应把旧 owning `Str` 保留为 `std::str::Str` 限定名，新借用 `Str` 走裸名；这是 P-7.4/S5b 的范围。

## 9. Patch 与主仓落点

- patch：`docs/planning/j6-evidence/p73/p73.patch`（1480 行，基线 `dff5a0df`，`git apply --check` 已在主仓通过，退出码 0）
- 原工作树：`/tmp/p73`；原型提交 `9e533a8`；未 push、未打 tag。
- 主仓只新增 `docs/planning/j6-evidence/p73/evidence.md` 与 `docs/planning/j6-evidence/p73/p73.patch`；没有 commit，没有改源码。

## 10. J-6 判定

P-7.3 的最小判据可以记为 **通过**：`String` 16 字节句柄 + 8 字节头、字面量 `Str`、`String[i]` 单码点只读视图、`.data`/`cstr()`、`refs=-1`、Drop/ASan、6 正 6 负都有原始输出。

但 A.3.2 只到“显式协议 + Vec<String> 元素 glue”，所以：

- **不能**据此把 A.3 全量、A.3.2 全绿或 P-7.4 记为通过；
- **不能**把旧 `std::str::Str` 兼容、UTF-16、`.m.ct`/shim 跨仓 dry-run 记为已做；
- J-6 整体仍需 P-7.1a/P-7.1b、P-7.2、P-7.3 全绿，且 P-7.4 在 S5 施工卡前补齐。

## 11. rebase 到当前 HEAD（2026-11-20）

- 基线：`5736f0d5`（`v0.78.1`，PH-78 收口后）。
- 方法：在 `dff5a0df` 应用原 `p73.patch` 并提交，再 rebase 到 `5736f0d5`；无冲突。
- 复现：`sh test/p73/run.sh` → **16 passed, 0 failed**（含 ASan、build 模式、6 个负例）。
- 产物：[`p73-rebased-5736f0d5.patch`](p73-rebased-5736f0d5.patch)（`selfhost/**` + `lib/std/Str.h.ct`，8 文件，560+/111-）。
- 限定：这是 P-7.3 最小切片，替换了旧 `lib/std/Str.h.ct`，既有测试套件不会全绿；只作 PH-80 参考，不直接当 S5a 合并。
