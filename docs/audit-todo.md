# 审计待办（交给模块组）

> 来源：一次「测试覆盖度 + 文档一致性」复审（基线 `./test/run.sh` = 110 passed / 0 failed；
> 自举侧 `check-goldens.sh` / `check-m2a.sh` / `check-archive.sh` 均绿）。
>
> 本文件只列**待修项**，不含已经修掉的东西。测试用例已由审计方补齐（见文末「已由本次审计完成」），
> 编译器与文档的修复留给模块组。每项都给了可复现的证据与验收方式。
>
> **模块组处理结果见文末「模块组回执」**（2026-10-16）。

---

## A. 文档一致性（按优先级）

### A1 `docs/architecture.md` —— 全文仍描述 Phase 0.3 已删除的越位实现（**最高优先级**）

该文自称「面向要修改 `ctc.c` 的人/代理」，但内容停留在越位实现期，读它会把人带错。

- [x] **函数清单含 18 个已不存在的符号**（中英两份清单都要改，约 L60–L87 / L211–L240）：
  `build_main`、`collect_imports`、`resolve_import`、`unit_visit`、`build_output`、
  `line_at`、`line_break`、`leak_observe`、`warn_add`、`leak_check_scope`、`line_has_word`、
  `find_struct_c`、`find_trait_c`、`last_qual_name`、`qual_to_c`、`span_qualified`、
  `body_calls_sibling`（已改名 `body_needs_vtable`）、`read_qual_ref`。
  - 证据：`grep -c '名字' ctc.c` 全为 0；现存的驱动只有 `usage`/`default_output`/`header_path`/
    `write_guard`/`read_file`/`compile_range`/`compile_file`/`compile_main`/`main`。
  - 另查出审计清单之外的 5 个同款失效符号并一并清除：`set_cname`、`line_of`、`find_field`
    （现存 `find_field_ex` / `find_iface_field`）、`file_exists`、`put_vptr_designators`
    （现存 `put_own_vptr`）。
- [x] **把机制描述改回现状**：越位期的 `#line` 发射、泄漏警告（Phase 1.7）、namespace 前缀修饰
  (`cname` mangling)、多文件驱动，都不再存在于 `ctc.c`。`compile_range` 现在**不**递归 namespace
  （`namespace`/`import`/`pub` 命中即 `die`，见 `ctc.c` L2753–2764）。
- [x] **§8「扩展点」把 namespace 标成「✅ 已落地（Phase 1.1）」**（中文 L155 / 英文 L325）——应改为
  「已随 Phase 0.3 移出，Phase 2 在 CT 层恢复」，与 `docs/language-spec.md` 开头状态声明保持一致。
- [x] 顺带核对 §4 数据结构一节：`cname` 仍在，但其语义已**不含**命名空间前缀（`ctc.c` L1197–1198 只是原名拷贝）。
- 验收：通读一遍，文中每个函数名都能在 `ctc.c` 里 `grep` 到；中英两份对称。

### A2 `docs/glossary.md` —— 术语与层清单过期

- [x] **层清单**（中文 L112 / 英文 L253）写作
  `build / unit / cases / errors / examples / multifile / import / line / limits / cli`，
  实际 `test/run.sh` 只有
  `build / unit / cases / errors / examples / limits / cli`（`multifile` / `import` / `line` 三层已随 Phase 0.3 移除）。
- [x] **`end-to-end` 定义**（中文 L120 / 英文 L261）仍写「examples / multifile / import 各层」。
- [x] **namespace / import / `ct build` / multi-file mode** 仍是现行术语（中文 L33/35/74/101、
  英文 L176-178/217/242）——应标注「已移出自 L0；Phase 2–5 在 CT 层恢复」，或注明现在由 `selfhost/` 的 L1 承载。
- 验收：层清单与实际 `test/run.sh` 注释中的层列表逐字一致。

### A3 `README.md` —— 四处过期（中英各一份）

- [x] **examples 目录树只列 01–04**（中文 L238–241 / 英文 L580–583），漏 `05_body_dispatch`、`06_iface_field`。
- [x] **通篇没有 `selfhost/`**：`selfhost/ctc.ct`(L1)、`selfhost/src/**`(L2 拆分树) 与四个 gate 脚本
  (`check-goldens.sh` / `check-m2a.sh` / `check-archive.sh` / `ct-tour.sh`) 都未出现在 README 的测试章节与目录树里；
  而 `AGENTS.md` 已把它们列为必跑。建议在「测试」节补一段自举 gate 说明。
- [x] **`check-grammar.py` 断言数写成 13**（中文 L230 / 英文 L571），实际 **19**：
  `python3 editors/vscode/test/check-grammar.py` → `== 19 checks, 0 failed ==`。
