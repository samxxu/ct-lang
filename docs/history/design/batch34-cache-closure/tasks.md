# 任务：增量构建的依赖闭包（第三十四批）

依据：`docs/design/batch34-cache-closure/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 `need` 集合

- `selfhost/l2/driver.ct`：`build_main` 增加 `need[MAX_UNITS]`；删除 `first`；
  反向遍历 `order` 求脏单元的依赖闭包；发射循环改为只看 `need[u]`。

## [x] T2 回归测试

- `selfhost/check-ast.sh`：缓存一节新增三单元工程（A 脏、B 干净、C 依赖两者），
  两条断言：冷构建解析导入类型；改 A 后重建仍解析，生成物零告警编译。

## [x] T3 真实链路验证

- 用新 L2 构建 ct-ast，改 `Parser.h.ct` 后同目录重建，生成物可编译且与重建前一致。

## [x] T4 文档与提交

- `docs/roadmap.md`：Post-Phase-12 补记第三十四批（中英）。
- 提交：`fix(build): recompile the dependency closure of a dirty unit`（代码 + 测试）
  与 `docs(spec): record the incremental-build closure fix`（文档与设计记录）。
  不 bump 版本。
