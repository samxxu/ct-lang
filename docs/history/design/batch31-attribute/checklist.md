# 检查清单：GNU `__attribute__((…))`（第三十一批）

依据：`docs/design/batch31-attribute/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与产物

- [x] 函数原型 / 定义：`)` 之后、`;` / `{` 之前（`unused`、`format(printf, 1, 2)`、
      连续两组 `unused` + `noinline`）
- [x] 形参：名字之后（`int b __attribute__((unused))`），原型与定义拼写一致
- [x] 字段：名字/维度之后；位域则在宽度之后
- [x] 全局变量：声明符之后、`=` 之前（`aligned(16)`，地址取模 0）
- [x] `typedef` 别名之后（`typedef int word __attribute__((aligned(8)))`，`_Alignof` ≥ 8）
- [x] `struct` / `union` / `enum` 定义体之后；typedef 记录类型发射在别名之前
      （`packed` 生效，`sizeof` = 5）
- [x] 属性原文（含嵌套实参）保留；多个连续组之间补空格、整体可被 C 编译器接受

## 诊断

- [x] 未闭合 → `unterminated __attribute__`（负例精确断言）
- [x] 同一声明两个捕获位置 → `duplicate __attribute__ on one declaration`（负例精确断言）

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 295 passed, 0 failed（含自编不动点）
- [x] `bash selfhost/check-warnings.sh` → 144 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] clang 与 GNU GCC 16 都零告警构建 fixture 生成物，输出一致
- [x] 构建未触发 `MAX_MAP_IMPLS`（新增 1 个 impl 方法 `attr_pool`）
- [x] 未新增节点编号、`CTC_VERSION` 未变、既有 golden 零改动

## 文档

- [x] `docs/language-spec.md` 新增 §4.36（中文 + 英文）
- [x] 顶部「C 形式覆盖」不再列未实现项；§4.23 / §4.26 的「范围外」改为「无」
- [x] `docs/roadmap.md` Post-Phase-12 补记第二十九 / 三十 / 三十一批（中英）
- [x] README 中英两处能力说明同步

## 提交

- [x] 代码 + fixture + 负例 + 关卡一个提交
- [x] 文档与设计记录一个提交
- [x] 提交正文说明「尾部透传」的取舍、typedef 记录位置的归一化与验证方式
