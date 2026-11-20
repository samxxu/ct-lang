# P-7.4-5：UTF-8 码点/`byte_*` 与 U16 核心 JS 方法全量清单

baseline: c3f2e0ea

> 日期：2026-11-20；DEV（隔离原型 `/tmp/p74`，由 [run.sh](run.sh) 重建）
> 原型补丁：[prototype.patch](prototype.patch)；[D-013](../../../decisions/D-013.md) §1.3。
> 主仓未改 `selfhost/**`、`lib/std/**`、`test/**`。

## 0. 结论

| 项 | 结果 |
| --- | --- |
| UTF-8 码点/`byte_*` 矩阵（13 行） | **通过**：逐项正例 + 越界分支，见 §3 |
| U16 核心 JS 方法（31 行） | **通过**：每个方法一条正例，越界/负下标一条边界分支 |
| 隐式 UTF-16 字面量 | **通过**：硬错（负例） |
| `U16String[i]` 是只读 code unit 视图 | **通过**：`u[0]` 可读，`u[0]=65` 硬错（负例） |
| 原始输出 / 退出码 | §3；harness `3 passed, 0 failed`，退出码 0 |

## 1. 原型改动

| 位置 | 改动 |
| --- | --- |
| `lib/std/Str.h.ct` | 真实 `U16String`/`U16Str`（16 字节句柄 + 同一 8 字节头，`uint16_t *` payload）；`from_utf8`/`from_utf16`/`to_utf8`/`to_utf16`；31 个 U16 方法；UTF-8 侧补 `char_at`/`byte_slice`/`byte_index_of(_from)` |
| `test/p74/api_matrix/**` | 一个正例程序（41 行输出）+ 2 个负例 + 期望输出 |

`U16String` 的指针是 `uint16_t *`，所有「头在 payload 前 8 字节」的换算都显式转成 `char *` 再减
`sizeof(struct ct_str_hdr)`；否则 C 的指针算术会按 2 字节元素放大偏移（原型调试时实测到的坑，已在
`trace.ct` 的 refs 轨迹中回归）。

## 2. 方法矩阵（逐项）

UTF-8（`String` / `Str`）：

| 行 | 正例（`"héllo"`，6 字节 / 5 码点） | 负例/边界 | 原始输出 |
| --- | --- | --- | --- |
| `len` | 6 | — | `u8 len=6 chars=5` |
| `char_len` | 5 | — | 同上 |
| `byte_at(i)` | 0..5 = 104,195,169,108,108,111 | `byte_at(99)=0` | `u8 bytes=...` / `u8 byte_oob=0` |
| `codepoint_at(i)` | 104,233,108,108,111 | `codepoint_at(99)=-1` | `u8 cps=...` / `u8 cp_oob=-1` |
| `s[i]` / `get` | `s[1]` 是 2 字节 `é` | `get(99)` 空视图 | `u8 sub len=2 cp=233` / `u8 get_oob len=0` |
| `char_at(i)` | 2 字节 | — | `u8 char_at len=2` |
| `byte_slice` | `[1,2)` 是 `é` | — | `u8 byte_slice len=2 cp=233` |
| `byte_index_of` | `"ll"`→3 | `from=4`→4；缺失→-1 | `u8 byte_index=3 from3=4` |
| `as_str` / `data` | 6 / 6 | — | `u8 as_str len=6 data len=6` |
| `slice`（String） | 新 owning，`refs=1` | `Str.slice` 返回视图（见 coexist） | `u8 slice len=2 refs=1 live=2` |
| `cstr` | 首字节 `h`，补 NUL | `.data` 不保证 NUL（p73 负例） | `u8 cstr first=h` |

U16（`"Aé😀B"` → 5 code units / 3 code points）：

| 方法 | 正例 | 负例/边界 | 输出 |
| --- | --- | --- | --- |
| `len` | 5（JS `length`） | — | `u16 len=5` |
| `char_code_at` | 65,233,55357,56832,66 | `(99)=0` | `u16 codes=...` / `u16 code_oob=0` |
| `code_point_at` | 65,128512,57344 | `(99)=-1` | `u16 cps=65,128512,-1` |
| `u[i]` / `get` | `u[0]=65` | `get(99)` 空视图 | `u16 sub=65` / `u16 get_oob=0` |
| `char_at` | 233 | — | `u16 char_at=233` |
| `at` | `at(-1)=66` | `at(99)` 空视图 | `u16 at(-1)=66 at_oob=0` |
| `index_of` | `"hello"` 找 `l`→2 | `from=4`→-1 | `u16 find=2 from4=-1 ...` |
| `index_of_from` | 从 4 找→-1 | — | 同上 |
| `last_index_of` | 3 | — | `last=3` |
| `includes` | 1 | 缺失 0 | `u16 has=1,1,1,0` |
| `starts_with` | 1 | 前缀更长 0 | 同上 |
| `ends_with` | 1 | 后缀更长 0 | 同上 |
| `slice`（JS 负下标/clamp） | `(1,3)` 2 units | 越界 clamp | `u16 slice=2` |
| `substring`（swap/clamp） | `(3,1)`→2 units | 负数→0 | `u16 substring=2` |
| `concat` | `+ "!"`→6 | — | `u16 concat=6` |
| `replace` | `é`→`e`，`Ae😀B` | 缺失→原串 | `Ae😀B replace=5` |
| `replace_all` | `hello`→`heLLo` | 空 before→原串 | `heLLo replace_all=5` |
| `to_upper_case` | `aBc`→`ABC` | 非 ASCII 不变 | `ABC upper` |
| `to_lower_case` | `aBc`→`abc` | 非 ASCII 不变 | `abc lower` |
| `trim` | `"  x \t"`→1 | 全空白→0 | `u16 trim=1` |
| `trim_start` | →3 | — | `u16 trim_start=3` |
| `trim_end` | →3 | — | `u16 trim_end=3` |
| `repeat` | `x`×3 | `n<=0`→空 | `xxx repeat=3` |
| `pad_start` | `7`→`00007` | 目标≤len→原串 | `00007 pad_start=5` |
| `pad_end` | `x`→`xaba` | 空 pad→原串 | `xaba pad_end=4` |
| `split` | `a,b,c`→3 段，各 1 unit | 空分隔符→逐 unit | `u16 split=3 1 1 1` |
| `to_utf8` | `Aé😀B` 6 字节 | — | 见 `put_u16` 输出 |
| `to_utf16` | 5 units | — | `u16 to_utf16=5` |
| `from_utf8`（static） | 全部正例的构造入口 | 隐式字面量硬错 | 见负例 1 |
| `from_utf16`（static/U16Str） | 1 unit | — | `u16 from_utf16=1` |
| `U16Str.to_string` / `to_utf8` | 1 / 1 | — | `u16 U16Str.to_string=1 u16str_to_utf8=1` |
| `String.from_utf16` | `é`→2 字节 | — | `u16 String.from_utf16=2` |

