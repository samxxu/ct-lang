# 检查清单：C 兼容性收尾（第三十二批）

依据：`docs/design/batch32-c-compat/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与产物

- [x] 整数后缀 `U` / `L` / `UL` / `LL` / `ULL`：十进制、十六进制、八进制、大小写混写
- [x] 后缀规范化（顺序统一、字母统一大写）后再发射；数值不变
- [x] `_Noreturn` 原型 + 定义的生成物保留 `_Noreturn`
- [x] `static_assert` 与 `_Static_assert` 都被接受，统一发射 `_Static_assert`
- [x] `int *__restrict p` / `int *__restrict__ p` 可用，拼写原样保留

## 诊断

- [x] `1LLL` → `an integer suffix may be U, L or LL`（负例精确断言）
- [x] `1UU` → 同一消息（负例精确断言）

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 300 passed, 0 failed
- [x] `bash selfhost/check-warnings.sh` → 145 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] clang 与 GNU GCC 16 都零告警构建 fixture 生成物，输出一致
- [x] 未新增 impl 方法、未新增节点编号、`CTC_VERSION` 未变、既有 golden 零改动

## 文档

- [x] `docs/language-spec.md` 新增 §4.37（中文 + 英文）
- [x] 顶部「C 形式覆盖」加入整数字面量后缀
- [x] `docs/roadmap.md` Post-Phase-12 补记第三十二批（中英）
- [x] README 中英两处能力说明同步

## 提交

- [ ] 代码 + fixture + 负例 + 关卡一个提交
- [ ] 文档与设计记录一个提交
