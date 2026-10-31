# 任务：设计模式覆盖（第三十五批）

依据：`docs/design/batch35-patterns/spec.md`

## [x] T1 六个模式 fixture

- `test/patterns/{strategy,observer,decorator,composite,factory_method,template_method}/`
  下的 `prog.ct` 与 `expected.out`。

## [x] T2 关卡

- `selfhost/check-ast.sh`：新增「design patterns」一节（编译 → 零告警构建 → 运行 →
  比对），头注释补 batch 35。

## [x] T3 文档

- `docs/patterns.md`：模式 → 机制的对照、无继承 / 无泛型的三条替换规则、其余模式的落法、
  边界（无类型检查、固定容量接口数组）。
- README 中英的文档树与链接加入 `patterns.md`。
- `docs/roadmap.md`：Post-Phase-12 补记第三十五批（中英）。

## [x] T4 验证与提交

- 三关（check-ast / check-warnings / check-all）如实记录。
- 提交：`test(patterns): cover six design patterns with the existing language`
  与 `docs(spec): record the design-pattern coverage`。不 bump 版本。
