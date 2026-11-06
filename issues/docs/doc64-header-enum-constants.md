# DOC-64 · C 头文件的 enum 常量在表达式里不可见，但文档没有写明

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Medium |
| 锚点 | commit `c27da3d`（`v0.19.1` + 1 commit，2026-11-03）；本机 `ct v0.19.1` 复现 |
| 文件 | [docs/language-spec.md:1191](../../docs/language-spec.md#L1191)（只写「不展开 `#include`」）；[L1193-1200](../../docs/language-spec.md#L1193-L1200)（大写宏的放行规则） |
| 状态 | 待处理 |

## 现象

ct 不展开 `#include`，头文件里的 `enum` 常量对解析器就是未知名字。文档只写了「头文件里的 typedef
按类型处理」，没有说明**enum 常量在表达式里会报 `use of an undeclared variable`**，也没有给出
shim 写法。对接 macOS / iOS SDK 时这是第一道门槛。

同时要注意：大写 `#define` 的宏对象**能**透传（被当作宏名放行），原文「enum 常量 / 宏对象都不可见」
并不准确。

## 证据

```text
/* hdr.h */
enum { kFoo = 7 };
#define K_BAR 9

/* only_enum.ct */
#include "hdr.h"
#include <stdio.h>
int main() { printf("%d\n", (int)kFoo); return 0; }

$ ct compile only_enum.ct -o e.c
only_enum.ct:3:38: error: use of an undeclared variable
```

```text
/* only_macro.ct */
#include "hdr.h"
int main() { printf("%d\n", (int)K_BAR); return 0; }

$ ct compile only_macro.ct -o m.c
rc=0
```

外部评估 §4.4 的结论方向正确（enum 常量必须过 shim），但对宏的表述过宽。

## 影响

Medium：不是编译器缺陷，而是**未文档化的必然边界**。每个平台 SDK 的头文件都含大量 enum（AudioToolbox
的 `kAudioFormatMPEG4AAC`、CoreFoundation 的常量组），用户会在第一小时撞上这条错误，却不知道
「写 shim 返回常量」或「`#ct-raw`」是既定解法。

## 修复建议

1. 在 `docs/language-spec.md` §4.33（头文件里的类型名）或 §6.2 已知限制补一段：
   「头文件里的 `enum` 常量不可见；大写 `#define` 可透传」；
2. 教程 / binding 五步法补一个最小 shim 示例：

   ```c
   static inline int ct_kAudioFormatMPEG4AAC(void) { return kAudioFormatMPEG4AAC; }
   ```

3. 说明判定依据（解析器只登记 `.ct` 内声明的类型 / 常量），避免读者以为是 bug；
4. 是否做 `ct-bindgen` 属能力决策（外部评估 S6），不在本条范围。

## 验证

- 文档新增段落覆盖「enum 常量」「大写宏」「shim 写法」三点；
- 示例可被 `ct build` 编译通过；
- `python3 test/docs/check-docs.py` 通过。