- [x] **容量清单仍含已删除的 `ct build` 限额**（中文 L283–284 / 英文 L630–631）：
  「`ct build` 输入 32 / 编译单元 64 / 每单元 import 16」——`ctc.c` 已无对应 `MAX_*` 常量。

### A4 `docs/language-spec.md` §7 容量表不全

- [x] 表里缺 `MAX_SCOPE`(256)、`MAX_FUNCS`(64)（中英两表）。两者都在 `ctc.c` 中真实生效，
  且已有负例 `test/errors/too_many_scopes`、`test/errors/too_many_funcs`。
- 验收：§7 表的行数与 `ctc.c` 顶部 `#define MAX_*` 一一对应。

### A5 `docs/vision.md` —— 把已移出的能力写成现状

- [x] 中文 L53 / 英文 L165 称「泄漏警告列表」是编译器现有能力；泄漏警告已随 Phase 0.3 移出，
  计划在 Phase 2–5 用 CT 重做。措辞改为展望或标注状态。

### A6 `README.md` 计数（**由本次新增用例直接引起，须与 fixture 同批更新**）

- [x] 负例诊断用例 **56 → 60**（新增 4 个），总数 **110 → 114**。
  - 中文 L221 / 英文 L552–553。
  - 之所以单列：本次审计只负责加用例，若不同批改计数，README 会立刻变成错的。

---

## B. 覆盖度遗留（需模块组先定行为，再决定补测试还是接受）

以下 `ctc.c` 诊断点**至今没有 fixture**。审计已逐个探针验证可达性，结论分两类：

### B1 防御性 / 探针未命中 —— 建议「接受并在代码注释里标明」，不必补 fixture

> **模块组处理**：采纳「接受、不补 fixture」的结论，但**不落在 `ctc.c` 注释里**——`ctc.c` 处于冻结期
> （AGENTS.md §2：只接受 bug 修复，加注释属「不允许」项）。改记入
> [architecture.md](architecture.md) §7「设计债与风险」表，作为长期备忘。

- [x] `ctc.c` L1187 / L1189 `expected struct name` / `expected '{' after struct`：
  派发点 L2781–2788 要求「名字 + `{`」才进 `parse_struct`，故这两个 `die` 不可达
  （探针：`struct { int x; }`、`struct Foo` 均 exit 0 原样透传）。
- [x] `ctc.c` L1491 `nested field path too long`（`put_heap_vpts` 版本）：
  只检查**一跳**，`sub = ptr + "->" + fname ≤ 127+2+127 = 258 < 128*(8+3)=1408`，不可达
  （对照：其兄弟站点 L1463 已被本次新增 fixture 覆盖）。
- [x] `ctc.c` L2837 `cannot create a temporary file`：仅在 `tmpfile` 失败时触发，难构造。
- [x] `ctc.c` L158 / L237 `out of memory`：OOM 分支。

### B2 疑似漏洞 / 需定行为 —— 请模块组判断

- [ ] `default_output()` 的非 `.ct` 后缀分支（`ctc.c` L2652–2659）：输入 `foo` 会得到 `foo.c`。
  当前 `cli` 层无断言。补一条 CLI 断言即可钉死，或明确不保证。
  - **状态：待用户定夺**（两条路线都成立：补断言会把 `run.sh` 总数 114 → 115 并需同步 README 计数；
    或改为在文档里明确「不保证」）。
  - 已实测该分支的实际行为：`cp test/cases/21_empty_init_iface.ct /tmp/noext && ./ctc /tmp/noext`
    → `rc=0`，产出 `/tmp/noext.c` 与 `/tmp/noext.h`（guard `NOEXT_H`）。即「补断言」这条路线
    **技术上成立**，草案断言（插在 `cli/cannot-write-header` 之后）也验证可通过；但**尚未落盘**，
    待用户拍板后再加（届时 README 的 114 需同步改为 115）。
- [x] `put_nested_assignments()` 的递归**自身没有深度上限**（`ctc.c` L1441–1465）：
  对 `nu>0`（本身 `use` 了 trait）的嵌套链，L1461 的短路使 `needs_nested_init` 的 `MAX_DEPTH` 检查
  被绕过，递归深度只受 `MAX_STRUCT`(32) 间接约束。
  当前**不是**可复现崩溃（值互相引用在 ct 里无法表达，链必为无环有限），故仅作提示：
  若后续支持前向声明，这里会变成无限递归。建议加一个显式深度守卫或注释说明。
  - **模块组处理**：采纳「接受现状 + 记录」，同样不落在 `ctc.c` 注释里（冻结期），已记入
    [architecture.md](architecture.md) §7「设计债与风险」表，写明「前向声明落地时必须补显式深度守卫」。

