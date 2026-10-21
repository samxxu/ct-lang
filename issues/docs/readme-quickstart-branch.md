# DOC-20 · README 快速开始 1b 只构建 `ctc`，后续步骤却调用 `ct`

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Low** |
| 锚点 | commit `dde0dda`（2026-10-21） |
| 文件 | [README.md:33-43](../../README.md#L33-L43)（中文）、[:477-486](../../README.md#L477-L486)（英文） |
| 状态 | ✅ 已修复（2026-10-21，`README.md` 中英快速开始第 2 步给出 `ct` / `./ctc` 两条分支） |

## 现象

快速开始给了两条并行路线：

```bash
# 1a) 直接安装 …
curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh

# 1b) 或者不安装，只用 L0 种子（单文件、核心语法）
gcc selfhost/l0/ctc.c -o ctc

# 2) 编译 .ct 到 .c（同时生成同名 .h）
ct examples/01_greeter/greeter.ct -o /tmp/greeter.c
```

第 2 步、第 3 步统一写 `ct`。只走 1b 的读者手里只有 `./ctc`，第 2 步必然
`command not found`。英文段 `:477-486` 同样如此。

## 证据

`README.md:34-41`（中文）与 `:478-484`（英文）逐行对应；`1b` 分支只产出仓库根目录下的 `ctc`，
而后续两条命令都写 `ct`。

## 影响

首次上手的读者若选 1b（不想安装、只想试一下），会立刻卡住；也没有提示「1b 之后请把 `ct` 换成 `./ctc`」。

## 修复建议

在第 2 步给两条等价写法，或按分支标注：

```bash
# 2) 编译（装过 1a 用 ct；只做了 1b 用 ./ctc）
ct examples/01_greeter/greeter.ct -o /tmp/greeter.c      # 1a
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c   # 1b（L0 只支持核心语法）
```

中英两处同步。

## 验证

- 按 1b 分支逐条执行，命令全部可用；按 1a 分支执行同样可用。
- 文档改动不影响门禁（`bash selfhost/check-all.sh` 保持八关全绿）。
