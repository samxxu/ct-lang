# PKG-25 · `ct.lock` 合并按叶子名去重，丢掉同名不同 publisher 的行

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct get` 的 lock 合并） |
| 定性 | bug（数据丢失） |
| 严重度 | Medium |
| 锚点 | v0.88.3（2026-11-23，PKG-17 探针发现） |
| 文件 | `selfhost/ct-ast/tool/pkg/Pkg.h.ct` 的 `pkg_lock_keep` |
| 状态 | open |

## 现象

同一个 `ct.lock` 里先装 `demo/hello@0.1.0`，再装 `acme/hello@0.1.0` 时，第二次 `ct get`
会把 `demo/hello` 的锁行删掉：`pkg_lock_keep` 把新装包按**叶子名**记入 `seen`，合并旧锁时
也只比较叶子名，于是所有 `*/hello` 行都被视为“本次已写”。

## 期望

- lock 行按完整身份 `<publisher>/<name>` 去重；
- 同名不同 publisher 的两行都保留；
- 同一身份重复写仍只保留一行；
- `ct verify --strict` 对两行都通过。

## 验收

- 探针：`ct get --index` 先 demo/hello 再 acme/hello，锁行数 2、两行都在；
- 既有 PKG-17 / pkg 套件绿；
- 不回退“同一身份只保留一行”。

## 处置（DEV，2026-11-23）：fixed

- **修复**：`get_one` / `fetch_git` 把本次解析到的包按完整身份
  `<publisher>/<name>` 记入 `seen`；`pkg_lock_keep` 合并旧锁时直接比较第一字段的完整
  身份，不再剥成叶子名。同一身份仍只保留一行，`demo/hello` 与 `acme/hello` 两行共存。
- **校验**：`pkg_verify_lock` 的重复行检查改为比较完整身份；只有精确重复的
  `<publisher>/<name>` 行才报 `is required twice`，同名不同 publisher 的合法锁行通过
  `ct verify --strict`。`ct build` 的依赖图裸名唯一规则（SP-006/SP-013）不变。
- **测试**：新增 `test/pkg/pkg25_lock_keep.sh`，接入 `test/pkg/run.sh`；用 PKG-17 的
  `index/two-publishers` 在同一工程里先取 `demo/hello` 再取 `acme/hello`，断言两行都在、
  `ct verify --strict` 接受两行、重复取一个身份仍只保留一行。
- **红证**：`baseline: fc5c0359`（test 提交 `1c008045` 的父提交），按 T-7 用
  `git archive fc5c0359` 重建 ct-ast 后运行：
  `CT_AST=<baseline>/ct-ast bash test/pkg/pkg25_lock_keep.sh` → exit 1，4 条断言红
  （lock 只剩 1 行、`demo/hello` 0 行、verify 只认 1 行、重复取后仍 1 行）。
- **绿证**：同一探针 9/9 OK；`test/pkg/pkg17_thirdparty.sh` 全绿；
  `test/pkg/run.sh` 156 passed / 0 failed；`tools/check.sh g0/g6/g8/g4` 均 exit 0。
- **状态**：issue 状态字段仍为 `open`（状态词归 REV/REQ）；DEV 主张 `fixed`，等待复核。
- **边界**：按本轮指令不 push、不打 tag、不改版本号；该行为改动未随 PATCH 移动。
