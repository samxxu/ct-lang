# DOC-14 · 关卡脚本头注释滞后：断言数 20 vs 21，覆盖阶段缺 11.x / 12.x

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Low** |
| 锚点 | commit `4ef8b68`（2026-10-21） |
| 文件 | [selfhost/check-all.sh:16](../../selfhost/check-all.sh#L16)、[:18-19](../../selfhost/check-all.sh#L18-L19)、[:60](../../selfhost/check-all.sh#L60)；[selfhost/check-ast.sh:3-4](../../selfhost/check-ast.sh#L3-L4) |
| 状态 | ✅ 已修复（2026-10-21；验证见 [issues/README.md](../README.md) 的「Phase 12 复审」一节） |

## 现象

- `check-all.sh` 的关卡清单写「editor grammar (**20 assertions**)」；实测该关卡输出 `== 21 checks, 0 failed ==`（AGENTS §6 也写 21）。
- `check-all.sh` 第 8 关的描述与运行标签写「AST compiler (Phase 9.1–9.7 + 10.x)」；但 `check-ast.sh` 实际上还包含 Phase 11（map 构造、11.3 加固）与 Phase 12.1（bindings）两节。
- `check-ast.sh` 第 3 行头注释写「Phase 9.1-9.7, Phase 10.x」，与其自身 11.1/11.2/11.3/12.1 的说明段不一致。

## 影响

关卡脚本是维护者判断「这道关卡覆盖到哪」的第一手材料；标签落后会让 Phase 11/12 的用例被误认为无门禁保护。

## 修复建议

- 20 → 21；
- 第 8 关标题统一为「Phase 9.1–9.7 + 10.x + 11.x + 12.1」（`check-all.sh` 与 `check-ast.sh` 同步）；
- 顺带核对 `check-ast.sh` 头部的断言计数（若各处引用旧数，一并订正）。

## 验证

`check-all.sh` / `check-ast.sh` 的标签与 `check-grammar.py` 实际输出、`check-ast.sh` 实际章节三者一致。
