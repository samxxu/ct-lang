# 第三十九批：`.m.ct` 的 C shim 伴随层（设计）

> 状态：**已实现（第三十九批，v0.15.1 之后，未 bump 版本）**。落地在
> `selfhost/ct-ast/frontend/module/**`、`selfhost/ct-ast/backend/emit/Emitter.h.ct`、
> `selfhost/check-ast.sh`、`selfhost/check-warnings.sh`，例子在
> `test/modules/map_unit_shim/` 与 `bindings/posix-socket/`。
> 现状描述见 `docs/language-spec.md` §4.10「静态映射」。
> 前置阅读：[batch38-map-unit/spec.md](../batch38-map-unit/spec.md)（§13 附录的分层结论）。

## 1. 问题与目标

第三十八批把「单次调用型」C API 做到了零成本（`host::Trait.method(…)` 与 `for type` 在调用点
展开成裸调用），但 §13 附录同时点明了 `.m.ct` 的天花板：recipe 只能写一次顶层调用，**写不出**
这些东西——

- 宏形式的 API（`FD_SET`、`WIFEXITED`、`container_of` 一类语句宏）；
- 全局量 / 隐蔽参数（`errno`、`optind`、`stdin`）；
- 需要类型转换才能匹配的调用（`write(int, const void *, size_t)` 对 `char *`）；
- 变参转发（`printf` 家族里「前缀固定、尾部透传」的形态）；
- 无 userdata 的回调（`qsort`、`signal`）。

第三十八批的结论是「这些交给用户手写 C shim」。问题是：**写了 shim 之后，编译器不认识它**——
shim 头不会被 include，shim 源不会进 `cc` 行，改了 shim 也不会触发消费者重建。

目标：

- 让 `.m.ct` **正式支持**同目录同名的伴随 shim：`<base>.shim.h` / `<base>.shim.c`。
- recipe 因此可以绑到 shim 里的 `static inline` 包装、宏访问器、全局访问函数，形状不再受限。
- 零新增语言语法、零新增 CLI 选项、零新增 JSON 字段；`.m.ct` 仍然零产物。
- 不改变既有动态 `map` 的产物与语义，不改变既有 `.m.ct`（没有 shim 时行为逐字节不变）。

非目标见 §7。

## 2. 术语

| 术语 | 含义 |
| --- | --- |
| 伴随 shim（sibling shim） | 与 `<base>.m.ct` **同目录同名**的两个 C 文件：`<base>.shim.h`、`<base>.shim.c` |
| shim 头 | `<base>.shim.h`；消费者 `.c` 自动 `#include "<base>.shim.h"` |
| shim 源 | `<base>.shim.c`；`ct build` 建议的 `cc` 行自动把它列入源文件 |
| 头文件式 shim | 只有 `.shim.h`、没有 `.shim.c` 的形态（`static inline` 包装，最常见） |
| shim 目录 | 映射单元所在目录；它同时成为 `cc` 行的一个 include root |

## 3. 约定

### 3.1 文件命名与位置

```
<dir>/<base>.m.ct         映射单元（namespace 必须等于 <dir>）
<dir>/<base>.shim.h       shim 头（可选，但一旦有 .shim.c 就必须有）
<dir>/<base>.shim.c       shim 源（可选）
```

- 三个文件**必须**同目录同名；编译器只按这个约定探测，没有配置项。
- shim 只对 `.m.ct` 生效。`foo.h.ct` / `foo.ct` 旁边的 `foo.shim.h` 被忽略。
- `.shim.h` 是本批唯一触发点：只有 `.shim.c` 而没有 `.shim.h` 时报
  `a shim source needs a matching .shim.h: <期望的头路径>`（位置 `<path>:1:1: error:`）；
  消息里带路径，用户不必自己拼文件名。

### 3.2 最小形状

```ct
/* posix/socket.m.ct */
namespace posix;

pub trait Socket {
    int pair(int *sv);
    int err();
}

map trait Socket for namespace posix {
    pair(sv) -> ct_sock_pair(sv);
    err() -> ct_sock_errno();
}
```

