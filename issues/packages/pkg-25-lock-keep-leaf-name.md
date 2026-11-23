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
