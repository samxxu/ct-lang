# LANG-11 · 同名 `.h.ct` + `.ct` 单元在 `ct build` 下产物冲突，C 式声明/定义分离不可用

| 项 | 值 |
| --- | --- |
| 模块 | lang（多单元构建 / 产物命名） |
| 严重度 | **High**（单元表承诺的配对形态不可用） |
| 优先级 | **P1** —— 挡住「`.h.ct` 接口 + `.ct` 实现」的包布局；有绕法但要把实现单元改名 |
| 状态 | open |
| 锚点 | `v0.53.1`（`3337ac7a`）；实测二进制 `ct v0.53.0` |
| 类型 | **实现缺陷**（不是语言设计拒绝） |

## 精确触发条件

同一目录下同时存在 `<base>.h.ct` 与 `<base>.ct`，且两者都进入一次 `ct build`：

- 只 `import <base>`：`.h.ct` 被编译，同目录 `.ct` **不**被自动编译 → 链接期缺符号；
- 把 `.ct` 也作为入参：两个单元都写到 `.ctbuild/<base>.c`，后写覆盖先写，
  `cc` 行同时列入两次 → `duplicate symbol`。

## 最小复现

```sh
mkdir -p /tmp/lcb/p4/lib /tmp/lcb/p4/app
cat > /tmp/lcb/p4/lib/cfg.h.ct <<'EOF'
pub extern int K;
pub extern int ARR[3];
EOF
cat > /tmp/lcb/p4/lib/cfg.ct <<'EOF'
int K = 5;
int ARR[3] = { 1, 2, 3 };
EOF
cat > /tmp/lcb/p4/app/main.ct <<'EOF'
import lib::cfg;
int main(void) { return K + ARR[1]; }
EOF
cd /tmp/lcb/p4
CT_STD_DIR=<repo>/lib/std ct build -I . app/main.ct lib/cfg.ct -o out
```

### 实际输出

```text
'cc' -std=c99 -I '.ctbuild' ... '.ctbuild/main.c' '.ctbuild/cfg.c' '.ctbuild/cfg.c' '-o' 'out'
duplicate symbol '_K' in:
    /var/folders/.../cfg-a54c9a.o
    /var/folders/.../cfg-8b58ac.o
duplicate symbol '_ARR' in:
    ...
ld: 2 duplicate symbols
rc=1
```

只传 `app/main.ct`（不传 `lib/cfg.ct`）时：

```text
Undefined symbols for architecture arm64:
  "_K", referenced from:
      _main in main-910c51.o
  "_ARR", referenced from:
      _main in main-910c51.o
rc=1
```

## 期望行为

- `ct build` 对同 base 的 `.h.ct` / `.ct` 使用不同的产物路径（或把 `.ct` 作为 `.h.ct` 的实现单元自动带上）。
- 每个 `.c` 在 `cc` 行只出现一次；头文件里的 `extern` 声明与实现单元的定义能链接。
- C 式分离（头声明 + 实现定义）在非 namespace 下应可用；namespace 下的 mangling 另行裁定（见 §影响面）。

## 规范依据

单元表把 `.ct` 定义为「实现 / 入口；接口写在同目录的 `.h.ct`」：
[language-spec.md:616](../../docs/language-spec.md#L616)。`pub` 全局的导出规则是
`.h` 发 `extern`、`.c` 发定义（[:774-775](../../docs/language-spec.md#L774-L775)）。
当前实现没有兑现「同目录 `.h.ct` 是实现单元的接口」这条配对。

## 影响面与绕法

- 影响任何按「接口 / 实现」拆单元的包；`src/<ns>/` 布局的包会同时撞 PKG-2。
- 绕法：实现单元改用不同 base（如 `cfg_impl.ct`）并作为入参；或把定义也写进 `.h.ct`
  （`pub int K = 5;`，此时 `.h` 发 `extern`、`.c` 发定义，可用）。
- namespace 下的 C 式分离另有符号问题：`pub extern` 不 mangling（[spec:778-779](../../docs/language-spec.md#L778-L779)），
  而 `.ct` 定义按 namespace mangling（[:783-784](../../docs/language-spec.md#L783-L784)），
  两者对不上；这一半归 namespace 常量/限定名的并行登记，不在本条修。

## 修复方向

1. **产物命名**：`.h.ct` → `.ctbuild/<base>.c`，`.ct` → `.ctbuild/<base>.impl.c`（或按单元类型分目录）；
   `cc` 行去重。
2. **自动配对**：`import <base>` 解析到 `.h.ct` 时，若同目录存在 `<base>.ct`，把它作为实现单元加入构建
   （与 `.m.ct` 的解析顺序分开；`.m.ct` 已有歧义规则）。
3. 同步单元表 / 教程，写清「同 base 的 `.ct` 是否自动配对」。

## 回归用例应断言

- 两单元工程 `ct build -I . app/main.ct lib/cfg.ct -o out` rc=0；
- `cc` 行中 `cfg.c` / `cfg.impl.c` 各出现一次；
- `cfg.h` 含 `extern int K;`，实现 `.c` 含 `int K = 5;`；
- 只 `import lib::cfg` 时，`ct build` 自动带上 `lib/cfg.ct`（若采纳自动配对）；
- 既有 `.h.ct` 单文件工程产物路径与内容零变化。

## 处置（2026-11-19，PH-72）

- 提交：`c45e41fb`
- 改动：`load_unit` 按 basename 查重，同 base 的 `.h.ct`/`.ct` 硬错
- 验证：`sh test/ast/p72_outputcollision.sh <ct-ast>` → `OK p72/collision`（报 `both emit 'cfg.c'`）

## 处置（2026-11-20，DEV · 复跑）

- 结论：PH-72 的修复仍在 HEAD；只记录证据，不改 `status`。
- 命令/输出：

```console
$ bash test/ast/p72_outputcollision.sh /tmp/ci9-sh93-build/ct-ast
OK p72/collision (same-base refused)
```