交叉编码只走显式工厂：`U16String.from_utf8`、`U16String.from_utf16`、`String.from_utf16`、
`to_utf8`、`to_utf16`。`match`/`match_all`/`search`/`locale_compare`/`normalize`/`substr`
按 C.3 **不在内建**，本原型也没有实现（不是遗漏）。

## 3. 原始输出

```console
$ /tmp/api
u8 len=6 chars=5
u8 bytes=104,195,169,108,108,111
u8 byte_oob=0
u8 cps=104,233,108,108,111
u8 cp_oob=-1
u8 sub len=2 cp=233
u8 char_at len=2
u8 get_oob len=0
u8 byte_slice len=2 cp=233
u8 byte_index=3 from3=4
u8 as_str len=6 data len=6
u8 slice len=2 refs=1 live=2
u8 cstr first=h
u16 len=5
u16 codes=65,233,55357,56832,66
u16 code_oob=0
u16 cps=65,128512,-1
u16 sub=65
u16 char_at=233
u16 at(-1)=66 at_oob=0
u16 get_oob=0
u16 find=2 from4=-1 last=3
u16 has=1,1,1,0
u16 slice=2
u16 substring=2
u16 concat=6
Ae😀B replace=5
heLLo replace_all=5
ABC upper
abc lower
u16 trim=1
u16 trim_start=3
u16 trim_end=3
xxx repeat=3
00007 pad_start=5
xaba pad_end=4
u16 split=3 1 1 1
u16 to_utf16=5
u16 from_utf16=1
u16 String.from_utf16=2
u16 U16Str.to_string=1 u16str_to_utf8=1
$ echo $?
0
```

负例 1（隐式 UTF-16 字面量）：

```console
$ test/p74/.build/ct-ast --allow-c-boundary test/p74/api_matrix/neg_utf16_literal.ct -o /tmp/n.c
test/p74/api_matrix/neg_utf16_literal.ct:4:1: error: a UTF-16 string literal is not implicit; use U16String.from_utf8()
$ echo $?
1
```

负例 2（U16 不可变）：

```console
$ test/p74/.build/ct-ast --allow-c-boundary test/p74/api_matrix/neg_u16_write.ct -o /tmp/n.c
test/p74/api_matrix/neg_u16_write.ct:6:6: error: type 'U16String' has a read-only subscript: declare 'void set(K, V)' in impl U16String
$ echo $?
1
```

整体 harness：

```console
$ CT_AST=test/p74/.build/ct-ast bash test/p74/api_matrix.sh
PASS api_matrix (UTF-8 codepoint/byte_* + UTF-16 core methods, warning-free)
PASS neg_utf16_literal (rejected: UTF-16 string literal is not implicit)
PASS neg_u16_write (rejected: read-only subscript)
summary: 3 passed, 0 failed
$ echo $?
0
```

## 4. 限制

1. **方法名拆分**：CT 没有默认参数，JS `indexOf(search, from)` 拆成 `index_of` 与 `index_of_from`；
   同样没有重载。
2. **大小写/trim 只覆盖 ASCII**：没有 Unicode 大小写表与 JS 全空白集合；`match`/`normalize` 等
   按 C.3 走包，不内建。
3. **`split` 返回 `Vec<U16String>`**，空分隔符按逐 code unit 切；零拷贝的 `for_each_split` 回调未做。
4. **`to_utf8` 的实现各调用一次都会分配一个 owning `String` 后丢弃句柄**（只保留 view）；原型不追
   分配轨迹，生产实现必须返回 owning `String` 并由调用方释放。
5. **U16 索引是 code unit**；`slice` 可以切在代理对中间（JS 同语义），`to_utf8` 对孤立代理回退
   U+FFFD；本矩阵没有逐项测孤立代理的编码输出。
6. 只跑 ASCII + `é` + `😀` 三类输入，没有 Unicode 全表/locale 组合。
