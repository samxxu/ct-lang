# SH-10 · 生成物触发 `-Wall -Wextra` 告警家族

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast / L2 同） |
| 严重度 | **Low** → **Medium**（2026-10-21 复核升级：发现三类告警、多个语料） |
| 锚点 | commit `dde0dda`（2026-10-21） |
| 文件 | [backend/emit/Emit.h.ct:493](../../selfhost/ct-ast/backend/emit/Emit.h.ct#L493)、[:531](../../selfhost/ct-ast/backend/emit/Emit.h.ct#L531)（`_self` 发射）；Emit.h.ct 各 vtable / wrapper / Drop 函数发射点 |
| 状态 | ✅ 已修复（2026-10-21，分两步）：① `_self` 未使用——方法体未引用 `self` 时补 `(void)_self;`（与既有 Drop 同法）；② 未被引用的 vtable / `Drop_drop`——三处发射点（vtable 前向声明与定义、map 实例 vtable、Drop 函数定义）统一加 `__attribute__((unused))`，与既有 `__ct_init` 的 `__attribute__((constructor))` 同源。复扫 69 个生成物，发射器产出的告警归零 |

## 现象

对 ct-ast 生成的 `.c` 文件跑 `gcc -Wall -Wextra -std=c99`，出现三类告警：

| 告警 | 原因 | 语料 |
| --- | --- | --- |
| `-Wunused-variable: '_self'` | impl 方法体第一行固定强转，方法内未引用 `self` | `02_multi_trait.c:38`、`04_signatures.c:23,32`、`sig_mismatch.c:20`、`sig_mismatch_json.c:20` |
| `-Wunused-variable: '<Trait>_<Struct>_vtable'` | 发射了 trait 的 vtable 但程序从未调用该 trait 的方法 | `04_signatures.c:35`（`Dict_Hashable_vtable`）、`13_map_instance.c:24`（`uart1_Controller_vtable`） |
| `-Wunused-function: '<Struct>_<Trait>_<method>'` | 发射了 Drop / map wrapper 函数但程序从未调 `delete` 或 map 实例 | `map/prog.ct`、`map_file/prog.ct`、`map_file_build/prog.ct`（`Person_Drop_drop`） |

三类均为 `static` 对象（vtable / Drop 函数 / wrapper 函数）——编译器不消除死代码，clang/gcc 因此告警。

## 证据（全量扫描，2026-10-21）

```text
test/cases (25 正例):
  02_multi_trait: 1 warning (_self)
  04_signatures: 3 warnings (_self x2 + Dict_Hashable_vtable)

test/ast (18 正例):
  13_map_instance: 1 warning (uart1_Controller_vtable)

test/modules (46+ .ct 文件):
  sig_mismatch / sig_mismatch_json: 各 2 条 _self 警告
  map / map_file / map_file_build: 各 1 条 Person_Drop_drop 警告
  leak 系列: p unused（源文件层面，非编译器 bug）
```

**零告警的子集**：examples（7 个正例，全 clean）、ct-ast 自举产物 20 个 `.c`（全 clean）、test/ast/01-12/14-18（全 clean）。

## 影响

- 生成物在 `-Wall -Wextra` 下不干净；用 `-Werror` 的用户直接编不过。
- **`_self` 告警**：L2 与 ct-ast 同源，L0 也一样；属既有行为，不是 ct-ast 引入。
- **未被引用的 vtable / Drop 函数**：ct-ast 独有（L2 不发射 map 绑定的 Drop wrapper 时不触发）。
- 测试套件（check-all.sh）**不检查生成物的 `-Wall -Wextra` 干净度**——只对 ct-ast 自身的 `.c` 构建跑告警检查，对 `test/cases/*.c`、`test/ast/*.c`、`examples/*.c` 的生成物没有这层门禁。

## 修复建议

两类处理，任选其一：

**方案 A（发射器侧）**：对 `_self`、vtable、Drop 函数的发射点逐一判断是否会被引用，不引用则不发射。这要在发射器层面引入「可达性分析」，改动面大。

**方案 B（局部抑制，改动最小）**：
- `_self`：方法体改写后扫一遍，若无 `self` / `_self` 引用则追加 `(void)_self;`（与 `docs/design/phase6.md:106` 记录的既有做法一致——那里是手写在 CT 源里，这里可由发射器代劳）。
- vtable / Drop 函数：在发射后追加 `(void)<obj>;` 抑制告警；或改用 attribute `__attribute__((unused))`。

注意：这会改动生成物，属于**行为变更**，需要用户确认并按规约重新生成受影响的 golden（check-goldens 的语料等价只比运行结果，不动运行输出）。

## 验证

- 上面的复现：`gcc -Wall -Wextra -std=c99` 零警告，运行输出不变。
- 回归面：`bash selfhost/check-all.sh` 八关全绿；若产物发生变化，需按 AGENTS §5 重新生成基线并逐条核对。
