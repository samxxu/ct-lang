# DOC-53 · spec §6.1 仍写「trait / struct 重名不报错」，实际已报 `duplicate`

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Low（一句话过期，方向上「低估了编译器」而不是高估） |
| 锚点 | commit `dab1b71`（`v0.16.2`，2026-11-02） |
| 文件 | [language-spec.md:1460-1461](../../docs/language-spec.md#L1460-L1461) |
| 状态 | 已修（2026-11-02，`v0.16.3`）：§6.1 中英改为「ct-ast 报 `duplicate`；L0 / L2 仍取最先出现者」 |

## 现象

§6.1「不做的检查」仍写：

```text
**不做**的检查：方法签名是否与 trait 一致（…）；
trait / struct 是否重名（`find_*` 取最先出现者，后者不可达，不报错）。
```

后半句已经不成立：ct-ast 对重名 trait / struct 都会报错。

## 证据

```text
$ ct dup.ct -o dup.c ; echo $?
dup.ct:2:9: error: duplicate trait 'T'
ctc: 1 error(s) generated
1
$ ct dup2.ct -o dup2.c ; echo $?
dup2.ct:2:10: error: duplicate struct 'S'
ctc: 1 error(s) generated
1
```

实现位置：[Parser.h.ct:1680](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1680)（`duplicate trait '%s'`）。

## 影响

- 读者会按「后者不可达、不报错」去设计名字，或以为重名是允许的；
- 第三方评估（`v0.16.2`）§3.1 也照这句写成「取最先出现者」，说明它仍在误导外部评审。

## 修复建议

1. 把该行改为「trait / struct **重名**：报 `duplicate trait '<name>'` / `duplicate struct '<name>'`
   （ct-ast 已校验；L0 / L2 仍取最先出现者）」——若冻结层行为不同，需按 `language-spec` 的
   代际标注惯例写清；
2. 同一句里的「方法签名不比对」保持不变（实测仍不比对，签名检查属定位取舍，见
   [issues/README](../README.md) 的「第三方评估复核（2026-11-02）」一节）。

## 验证

- 按上两条最小用例复跑，文档结论与 `exit 1` 一致；
- 只动文档，九关不受影响。

## 关联

- [SH-46](../selfhost/sh46-trait-method-ambiguity.md)：方法名的歧义仍无诊断（与类型重名不同）
- 第三方评估（`v0.16.2`）§3.1 的同类陈述
