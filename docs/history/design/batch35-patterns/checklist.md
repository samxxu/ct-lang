# 检查清单：设计模式覆盖（第三十五批）

依据：`docs/design/batch35-patterns/spec.md` / `tasks.md`

## 覆盖

- [x] Strategy：接口参数按值装箱，两个实现切换
- [x] Observer：接口数组字段、变量下标赋值、经 Subject 指针通知
- [x] Decorator：接口字段嵌套两层，逐层转发
- [x] Composite：接口数组字段 + 递归求和 / 计数
- [x] Factory Method：返回接口的工厂，堆对象装箱
- [x] Template Method：自由函数骨架 + 步骤 trait 的两个实现

## 关卡

- [x] `check-ast.sh` 的六个 `pattern/*` 断言全过
- [x] clang 与 GNU GCC 16 零告警，输出一致
- [x] `bash selfhost/check-ast.sh` → 317 passed, 0 failed
- [x] `bash selfhost/check-warnings.sh` → 146 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未改编译器、生成物、golden 与 `CTC_VERSION`

## 文档与提交

- [x] `docs/patterns.md`（对照表 + 替换规则 + 边界）
- [x] README 中英文档树与链接
- [x] `docs/roadmap.md` 第三十五批（中英）
- [x] 测试一个提交；文档与设计记录一个提交
