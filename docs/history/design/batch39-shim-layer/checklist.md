# 检查表：`.m.ct` 的 C shim 伴随层（第三十九批）

按 `spec.md` 逐条核对；每项以**运行结果**为准，不以读码代替。

## 探测与诊断

- [x] 同目录同名的 `<base>.shim.h` 让映射单元 `has_shim = 1`，`.shim.c` 同样被记录。
- [x] shim 只对 `.m.ct` 生效：`foo.h.ct` / `foo.ct` 旁的 `foo.shim.h` 被忽略。
- [x] 只有 `<base>.shim.c` 没有 `<base>.shim.h` → 非零退出，stderr 含
      `a shim source needs a matching .shim.h` **且含期望头路径**，位置是 `<path>:1:1: error:`。
- [x] `<base>.shim.h` 不是普通文件（如目录）→ 非零退出，stderr 含
      `a shim header is not a readable file: <路径>`。
- [x] 两个映射单元的 shim 同名但目录不同 → 非零退出，stderr 含
      `ctc: shim base name '<base>' is ambiguous: <dir1> and <dir2>`，输出目录无 `main.c`。

## prologue

- [x] `test/modules/map_unit_shim/main.c` 顶部含 `#include "lib.shim.h"`，消费者自己没写这行。
- [x] shim 行先于该映射单元的 `#include` / `#define`。
- [x] 同一 shim 被多个消费者（含传递 import）看到时整行只出现一次。
- [x] 消费者 `.h` 不含 shim include 与 prologue。

## `cc` 行

- [x] 带 shim 的映射单元产生 ` -I <shim 目录>`，同一目录只输出一次。
- [x] 存在的 `.shim.c` 列在消费者源文件之后，每个文件一次。
- [x] 头文件式 shim 只增加 `-I`，不增加源文件。
- [x] `.m.ct` 自身仍不出现在源文件列表里（零产物）。

## 缓存

- [x] 无改动时暖构建复用消费者（消费者 `.c` 不重生成）。
- [x] `touch <base>.shim.h` 后消费者重建。
- [x] 缓存 key 的依赖材料里含 shim 两文件的 `mtime.size`（拼接为 `sh@…;` / `sc@…;`，再参与
      `imports` 哈希）；可观察的结果就是暖构建复用、`touch` 后重建。

## 例子与回归

- [x] `test/modules/map_unit_shim` 产物目录无 `lib.c` / `lib.h`；先 `lib::Io.clear()`，用 `cc` 行
      编译运行得到 `1 1 2`。
- [x] `--emit-map` 的静态条目含 `"shim":{"header":…,"source":…}`；不带 shim 的 `test/modules/map_unit`
      JSON 里没有 `"shim"`。
- [x] `bindings/posix-socket/demo.ct` 生成物含 `#include "socket.shim.h"`，`cc` 行含
      `-I bindings/posix-socket/posix` 且不含 `.shim.c`；运行得到 `hello 5`。
- [x] `check-warnings.sh` 用 `cc` 行的 `-I` 对解析 shim 头，两个 binding 都覆盖。
- [x] 无 shim 的既有 `.m.ct` 用例生成物逐字节不变；动态 `map` 产物不变。
- [x] `test/cases/**` 与 `test/modules/**` golden 不变（本批不 bump 版本）。

## 关卡

- [x] `bash selfhost/check-ast.sh` 全绿（403 passed）。
- [x] `bash selfhost/check-warnings.sh` 全绿。
- [x] `bash selfhost/check-all.sh` 九关全绿。
- [x] `CTC_VERSION` 不变（v0.15.1）。

## 文档

- [x] `docs/design/batch39-shim-layer/` 三件套与实现一致。
- [x] `docs/language-spec.md` §4.10 中英对称补「伴随 C shim」。
- [x] `docs/tutorial.md` 有最小 shim 例子（中英）。
- [x] `bindings/README.md` 写明 shim 约定与参考 binding。
- [x] `docs/glossary.md` 补术语；`docs/roadmap.md` 新增批次条目（中英）。
