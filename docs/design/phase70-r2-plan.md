# v0-PH-70-R2 施工计划（定值 / 全路径 return）

> 状态：未开工；R3 已交付，R1 CFG 未建。本文件给出不必先建 CFG 的最小实现路径。

## 0 现状

- `int x; return x;` 在 `ct check` 下静默（未初始化读）；
- 非 void 函数缺少 return 也静默（掉出函数尾是 UB）；
- 已有的 `p70/flow`、`p70/switch`、`p70/unreach` 只覆盖语句级跳转上下文。

## 1 两条独立的小检查（不依赖 CFG）

### A. 未初始化读（线性、函数内）

1. 在 `Stmt` 的作用域栈旁维护一个「已声明未赋值」集合（按变量名）；
2. `N_DECL` 无初值时加入；`N_ASSIGN`/复合赋值以 `N_VAR` 为目标时移除；
3. 读到集合内变量 → `use of uninitialized variable 'x'`；
4. 分支/循环保守处理：进入 `if`/`switch`/循环前快照集合，退出时求**交集**
   （只在所有路径都不确定已初始化时才报），宁可漏报不误报。

### B. 非 void 函数缺 return

1. 函数体 AST 递归扫描 `N_RET`；
2. 没有任何 `N_RET` 且返回类型非 void → `non-void function may not return a value`；
3. 例外：函数体含 `while(1)`/`for(;;)` 等可判定的无限循环、或末尾调用
   `exit/abort`，跳过（避免对合法代码误报）。

## 2 验收

- `p70_definite.sh`：未初始化读负例、全路径赋值正例、分支半边赋值负例；
- `p70_return.sh`：缺 return 负例、无限循环/exit 正例；
- 两个探针接入 `check-ast`；`p68_fp`/`p69_fp` 仍 FP=0。

## 3 风险

| 风险 | 缓解 |
| --- | --- |
| 分支合并误报 | 只在交集为「未初始化」时报；先跑合法语料 |
| 无限循环判定 | 只认字面 `while(1)`/`for(;;)`，其余跳过 |
| 与 AutoDrop/own 交互 | 只读变量名集合，不改 AutoDrop 台账 |