```c
/* posix/socket.shim.h —— 头文件式 shim，无需 .shim.c */
#include <errno.h>
#include <sys/socket.h>

static inline int ct_sock_pair(int *sv) { return socketpair(AF_UNIX, SOCK_STREAM, 0, sv); }
static inline int ct_sock_errno(void) { return errno; }
```

生成物（消费者 `.c` 顶部）：

```c
#include "socket.shim.h"
#include <stdio.h>
```

注意 shim 头用**文件名**而非路径：它靠 `cc -I <shim 目录>` 解析，这也是 `ct build` 会打印
`-I <shim 目录>` 的原因。

## 4. 编译器行为

### 4.1 探测（`Module::load_unit`）

`load_unit` 在 `base_name` 之后、`read_file` 之前探测；只有 `is_map` 为真时探测：

- `stat("<dir>/<base>.shim.h")` / `stat("<dir>/<base>.shim.c")`，命中的路径记入
  `Unit.shim_h` / `Unit.shim_c`；
- 命中的文件必须是**普通文件**且可读（`S_ISREG` + `access(R_OK)`），否则报
  `a shim header is not a readable file` / `a shim source is not a regular file`，消息带路径；
- `has_shim = 1` 当且仅当 `.shim.h` 存在且可读（`shim_dir` 同时记为该目录）；
- `.shim.c` 存在而 `.shim.h` 缺失 → `tool::diag::ct_sem_error(1, 1,
  "a shim source needs a matching .shim.h: <头路径>", path)`。

`Unit` 新增四个字段（[Unit.h.ct](../../../../selfhost/ct-ast/frontend/module/Unit.h.ct)）：

```c
int  has_shim;
char shim_dir[1024];
char shim_h[1024];
char shim_c[1024];
```

### 4.2 prologue 引入（`Emitter::emit_map_prologues`）

对消费者 `u` 的 `depu` 闭包里每个可达的 `.m.ct` 单元 `d`：

1. 若 `d.has_shim`，先输出 `#include "<base>.shim.h>"`；
2. 再按第三十八批的规则输出 `d` 的 `#include` / `#define` 行。

去重按**整行文本**，shim 行与 prologue 行共用一个 `seen` 表，因此同一 shim 被两个 `.m.ct`
消费者（或经传递 import）看到时只出现一次。shim 行**先于**该单元的 prologue，因为该单元自己的
`#include` 可能是 shim 头依赖的头文件。

`emit_program`（compile 模式）不改：`.m.ct` 只能经 `ct build` 使用。

### 4.3 `cc` 行（`Module::build_main`）

- 在每个带 shim 的 `.m.ct` 之前输出 ` -I <shim_dir>`；同一目录只输出一次。
- 在消费者源文件之后输出每个存在的 `.shim.c`（按单元顺序，每个文件一次）。
- 头文件式 shim 不产生任何 `cc` 行增量（除 `-I`）。

示例：

```
cc -std=c99 -I test/modules/map_unit_shim/lib /tmp/x/main.c /tmp/x/lib.shim.c -o a.out
```

`.m.ct` 本身仍不出现在源文件列表里。

### 4.4 缓存（`Module::cache_key_of`）

`Cache::key` 只 stat 单元自身，因此 shim 的两个文件折叠进 `imports` 文本：

```
sh@<mtime>.<size>;  sc@<mtime>.<size>;
```

- 拼接位置在既有依赖列表之后、`dep` 哈希之前；
- 任一 shim 文件 `touch` 或改内容 → 消费者重建；什么都没变 → 命中缓存。

### 4.5 诊断

| 情形 | 消息 | 位置 |
| --- | --- | --- |
| 有 `.shim.c` 无 `.shim.h` | `a shim source needs a matching .shim.h: <头路径>` | `<path>:1:1: error:` |
| `.shim.h` 不是普通文件 / 不可读 | `a shim header is not a readable file: <路径>` | `<path>:1:1: error:` |
| `.shim.c` 不是普通文件 | `a shim source is not a regular file: <路径>` | `<path>:1:1: error:` |
| 两个映射单元的 shim 同名（不同目录） | `ctc: shim base name '<base>' is ambiguous: <dir1> and <dir2>` | 构建失败，无 `ctc:` 之外的位置 |
| shim 头里的符号拼错 | C 编译器报错（`cc` 行已含 `-I`） | 生成物 `main.c` 对应行（`#line` 默认开） |

