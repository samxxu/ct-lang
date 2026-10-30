# 任务：把 L0 种子纳入关卡（第二十七批）

依据：`docs/design/batch27-seed-gate/spec.md`
顺序即依赖顺序。

## [x] T1 新断言

- `check-ast.sh`：在 `== self-hosting (9.6) ==` 之后、summary 之前新增
  `== the L0 seed (ct-ast compiles ctc.c itself) ==`，一条断言串起
  「解析 ctc.c → 编生成物 → 用产物编示例 → 运行并比对期望输出」。
- 头注释补一行说明本批。

## [x] T2 关卡、文档与提交

- `bash selfhost/check-ast.sh` → 276 passed；`check-warnings.sh` → 141 ok；
  `check-all.sh` → 九关全绿。
- `docs/design/batch27-seed-gate/` 三件套（本批不改 `docs/language-spec.md`：
  没有语法变化）。
- 提交拆分：`test(selfhost): gate the L0 seed compile`、
  `docs(spec): record the L0 seed gate`。不 bump 版本、不动 golden。
