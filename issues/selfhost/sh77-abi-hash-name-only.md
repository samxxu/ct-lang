# SH-77 · `ABI_HASH` 只覆盖导出名，判不出签名级漂移

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`--lib` ABI 头） |
| 类型 | **设计口径**（不是缺陷） |
| 严重度 | Low（`.abi.h` 原型已逐行变化，签名漂移仍可观测） |
| 状态 | rejected（按 D39-12 / D42-10，不排期；只补文档） |
| 锚点 | `v0.53.1`（`55d89e2b`）；实测 `ct-ast v0.53.1`（HEAD 重建） |

## 现象

`--lib` 产出的 `<base>.abi.h` 里 `ABI_HASH` 由「导出名排序后的 FNV-1a」算出，不含返回类型 /
参数类型；把导出函数 `int box_get(struct Box *)` 改成 `long box_get(struct Box *)`，
原型变了，哈希不变。

## 最小复现

```sh
mkdir -p lib && cat > lib/lib.h.ct <<'EOF'
namespace lib;
pub struct Box { int n; }
pub int box_get(struct Box *b) { return b->n; }
EOF
CT_STD_DIR=<repo>/lib/std ct build --lib -I . lib/lib.h.ct -o out
grep ABI_HASH .ctbuild/lib.abi.h      # 0x6cdaf7f5
sed -i '' 's/pub int box_get/pub long box_get/' lib/lib.h.ct
CT_STD_DIR=<repo>/lib/std ct build --lib -I . lib/lib.h.ct -o out
grep ABI_HASH .ctbuild/lib.abi.h      # 仍是 0x6cdaf7f5
```

## 实测原文

```text
#define LIB_ABI_HASH 0x6cdaf7f5
...
int lib_box_get(struct lib_Box *);
```

改签名后：

```text
#define LIB_ABI_HASH 0x6cdaf7f5
...
long lib_box_get(struct lib_Box *);
```

## 定性

**拒绝（设计）**，不是 bug：

- Phase 39 D39-12 明文定义哈希 = **导出名**排序后的 FNV-1a；
- Phase 42 D42-10 明文要求「不以 `ABI_HASH` 单独作证据」，签名面以 `.abi.h` 逐字节 diff 为准；
- 本次实测里 `.abi.h` 原型确实从 `int` 变成 `long`，ABI 漂移**可观测**，只是哈希不承担这个职责。

## 落点

不排期。需要签名级摘要时另立新特性（改哈希输入 = 已发布契约变更），归工具链 phase，
不在本轮的 patch 队列里。

## 文档动作

在 `package-guide` 的 `--lib` 段补一句：「`ABI_HASH` 只覆盖导出名；签名漂移请 diff `.abi.h`」。
