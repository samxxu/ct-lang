# 检查清单：真实头文件兼容（第三十三批）

依据：`docs/design/batch33-header-compat/spec.md` / `tasks.md`

## 语法与产物

- [x] `_Atomic(int)` 在全局、局部与 `sizeof` 中可用，拼写原样保留
- [x] 裸 `_Atomic int` 仍可用
- [x] `_Alignas(16) static int g;` 可用，发射为 `static _Alignas ( 16 ) int g;`，地址按 16 对齐
- [x] 块作用域 `_Alignas(8) static int x;` 可用，地址按 8 对齐
- [x] 声明符前的属性：全局、函数原型 / 定义、局部变量
- [x] 局部变量尾部属性 `int x __attribute__((unused));`
- [x] 属性抑制未使用告警（生成物在 `-Wall -Wextra` 下零告警）

## 诊断

- [x] `_Atomic(int x;` → `unterminated _Atomic`
- [x] `__attribute__((…)) typedef int T;` → `an attribute must prefix a declaration`
- [x] 同一局部声明前后各一个属性 → `duplicate __attribute__ on one declaration`
- [x] `_Alignas(8) _Alignas(16) int g;` → `duplicate _Alignas on one declaration`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 309 passed, 0 failed
- [x] `bash selfhost/check-warnings.sh` → 146 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] clang 与 GNU GCC 16 零告警构建 fixture 生成物，输出一致
- [x] 未新增 impl 方法（`attr_pool` 只是从 `ParseOps` 搬到 `SupportOps`）
- [x] 未改 `selfhost/l2/**`、节点编号、`CTC_VERSION` 与既有 golden

## 文档

- [x] `docs/language-spec.md` 新增 §4.38（中文 + 英文）
- [x] `docs/roadmap.md` Post-Phase-12 补记第三十三批；容量策略 A 与回访条件入表
- [x] README 中英能力说明同步
- [x] 增量缓存的不自洽现象记入 spec §4（不在本批修复）

## 提交

- [x] 代码 + fixture + 负例 + 关卡一个提交
- [x] 文档与设计记录一个提交
