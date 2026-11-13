# Phase 34 / 36 最终签核（r9）

- 对象：`d9fb14c`（P34 `1+/1−`、P36 `4+/4−`）
- 范围：只验这五处 diff；实测用 `/bin/sh`，未跑 `check-all.sh`，未改任何文件。
- 约束：未碰 `phase31.md`；`2026-11-11/` 未提交。

## 五项结论

| # | 项目 | 结论 | 一句话证据 |
| --- | --- | --- | --- |
| 1 | P34 假绿修复 | **PASS** | L202 已是 `d="$mod-p34g"`/`d="$mod-p34b"`；位置在 `mod="$work/mod"`（`check-ast.sh:889`）之后的 modules 段；文本顺序为“各建目录 → build 成功后绑定并守卫” |
| 2 | P34 守卫 | **FAIL（仅 (b)）** | (a) 空/不存在/非 `.c` 均走 `else bad`，(c) `if` 能阻断；但 `set --` 是**顶层**执行，不在子 shell/函数内，实测污染外层位置参数 |
| 3 | P34 `case` 失败分支 | **PASS** | 空串→BAD、`T(2) `→BAD、`T(1) `→OK；带换行的 `T(1)\nX` 也 OK（`*` 跨换行匹配，语义上仍是“含残留”） |
| 4 | P36 谓词统一 | **PASS** | ③ 与 S1a 都写 `find_trait(...) < 0`；用户 `trait Drop`（`find_trait >= 0`）走 `adopt_use` + vtable，内建走 `has_drop_impl` + 无 vtable |
| 5 | P36 两条 Low + 编号 | **PASS** | S1a 明写“新增 `for` 解析、今天报错”，`~25–40` 与 60–100 相容；E36-1 改为“文件内 2 行、只数定义行期望 1”；§7 标题、E36-14、§12 均为 225–227 / 229–232、228 属 P34 |

## 唯一未过项：2(b) `set --` 污染顶层位置参数

卡片 L202 的实际片段是顶层执行：

```sh
d="$mod-p34g"; if set -- "$d"/*.c && [ -f "$1" ]; then ...; else bad ...; fi
```

`sh` 实测：

```text
$ /bin/sh -c 'set -- outer1 outer2; if set -- a b && true; then :; fi; echo "after if: $1 $2 ($#)"'
after if: a b (2)
$ /bin/sh -c 'set -- outer1 outer2; if ( set -- a b && true ); then :; fi; echo "after subshell: $1 $2 ($#)"'
after subshell: outer1 outer2 (2)
```

四个目录情形本身是对的（`missing`/`empty`/`non-c` → `ELSE bad`，`one` → `THEN`），`if` 在只有 `set -u` 的脚本里也确实阻断。问题只在卡片同时写了“`set --` 放子 shell 或函数内”，而片段没有做到。

**修法（一行，已实测）**：把条件包进子 shell——

```sh
d="$mod-p34g"; if ( set -- "$d"/*.c && [ -f "$1" ] ); then tp=...; else bad ...; fi
```

外层 `$1 $2` 保持不变（实测 `outer: OUT1 OUT2 (2)`），四种目录情形结果不变。若不想用子 shell，改成先取第一个文件：`first=$(for f in "$d"/*.c; do printf '%s' "$f"; break; done); [ -f "$first" ]`。

## 终态

五项中 1/3/4/5 通过，**2(b) 未过**，因此本轮**不签 GO**；只差上述一行（子 shell 包裹或函数内 `set --`）。改完后 34/36 即可冻结、进入实施排期。
