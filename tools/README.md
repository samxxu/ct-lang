# tools/ 工具索引

面向仓库维护者的小工具；都是 std-lib Python 或 POSIX shell，不装依赖。

| 工具 | 用途 | 入口 |
| --- | --- | --- |
| `check.sh` | 治理门禁 G0–G9 与 `lint` 子命令的统一入口 | `bash tools/check.sh g0` … `g9`、`bash tools/check.sh lint` |
| `migrate_lint.py` | **P-1.3 迁移 lint**：指针时代站点的三档 dry-run（可自动 / 需人工 / 语义需确认） | `python3 tools/migrate_lint.py` |
| `check-feature-matrix.py` | S8c 特性矩阵一致性（`g4` 调用） | `python3 tools/check-feature-matrix.py --strict` |
| `p85_inventory.py` | 语料清单 / sha256 pin（改动 `examples/**` 后重生成） | `python3 tools/p85_inventory.py …` |
| `limits_sync.py` | 容量上限镜像一致性 | `python3 tools/limits_sync.py --check` |
| `sh94_split_check.py` | SH-94 拆分的函数体多重集检查 | `python3 tools/sh94_split_check.py …` |

## migrate_lint.py（P-1.3）

```sh
python3 tools/migrate_lint.py --selftest              # 正/负夹具，13 例
python3 tools/migrate_lint.py                          # 三档汇总（dry-run）
python3 tools/migrate_lint.py --list                   # 按档列出站点
python3 tools/migrate_lint.py --format tsv             # 站点明细
python3 tools/migrate_lint.py --files                  # 每个文件一行（清单）
python3 tools/migrate_lint.py --format json            # 机器可读
```

- **只读**：没有 `--write`，不修改任何 `.ct`；dry-run 是唯一模式。
- 扫描 `examples/`、`test/`、`lib/` 的 `.ct`；按 [test/c-boundary-allow.tsv](../test/c-boundary-allow.tsv)、
  `.m.ct`/shim 同目录、`map trait`、`#ct-raw`、`lib/**`、负例/历史夹具把 C 边界站点归入 `keep`，
  不计入三档百分比。
- 三档定义、规则表、最新百分比与清单：见
  [docs/planning/j6-evidence/p1_3_lint.md](../docs/planning/j6-evidence/p1_3_lint.md)。
- `tools/check.sh g4` 会跑 `--selftest`；`tools/check.sh lint` 跑自测 + 汇总。

改规则时先改 `--selftest` 的夹具（正例 + 反例），再跑 `tools/check.sh g4` 与 `lint`。
