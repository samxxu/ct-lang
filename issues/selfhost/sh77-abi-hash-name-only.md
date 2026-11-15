# SH-77 · `ABI_HASH` 只覆盖导出名，判不出签名级漂移

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`--lib` ABI 头） |
| 类型 | **已由既有需求承接**（不是新缺陷） |
| 严重度 | Low（`.abi.h` 原型已逐行变化，签名漂移仍可观测） |
| 状态 | superseded（并入 [REQ-ABI-2](../../docs/planning/requirements-pool.md#L162)，P2，触发条件 = 下游需要 `#if` 编译期 pin） |
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

**不是新缺陷**：Phase 39 D39-12 明文定义哈希 = 导出名排序后的 FNV-1a；Phase 42 D42-10 明确
「不以 `ABI_HASH` 单独作证据」，签名面以 `.abi.h` diff 为准。本次实测里 `.abi.h` 原型确实从
`int` 变成 `long`，ABI 漂移可观测。

该需求已登记为 [REQ-ABI-2](../../docs/planning/requirements-pool.md#L162)（P2，open）：
仅当下游出现 `#if` 编译期 pin 需求时才改哈希输入；否则按 REQ-ABI-1 的「重新生成 + 归一化 diff」。
本条 superseded，不再单独排期。

## 落点

随 **REQ-ABI-2** 的触发条件；不占 patch、不占 phase。触发前只补文档。

## 文档动作

在 `package-guide` 的 `--lib` 段补一句：「`ABI_HASH` 只覆盖导出名；签名漂移请 diff `.abi.h`」。