---

## 已由本次审计完成（无需模块组处理）

- [x] 新增 `test/errors/too_many_ptr_fields.*` —— 覆盖指针 struct 字段表溢出（`ctc.c` L1151）。
- [x] 新增 `test/errors/too_many_ptr_iface_fields.*` —— 覆盖指针接口字段表溢出（`ctc.c` L1156）。
- [x] 新增 `test/errors/too_many_iface_fields.*` —— 覆盖值接口字段表溢出（`ctc.c` L1161）。
- [x] 新增 `test/errors/nested_field_path_too_long.*` —— 覆盖嵌套字段路径超长（`ctc.c` L1463）。
- 四个 `*.expected-err` 均由真实二进制输出导出（非手写）；`./test/run.sh` 由 110 项增至 **114 项全绿**。

---

## 模块组回执（2026-10-16）

**范围**：只改文档 + README 计数同步；**未改动 `ctc.c`**（冻结期），未改动任何测试或脚本。

| 项 | 处理 | 落点 |
| --- | --- | --- |
| A1 | 清理 **23** 个失效符号（审计列的 18 个 + 另查出 5 个）；重写 `#line` / 泄漏警告 / `cname` 前缀 / 多文件驱动四处机制描述；§8 namespace 恢复为「已移出 L0，Phase 2 起用 CT 重做」；§4 `cname` 改回「原名拷贝」 | `docs/architecture.md` |
| A2 | 层清单改为 `build / unit / cases / errors / examples / limits / cli`（与 `test/run.sh` banner 逐字一致）；`end-to-end` 定义同步；namespace / import / `ct build` / multi-file mode 四个术语补状态标注。**另（复核时发现，审计未点名）**：「内部符号」表整段仍在描述越位实现——驱动行误写 `build_main`（现存 `compile_range`/`compile_file`/`compile_main`）、`line_of`/`line_at`/`line_break`、`mark_drop_closure`、`potential_leak`/`leak_observe`、`Var.owned`/`own_line` 均已随 Phase 0.3 移出 L0，已逐个补「已移出 L0 / 由 `selfhost/` 用 CT 重做」标注 | `docs/glossary.md` |
| A3 | examples 树补全 01–06；新增「自举 gate（`selfhost/`）」小节（L1 / L2 / 四个脚本 + 用法，描述取自各脚本头注释）；`check-grammar.py` 13 → 19；容量清单去 `ct build` 三项、改为与 `ctc.c` 的 11 个 `#define MAX_*` 一一对应（中英对称） | `README.md` |
| A4 | §7 表补 `MAX_SCOPE` 256、`MAX_FUNCS` 64（中英对称），全表 11 行 = `ctc.c` 的 `#define MAX_*` 全集 | `docs/language-spec.md` |
| A5 | 泄漏警告改为「尚属展望——已随 Phase 0.3 移出 L0，计划 Phase 4 用 CT 重做」 | `docs/vision.md` |
| A6 | 负例 56 → 60、总数 110 → 114（中英各一处） | `README.md` |
| B1 | 采纳「接受、不补 fixture」；因冻结期不落 `ctc.c` 注释，改记入 §7「设计债与风险」表 | `docs/architecture.md` §7 |
| B2.2 | 采纳「接受现状 + 记录」，同样记入 §7，并写明「前向声明落地时必须补显式深度守卫」 | `docs/architecture.md` §7 |
| B2.1 | **未决**——两条路线都成立，需用户定夺（见上） | — |

**额外修正（审计未列，同属文档一致性）**：`README.md` 顶部「当前进入 Phase 1：自举」已过期，
改为「Phase 0 及子阶段 0.1/0.2/0.3、Phase 1（自举，2026-10-15）、Phase 2（模块化，2026-10-16）
均已完成，当前进入 Phase 3：内存」。

**验证**：
- 4 个新 fixture 逐个复跑：`./ctc test/errors/<name>.ct` 均 `exit=1`，且 stderr 含
  `too many struct fields in 'Big'`（3 个）/ `nested field path too long in struct`。
- `ls test/errors/*.ct | wc -l` = **60**，与 README 的 60 / 114 一致。
- `ctc.c` 上 `grep -c '\b<name>\b'` 对全部 18 个审计点名符号 = 0（复核成立）；
  `architecture.md` 改写后对全部 23 个失效符号 = 0 命中。
- 说明：`./test/run.sh` **未能**在本环境完整执行——其 `cli/cannot-write` 用例故意写
  `/nonexistent-dir/x.c`，被沙箱拦截（`hit restricted`）。故 114 这一数字取自「原 110（已实跑）
  + 本次 4 个新负例（已逐个复跑通过）」，而非一次整跑的输出。
