# LANG-16 · 诊断位置源过期：块注释后列号偏移、`1:-3788` 类负列

| 项 | 值 |
| --- | --- |
| 模块 | lang（词法位置 + 诊断打印） |
| 类型 | **实现缺陷**（已有 `line`/`lstart` 跟踪，块注释分支漏更新；诊断未校验） |
| 严重度 | Medium（不挡编译，挡编辑器跳转 / CI 解析；位置可越界读） |
| 优先级 | **P2** —— 与 PH-58 的字段位置同向，可独立修 |
| 状态 | open |
| 落点 | patch **0.53.16** |
| 锚点 | `v0.53.0`（`~/.local/bin/ct`）与 `v0.53.1`（HEAD 重建 `ctc`） |
| 关联 | LANG-10（机读诊断）、PH-58（字段位置）；与 **PH-62 无依赖** |

## 现象

写入容器下标被拒时，诊断打印的列号与 `[` 的真实列不符：

```text
cmt.ct:4:29: error: a Map subscript is read-only; use put(k, v)       # 真实 4:17
cmt2.ct:4:29: error: a Vec subscript is read-only; use set(i, v)      # 真实 4:17
cmt3.ct:84:1364: error: a Map subscript is read-only; use put(k, v)   # 真实 84:4
```

更早的一次探针给出过**负列**：`b.ct:1:-3788`、`c.ct:1:-3796`、`e.ct:1:-3755`。

## 最小复现

```sh
mkdir -p /tmp/ctneg && cd /tmp/ctneg
cat > cmt2.ct <<'EOF'
int main(void) {
  Vec<int> v;
  v /* long
     comment */ [0] = 1;
  return 0;
}
EOF
CT_STD_DIR=<repo>/lib/std ctc cmt2.ct
```

同族变体：`cmt.ct`（Map）、`cmt3.ct`（80 行填充，`[` 在 84 行第 4 列）、
`cmt4.ct`（注释只跨一行，`[` 在 4 行第 4 列）。

### 实际输出

```text
cmt2.ct:4:29: error: a Vec subscript is read-only; use set(i, v)
ctc: 1 error(s) generated
```

## 触发条件

1. 写形式目标走到 `container_write_check`（`v[i] = x` / `m[k] = v` 被拒的路径）；
2. 接收者与 `[` 之间存在**跨行的块注释** `/* ... */`；
3. 该注释消费的换行没有经过主循环。

`//` 行注释不受影响：它不消费 `\n`，换行仍由主循环处理并更新 `lstart`。

## 位置怎么算

