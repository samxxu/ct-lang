# 检查清单：`.h.ct` 规则落地（第三十批）

依据：`docs/design/batch30-header-rule/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与产物

- [x] `build` 只为 `.h.ct` 单元写 `.h`（split：有 `shapes.h` / `impl_dog.h`，无 `main.h`）
- [x] `compile foo.ct` 只写 `foo.c`（corpus 53 个 fixture 逐一断言无 `.h`）
- [x] `compile foo.h.ct` 写 `foo.c` + `foo.h`，且 `.c` 不包含自己的头
- [x] 实现单元的 `.c` 自包含（`pub` 类型在本地发射；split / hdr 编译零警告）
- [x] 头文件前言规则仍成立（`hdr` / `hdr_prologue` 的 `#include` 进头、`#define` 不进）

## 诊断

- [x] `import` 普通 `.ct` → `only a .h.ct unit can be imported: rename 'helper.ct' to 'helper.h.ct'`
- [x] `import` 不存在的单元 → 仍是 `cannot resolve import 'x'`（inc_missing 不变）
- [x] `-I` 顺序不变：导入方目录优先（precedence 迁移后仍通过）
- [x] 别名导入、`::` 限定、`--ns-root` 行为不变（alias / ns_* 全部通过）

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 290 passed, 0 failed（含自编不动点）
- [x] `bash selfhost/check-warnings.sh` → 143 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] `test/pkg` 的 vendored 包改名后 `ct get` / `install` / `build` 仍通过
- [x] `ct-tour` 的缓存演示按新产物断言（无 `main.h`）
- [x] 归档 oracle（L2）0 退化：`test/archive/**` 全部 PASS
- [x] L2 designed goldens 只重生成 8 个改名单元，diff 仅 banner / `#line` 的源路径
- [x] 未新增 impl 方法、未新增节点编号、`CTC_VERSION` 未变

## 文档

- [x] `docs/roadmap.md` 文件命名表：`foo.ct` 半已落地（中英对称）
- [x] `docs/language-spec.md` 顶部「有意拒绝」表新增 `import` 普通 `.ct` 一行（中英）
- [x] tutorial / bindings README / selfhost README 的 `.h.ct` 路径已同步
- [x] `docs/design/batch30-header-rule/` 记录决策与数字

## 提交

- [x] 代码 + 改名 + fixture + 关卡一个提交
- [x] 文档与设计记录一个提交
- [x] 提交正文说明「为什么必须禁 import」与 L2 分叉