同名冲突在 `build_main` 里于**产物落盘之前**检测（遍历已加载单元，按 `base` 比较、
目录不同即冲突），所以失败时输出目录里没有半成品。不校验 shim 的签名（签名契约是
「recipe 里写的 callee 必须存在」，由 C 编译器兜底）。

### 4.6 `--emit-map` 的 shim 字段

静态映射条目在 `"static":true` 之后多一个 `"shim"` 对象：

```json
{"trait":"Io","static":true,"shim":{"header":"lib/lib.shim.h","source":"lib/lib.shim.c"},"instance":"lib",…}
```

- `header` 恒在；`source` 只在 `.shim.c` 存在时出现；
- 无 shim 的映射条目逐字节不变（既有 golden 与 grep 断言不受影响）；
- 目的是让读 map 的工具（IDE、打包器）知道该映射还有两个 C 文件要带。

## 5. recipe 因此解锁的形状

| 形状 | shim 里的写法 | recipe |
| --- | --- | --- |
| 宏 / 语句宏 | `static inline int ct_fd_isset(int fd, fd_set *s) { return FD_ISSET(fd, s); }` | `isset(fd, set) -> ct_fd_isset(fd, set);` |
| 全局量 / 隐蔽参数 | `static inline int ct_errno(void) { return errno; }` | `err() -> ct_errno();` |
| 需要转换的调用 | `static inline int ct_sock_send(int fd, char *b, int n) { return (int)write(fd, b, (size_t)n); }` | `send(fd, buf, n) -> ct_sock_send(fd, buf, n);` |
| 变参前缀转发 | `static inline void ct_log_err(const char *fmt, ...) { … }`（`va_list` 在 shim 内部） | `err(fmt) -> ct_log_err(fmt);` |
| 无 userdata 回调 | `static int ct_cmp(const void *a, const void *b) { … }` + `static inline void ct_sort(...)` | `sort(base, n) -> ct_sort(base, n);` |
| 结构体字段访问 | `static inline int ct_stat_size(const struct stat *s) { return (int)s->st_size; }` | `size(st) -> ct_stat_size(st);` |

有 userdata 的回调（`pthread_create`、`sqlite3_exec`）仍需用户写 thunk，shim 只是**一个**适配点，
不是自动生成。

## 6. 测试与关卡

正例 `test/modules/map_unit_shim/`：

- `lib/lib.m.ct`（`namespace lib`，`trait Io { int err(); void clear(); int next(); }`，`for namespace lib`）；
- `lib/lib.shim.h`（`errno` 读/写访问器 + `next` 的声明与 `<errno.h>`）；
- `lib/lib.shim.c`（`next` 的实现，带状态计数）；
- `main.ct`（`import lib::lib;`，先 `lib::Io.clear()`，再
  `printf("%d %d %d\n", lib::Io.err() == 0, lib::Io.next(), lib::Io.next());`）；
- `expected.out` = `1 1 2`。

先 `clear()` 是刻意的：`errno` 在进程启动时不保证为 0（C 运行时自己可能失败一次），
不清零的话这条断言会随环境漂。

断言（[check-ast.sh](../../../../selfhost/check-ast.sh)）：

- 产物目录没有 `lib.c` / `lib.h`（`.m.ct` 仍零产物）；
- `main.c` 含 `#include "lib.shim.h"`；
- `cc` 行含 `-I <fixture>/lib` 与 `lib.shim.c`；
- 用该 `cc` 行（`-Wall -Wextra -std=c99`）编译运行，输出等于 `expected.out`；
- 冷/暖缓存：无改动时消费者不重生成；`touch lib.shim.h` 后重生成；
- `--emit-map` JSON 含 `"shim":{"header":…,"source":…}`，而不带 shim 的 `test/modules/map_unit`
  的 JSON 里没有 `"shim"`。

负例：

- `shim_source_without_header`：`lib.m.ct` + `lib.shim.c`（无 `.shim.h`）→ 非零退出，
  stderr 含 `a shim source needs a matching .shim.h` **且含期望头路径**；