列号公式是 `col = tokstart - lstart + 1`
（[Lexer.h.ct](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct#L49)）。
`lstart` 只在主循环消费 `\n` 时更新
（[Lexer.h.ct](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct#L70)）：

```c
if (c == '\n') { self->bol = 1; self->line++; self->pos++; self->lstart = self->pos; continue; }
```

块注释分支只加 `line`，不更新 `lstart`
（[Lexer.h.ct](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct#L76-L83)）：

```c
if (c == '/' && self->src[self->pos + 1] == '*') {
    self->pos += 2;
    while (...) {
        if (self->src[self->pos] == '\n') self->line++;
        self->pos++;
    }
    ...
}
```

于是 `lstart` 停在注释**开始前**那一行的行首，列号被整段注释长度（含换行）撑大：

| 探针 | `lstart` 停在哪 | `tokstart - lstart` | 打印 | 应打印 |
| --- | --- | --- | --- | --- |
| `cmt4.ct` | 第 3 行行首 | 7 + 3 | `4:11` | `4:4` |
| `cmt2.ct` | 第 1 行行首 | 28 | `4:29` | `4:17` |
| `cmt3.ct` | 第 1 行行首 | 1363 | `84:1364` | `84:4` |

行号是对的（注释内逐个 `\n` 加了 `line`），错的是列；这正是「位置源过期」而非公式本身错。

## 负值从哪来

`-3788` 在 `v0.53.0` 与 HEAD 重建的 `v0.53.1` 上都**未复现**；两个二进制给出的都是上表的
「正确行号 + 偏大正列」。但负值与本条同类：**位置源缺失/失效后被原样打印**，诊断层没有兜底。

两条代码路径能产出 ≤0 的列（`-3788` 尚未逐条构造出来）：

1. `N_MCALL` 语法糖节点的 `num` 默认 0
   （[Arena.h.ct](../../selfhost/ct-ast/runtime/arena/Arena.h.ct#L102)）。
   `container_subscript_kind` 对自定义下标（`k==3`）校验 `num > 0`，对 `Vec`/`Map`（`k==1/2`）
   **不校验**（[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4018-L4043)）；
   任何未写入位置的糖节点都会把 0 或负值直接交给 `ct_sem_error`。
2. `container_write_check` 沿 `N_MEMBER`/`N_ARROW` 下钻取位置
   （[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4045-L4066)）；若链条 `.a == -1`，
   `at` 变 -1 后仍执行 `self->arena->nodes[at]`，即读 `nodes[-1]` 越界，打印相邻内存的垃圾值——
   可以解释「行号 1、列任意负数」这种组合。

`ct_sem_error` 直接 `fprintf(stderr, "%s:%d:%d: error: %s\n", ...)`
（[Diag.h.ct](../../selfhost/ct-ast/tool/diag/Diag.h.ct#L85)），不校验、不夹取。

## 定性

**A 类 bug**（既有承诺未实现），不是新能力：

- 位置本来就有：`Lexer` 已维护 `line` / `lstart`，诊断格式也承诺 `file:line:col`
  （与 LANG-10、PH-58 同向）；
- 块注释分支少一次 `lstart` 更新，是实现遗漏，不是设计拒绝；
- `col <= 0` 不是「未定义位置」的合法表达，原样打印属降级失败。

## 落点与判据（patch 0.53.16）

| ID | 断言 |
| --- | --- |
| P1 | `cmt4.ct` → `4:4`；`cmt2.ct` → `4:17`；`cmt3.ct` → `84:4`（行、列都对） |
| P2 | 块注释内每消费一个 `\n`，`line` 与 `lstart` 同步更新；多行注释后首个 token 列号正确 |
| P3 | 其它跳行路径（字符串/字符字面量内的换行）核对一次：同样更新位置，或显式拒绝，不留静默错位 |
| P4 | 任何诊断不得打印 `col <= 0`：诊断入口校验，非法值降级为「只打行」或 `col=1`，不得原样输出 |
| P5 | `container_write_check` 的 `at` 下钻遇 `-1` 立即返回，不得索引 `nodes[-1]` |
| P6 | 现有诊断文本除位置数字外零变化（golden），`ct check` / `compile` / `build` 三种出口一致 |

## 与 PH-62 的边界

- **互不依赖**：PH-62 是写语义（糖 + `set` 补齐 + 洞/释放/分配失败），LANG-16 是位置源与诊断兜底；
  PH-62 的 W1–W22 不含位置断言，LANG-16 的 P1–P6 不含写语义断言。
- 先后任意：先修 LANG-16 只让 PH-62 的报错位置变准，不改其行为；先做 PH-62 也不会让 LANG-16 消失。
- 唯一交集是 `frontend/parse/Expr.h.ct`：两条都碰时**合并串行**，开发可并行。
- 与 0.53.9（LANG-8）同改 `frontend/lex/Lexer.h.ct`，**必须串行**。

## 文件族

`frontend/lex/Lexer.h.ct`（主修）+ `tool/diag/Diag.h.ct`（校验/兜底）；
`frontend/parse/Expr.h.ct` 仅在加 `at < 0` 守卫或位置 helper 时触碰。

## 处置（2026-11-19，PH-72）

- 提交：`2a4c632f`
- 改动：块注释内换行同步 `lstart`/`bol`
- 验证：`sh test/ast/p72_diagpos.sh <ct-ast>` → 列号 `5:17`（修复前 `5:29`）

## 处置（2026-11-20，DEV · 复跑）

- 结论：PH-72 的修复仍在 HEAD；只记录证据，不改 `status`。
- 命令/输出：

```console
$ bash test/ast/p72_diagpos.sh /tmp/ci9-sh93-build/ct-ast
OK p72/diagpos (pp length + comment column)
```
