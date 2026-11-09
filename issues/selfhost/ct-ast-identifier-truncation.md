# SH-23 · ct-ast 静默截断超长标识符（160 字符），与 spec「>127 报错」相反且可致重定义

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | **High** |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 站点 | [Lexer.h.ct:97-108](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct#L97-L108)（`#define MAX_TEXT 160`，[:18](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct#L18)） |
| 状态 | 已修（`67da4c3`，2026-11-09 回填） |

## 现象

`docs/language-spec.md` 明确要求：

- [:59](../../docs/language-spec.md#L59)：固定容量上限越界**一律报错，不静默截断**；
- [:63](../../docs/language-spec.md#L63)：标识符「超出 127 字符会**报错**（`identifier too long`），不再静默截断」；
- 英文同义见 [:1424-1425](../../docs/language-spec.md#L1424-L1425)。

ct-ast 的词法器对标识符的处理是：

```c
if (n + 1 < MAX_TEXT) { self->toktext[n] = self->src[self->pos]; n++; }
self->pos++;
```

`MAX_TEXT` 为 160，`toktext` 可容纳 159 字符 + NUL；第 160 个字符起的尾部被**丢弃**、
扫描游标却继续前进，最终 `toktext` 只剩前 159 字符，
**既无 `identifier too long`，也 `exit 0`**。符号表随后按截断名落库
（`Symbols.h.ct` 的 `snprintf(..., MAX_TEXT, "%s", name)`）。

## 证据（探针）

> **订正（2026-11-09）**：本节原始探针有误。原文用 `a = "a" * 159` 与 `b = "a" * 158 + "b"`
> 构造「前 159 字符相同」的两个名字，但两者都是 159 字符，都能完整装入 `toktext`，
> **不会发生截断，也不可能出现 `redefinition`**；原文第 44 行的报错不可复现。
> 正确的触发输入是 160 字符：`a = "a" * 160`、`b = "a" * 159 + "b"`，两者都只剩前 159 字符而重名。

```bash
# 两个 160 字符标识符前 159 字符相同、仅末尾不同
python3 - <<'PY' > /tmp/idc.ct
a = "a" * 160
b = "a" * 159 + "b"
print(f"int {a} = 1;")
print(f"int {b} = 2;")
print("int main(void) { return 0; }")
PY
$ /tmp/a/ct-ast /tmp/idc.ct -o /tmp/idc.c ; echo "exit=$?"
exit=0
$ gcc -Wall /tmp/idc.c -o /tmp/idc
/tmp/idc.c:7:9: error: redefinition of 'aaa…（159 个 a）'
```

同一输入在 L0（`selfhost/l0/ctc.c`）上也是 `exit 0`，说明截断行为并非 ct-ast 独有；但
`language-spec` 的两处表述都以「已修」口吻写作，与两个实现均不符（修复后 ct-ast 已改为报错，
L0 仍按冻结层现状）。

## 影响

- **静默改变语义**：两个不同标识符被合并成同名符号，生成物直接触发 C 的重定义错误——违反
  「不生成明知编译不过的 C」的既有约定；
- 规格与实现相反，用户无法通过诊断发现；
- 与 `MAX_TEXT 160` 的容量账本冲突：规格写 127 报错，实现用 160 截断；
- 属 [TEST-9](../testing/test9-cap-limits-untested.md) 空白区的典型后果：没有夹具时无人发现。

## 修复建议

1. 在词法器扫描标识符时计数；超过上限（建议把上限统一为规格的 127，或把规格改为 159 并说明）
   立即走 `ct_sem_error` 报 `identifier too long` 并 `exit 1`；
2. 若改规格口径，需同步 `docs/language-spec.md` 的四处（59 / 63 / 1311 / 1424）；
3. 补一条负例：>127（或 >159）字符的标识符必须非零退出并带位置诊断；
4. 注意冻结层边界：L0 / L1 / L2 不改；修复只落 `selfhost/ct-ast/**`（若 L0 也要修，属冻结期
   缺陷修复，需按 AGENTS §2 的判据与登记流程走）。

## 验证

修复后两个探针分别得到 `identifier is too long`（exit 1）与正常编译；新增负例在 `check-ast.sh` 中通过；
`bash selfhost/check-all.sh` 九关全绿。

## 处理（2026-10-31 修复，2026-11-09 回填）

已修复（ct-ast）：标识符超过 159 字符报 `identifier is too long`，不再静默截断；新增负例
`test/ast/errors/identifier_too_long.ct`。L0 / L1 / L2 属冻结层未改，language-spec 已改为如实描述各层的上限。

- 修复提交：`67da4c3`。
- 验证证据：`test/ast/errors/identifier_too_long.ct` 存在，由 `check-ast.sh` 断言非零退出并带位置诊断；
  2026-11-09 在干净克隆（`6da3ce4`）上复跑 `bash selfhost/check-all.sh`，
  `check-ast: 765 passed / 0 failed`，11 道门禁全绿。