- `shim_header_not_a_file`：`.shim.h` 是一个目录 → 非零退出，stderr 含
  `a shim header is not a readable file`；
- `shim_base_ambiguous`：两个目录各有一份 `lib.m.ct` + `lib.shim.h`，一个 `main.ct` 同时
  import 两个 → 非零退出，stderr 含 `shim base name 'lib' is ambiguous`，且输出目录没有 `main.c`。

真实库例子 `bindings/posix-socket/`：

- `posix/socket.m.ct`（`namespace posix`，`trait Socket { pair/send/recv/err }`，`for namespace posix`）；
- `posix/socket.shim.h`（头文件式：`socketpair` / `write` / `read` / `errno` 的 `static inline` 包装）；
- `demo.ct`（`import posix::socket;`，socketpair → send → recv → 打印 `hello 5`）；
- `demo.expected.out` = `hello 5`。

断言：`#include "socket.shim.h"`、`cc` 行含 `-I bindings/posix-socket/posix`、**不含** `.shim.c`，
编译运行输出 `hello 5`。

`check-warnings.sh`：

- 生成物里的 `#include "<base>.shim.h"` 需要 include root，故 modules 与 bindings 两段在 build 后
  从 `cc` 行用 `awk` 提取 `-I <dir>` 对，原样传给 `scan_one`；
- bindings 段改为遍历 `bindings/*/demo.ct`（mock-hal 与 posix-socket 都覆盖）。

## 7. 非目标

- 不自动生成 shim（仍由用户手写，一个 shim 只服务一个映射单元）。
- 不做 shim 签名校验、不做 ABI 校验；错配由 C 编译器报错。
- 不支持跨目录 / 改名 / 多个 shim（没有配置项，只有同目录同名约定）。
- 不在 `.m.ct` 里镜像 C `struct` / `enum` / 全局变量（第三十八批的非目标仍然成立，shim 是出口）。
- 不引入 `ct.pkg` / `ldflags` / `-l`（仍需用户自己加链接参数）。
- 不改既有动态 `map` 的行为、产物、命名与 JSON 形状；`--emit-map` 只在静态映射条目上加一个
  `shim` 对象（§4.6），其余字段不变。
- 不 bump `CTC_VERSION`（用户未要求；本批是能力增量而非版本事件）。

## 8. 已定取舍

| 问题 | 结论 |
| --- | --- |
| shim 怎么定位 | 同目录同名 `.shim.h` / `.shim.c`，零配置 |
| 触发点 | `.shim.h` 存在即 `has_shim`；只有 `.shim.c` 报错 |
| shim 头怎么 include | `#include "<base>.shim.h>"`（文件名），由 `-I <shim 目录>` 解析 |
| include root 谁来给 | `ct build` 打印的 `cc` 行带 `-I`；`check-warnings.sh` 从该行取 |
| shim 源怎么编译 | 直接列入 `cc` 行，不复制、不进产物目录、不写缓存 |
| 缓存 | shim 两文件的 `mtime.size` 折叠进 map 单元 key（`sh@…; sc@…;`） |
| 头文件式 shim | 支持（最常见的形态），`cc` 行只有 `-I` |
| 与 prologue 的顺序 | shim 行在前，单元自己的 `#include` 在后 |
| JSON | 静态映射条目加 `"shim":{"header","source"}`；无 shim 时形状不变 |

## 9. 分片

| 片 | 内容 | 出口 |
| --- | --- | --- |
| S0 | `Unit` 字段 + `load_unit` 探测 + `.shim.c` 无头的诊断 | 探测结果可观察（正/负例） |
| S1 | `emit_map_prologues` 输出 shim include（整行去重） | 正例 1 能编过、能跑 |
| S2 | `build_main` 的 `-I` 与 `.shim.c` | `cc` 行自洽 |
| S3 | 缓存折叠 + warm / touch 断言 | 改 shim 触发重建 |
| S4 | 真实库 binding（posix-socket）+ `check-warnings.sh` roots | 九关全绿 |
| S5 | 收尾：诊断带路径、非普通文件拒绝、`--emit-map` 的 `shim` 字段、同名 base 冲突 | 三条新断言 + 九关全绿 |
