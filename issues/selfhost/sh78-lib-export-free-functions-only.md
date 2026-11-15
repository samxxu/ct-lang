# SH-78 · `--lib` 导出面只收根单元 `pub` 自由函数，`impl` 的 `pub` 方法不计入

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`--lib` 导出面） |
| 类型 | **设计口径**（不是缺陷） |
| 严重度 | Medium（只有方法的库必须再加一个自由函数才能构建） |
| 状态 | rejected（按 D39-2 / D42-10，不排期；补文档与诊断说明） |
| 锚点 | `v0.53.1`（`55d89e2b`）；实测 `ct-ast v0.53.1`（HEAD 重建） |

## 现象

根 `.h.ct` 只有 `pub struct` 与 `impl` 内的 `pub` 方法时，`--lib` 直接失败：

```console
$ ct build --lib -I . lib/lib.h.ct -o out
lib/lib.h.ct:1:1: error: no exported functions in 'lib/lib.h.ct'
```

补一个 `pub` 自由函数后同一条命令 rc=0。

## 最小复现

```sh
mkdir -p lib && cat > lib/lib.h.ct <<'EOF'
namespace lib;
pub struct Box { int n; }
impl Box {
    pub int get(void) { return self->n; }
}
EOF
CT_STD_DIR=<repo>/lib/std ct build --lib -I . lib/lib.h.ct -o out
```

### 实际输出

```text
lib/lib.h.ct:1:1: error: no exported functions in 'lib/lib.h.ct'
rc=1
```

追加 `pub int box_get(struct Box *b) { return b->n; }` 后 rc=0，`.ctbuild/lib.abi.h` 只列
`lib_box_get`，`Box` 的方法仍不在 ABI 面。

## 定性

**拒绝（设计）**：Phase 39 D39-2 明文「只导出根单元内有定义的 `pub` **函数**」；
Phase 42 D42-10 重申「方法不在 ABI 面」。当前行为与冻结卡一致，不是实现缺陷。

可选的只是诊断措辞：错误说「no exported functions」没错，但没告诉用户「`pub` 方法不算导出面」。
这属于文案改进，随文档提交，不单独立 patch。

## 落点

不排期。若要让 C 消费者直接拿到类型方法，那是新的导出面设计（B，新 phase），
需先改 D39-2 / ABI 契约，不能按 bug 修。

## 文档动作

`package-guide` 的 `--lib` 段补：「导出面 = 根单元 `pub` 自由函数；`impl` 内的 `pub` 方法不导出，
需要给 C 调用方包一个自由函数」。
