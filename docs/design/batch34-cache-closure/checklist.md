# 检查清单：增量构建的依赖闭包（第三十四批）

依据：`docs/design/batch34-cache-closure/spec.md` / `tasks.md`

## 修复

- [x] `build_main` 的编译集合是脏单元的依赖闭包（反向传播一趟）
- [x] `first` 及其前缀规则删除，发射循环只看 `need[u]`
- [x] 干净依赖被重编译时产物逐字节不变，缓存键不变

## 回归与关卡

- [x] `check-ast.sh` 新增：L2 冷构建解析导入类型（`struct cache_B`）
- [x] `check-ast.sh` 新增：改 A 后重建仍解析，生成物零告警编译
- [x] 真实链路：新 L2 构建 ct-ast → 改 `Parser.h.ct` → 同目录重建可编译且产物一致
- [x] `bash selfhost/check-ast.sh` → 311 passed, 0 failed
- [x] `bash selfhost/check-warnings.sh` → 146 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未改生成物内容、缓存键格式、`CTC_VERSION` 与既有 golden
- [x] 只动 `selfhost/l2/driver.ct`（冻结层的 bug 修复，提交正文说明）

## 文档与提交

- [x] `docs/roadmap.md` Post-Phase-12 补记第三十四批（中英）
- [x] 代码 + 测试一个提交；文档与设计记录一个提交
