# langcap-1 关闭

| 项 | 值 |
| --- | --- |
| 状态 | `closed`（2026-11-15；EDITOR 判决） |
| 争点 | 九条语言能力缺口逐条定性：A 承诺未兑现（bug）/ B 从未支持（需求）/ C 明确不做（设计拒绝）/ D 主张不成立 |
| 结论 | 无整条「没实现」；真 A 六处：同名 `.h.ct`/`.ct` 产物冲突（1b，open）、数字下标静默空值（5a，open）、三级同类型下标链（6a，LANG-13 声称已修）、固有方法结果作接收者（6b，LANG-5 / `JSON-2` 在途）、下标结果取字段静默坏 C（6c，open）、`char *` 传 `Str` 只报 warning（9b，LANG-14 声称已修）；其余为已支持（1a/8b）、新需求（1c/2/4/5b）或明文拒绝（3/6d/7/8a/9a） |
| 证据 | [verify.json](verify.json)（10 条 evidence、23 条 anchor、9 条 checks）；探针在 `/tmp/lcb/**`，未写入仓库 |
| 修复状态 | LANG-13 / LANG-14 的「已修」未复验：issue 引用的 `263` / `264` 夹具不在仓库；LANG-5 有 `262_inherent_mcall_receiver` 与 `TypeCheck.h.ct` 在途改动，未提交。三者均只按「声称已修 / 在途」引用 |
| 新建 issue | `LANG-11`（同名单元产物冲突）、`LANG-12`（属性访问协议） |
| 引用 issue | `LANG-4`（5a）、`LANG-5`（6b/6c，`JSON-2`）、`LANG-13`（6a，`JSON-1`）、`LANG-14`（9b，`JSON-3`）、`SH-73`（6d）、`SH-18`（2）、`PKG-2`/`LANG-6`（3）、`REQ-JSACCESS-1`/`REQ-INDEX-1`（5b） |
| 并行交接 | 开工时 `issues/lang/` 只有 LANG-1..5、7..10；写作中并行提交 `89b1124b` 新增 LANG-13/14；LANG-6 已并入 PKG-2；本轮占 LANG-11/12，namespace 常量与限定名登记顺延 LANG-15 起 |
| 下一步 | P0：LANG-4 的「无候选硬错」；P1：LANG-5 字段守卫、LANG-11 产物命名；在途：LANG-5 固有方法结果（`262` 提交后复验）；待验证：LANG-13 / LANG-14 夹具补齐；P2：LANG-12 / REQ-JSACCESS-1；P3：1c、2、PKG-2、6d |
| 不修改 | 不改 `selfhost/**`、`test/**`、`lib/**`、`docs/language-spec.md`、`docs/package-guide.md`；不 push、不打 tag、不 bump 版本 |
