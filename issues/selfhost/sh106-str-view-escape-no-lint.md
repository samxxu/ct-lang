---
id: SH-106
title: "Str 借用视图逃逸（返回局部/String owner 的视图）无 lint，悬垂只在运行期暴露"
status: verified
area: selfhost
severity: P2
opened: 2026-11-21
confirmed-by: battle/ct-guide-1
---

# SH-106 · `Str` 视图逃逸没有编译期告警

## 来源

[battle/ct-guide-1 判决](../../battle/ct-guide-1/verdict.md) §3、F4/F5；
[language-spec §4.70](../../docs/language-spec.md#L2885-L2927)；
[test/ast/p79_places.sh:184](../../test/ast/p79_places.sh#L184)（`E79-6` 只覆盖 `T[]`）。

## 结论

`Str` 是借用视图（`{char *data; int len;}`，无 Drop）。当前 v0.84.1 对下列两种逃逸
**既不报错也不告警**，`ct check` / `ct check --types` 均静默：

1. 返回局部 `String` 的视图（owner 在函数出口释放）；
2. 从临时接收者取视图（临时量的 owner 在全表达式结束后释放）。

`T[]` 切片已有 `E79-6 slice escape` 警告，`Str` 没有对应检查。结果就是：C 程序员按
“借一张纸条”的心智写代码，编译器不拦，运行期读到已释放 buffer；没有 ASan 时可能静默通过。

## 复现（`ct v0.84.1`）

```ct
/* /tmp/str_escape.ct */
Str f(void)
{
    String s = str_dup("x");   /* 非 immortal：owner 在 f 出口 release */
    return s.as_str();
}

int main(void)
{
    Str v = f();
    return v.byte_at(0) == 'x' ? 0 : 1;   /* 读已释放 buffer */
}
```

```console
$ ct build /tmp/str_escape.ct
'cc' ... '.ctbuild/str_escape.c' '-o' 'a.out'     # exit 0
$ ct check /tmp/str_escape.ct
$ ct check --types /tmp/str_escape.ct
                                                  # 静默
```

同一仓库内的 `test/ast/p79_places.sh:184` 对 `T[]` 返回局部切片给出
`warning: ... slice escape`；`Str` 走不到该检查。

## 期望

- 编译期：对”返回局部 owner 的 `Str` 视图”给出与 `E79-6` 同级的 **warning**
  （文案含 `borrowed 'Str' view escapes`），不升级为硬错；
- 编译期：对“从临时接收者取视图并立即返回/存储”给出同类 warning；
- 设置 `/* ct: allow-escape */` 或显式 `retain`/`to_string` 的写法可豁免；
- 跨函数转手的形态仍归契约 + ASan（不承诺跨过程分析）。

## 非目标

- 不做完整借用检查器（D-014 / spec §4.68 已明确）；
- 不改变 `Str` 的 ABI、不引入 Drop；
- 不覆盖 `ref`/`out` 的跨过程逃逸。

## 验收

- 新探针覆盖“返回局部 String 视图”“临时接收者视图”两例，挂 `check-ast`；
- `p79_places` 的 `T[]` 行为不变；
- 文档（[guide-for-c-programmers](../../docs/guide-for-c-programmers.md) 的“残余风险诚实清单”）与告警文案一致。

## 关联

- [battle/ct-guide-1](../../battle/ct-guide-1/question.md) F4/F5
- [D-014](../../docs/decisions/D-014.md)（契约 + lint）
- [SH-101](sh101-p79-slice-element-borrow.md)（切片元素借用）

## 处理（REQ，2026-11-21）

- 状态：`open`（P2；2026-11-22 REV 复核后转 `verified`，见文末）
- owner：DEV
- next：补 Str 视图逃逸 lint；先加 E79-6 对应负例
- 不能关闭：当前 `ct check`/`--types` 仍静默

## 处置（DEV，2026-11-21）：**fixed**

`status` 保持 `open`（5.4：`fixed` 只写正文，由 REV 复核后改 `verified`）。两类 `Str` /
`U16Str` 视图逃逸现在都有编译期诊断，复用 E79-6 的 `Var` 借用/生命周期位，未新造平行分析。

### 实现

- **复用 E79-6 的数据结构**：`struct Var` 增加 `str_escape`（0 安全 / 1 局部 owner /
  2 临时 owner）与 `str_immortal`（局部 owning 句柄绑定 immortal 字面量），与
  `slice_escape` 同一行、同一清零路径；没有第二套借用分析。
- **视图根判定**（`Stmt.h.ct`）：`Str` / `U16Str` 表达式的静态类型先确认是 borrowed view，
  再沿接收者回溯：`String.as_str` / `get` / `s[i]` / `char_at` / `byte_slice`、
  `Str.slice` / `as_str` / `get` 以及 `str_slice` 的第一个实参；owner 分类为局部（函数出口
  失效）、临时（整条表达式末失效）、参数 / 字段 / 解引用 / 数组元素 / 全局 / static（安全）。
  `self` 接收者按调用方对象处理。
- **两个挂点**：`return` 分支（与 E79-6 同一位置）与局部声明 / 赋值（视图绑定传播；
  临时 owner 在绑定时即报）。前者覆盖直接 `return s.as_str()`，后者覆盖
  `Str v = mk().as_str();` 及 `v = mk().as_str();`，并把局部视图的逃逸类别带到 `return v`。
- **诊断**：新增 Diag kind 11（JSON `type: "str_escape"`），文案含
  `borrowed 'Str' view escapes` / `borrowed 'U16Str' view escapes`，带 `file:line:col`；
  `ct build` / `ct compile` 是 warning（不失败），`ct check` 按既有 strict 规则是 error。
  与 E79-6 完全同一口径，不升级为硬错。
- **豁免**：同一行 `/* ct: allow-escape */`（沿用 `ct: allow-cycle` 的读回源行之例）；
  immortal 字面量视图、owner 仍在作用域、参数 / 字段 / 全局 / static 借用、
  owning 局部绑定 immortal 字面量均不报。

### 红证（baseline `1ea0502a`，干净树，ct-ast v0.88.0）

```console
$ .temp/sh106/build/ct-ast check .temp/sh106/probe/ret_local.ct
exit=0
$ .temp/sh106/build/ct-ast check --types .temp/sh106/probe/ret_temp.ct
exit=0
$ .temp/sh106/build/ct-ast build .temp/sh106/probe/ret_local.ct
exit=0
诊断行数: 0
```

`1ea0502a` 是实现落地前的 HEAD，且是当前 HEAD 的祖先。把落地后的探针交给基线编译器，
负例侧 15 条全红、正例侧 13 条全绿，说明探针本身能区分两类形态：

```console
$ sh test/ast/p106_str_escape.sh <baseline 1ea0502a ct-ast>
FAIL p106/escape: ret_local            warning missing
FAIL p106/escape: ret_temp             warning missing
FAIL p106/escape: ret_local_var        warning missing
FAIL p106/escape: ret_local_get        warning missing
FAIL p106/escape: ret_view_slice       warning missing
FAIL p106/escape: bind_temp            warning missing
FAIL p106/escape: assign_temp          warning missing
FAIL p106/escape: ret_u16str           warning missing
FAIL p106/escape: ret_str_slice       warning missing
FAIL p106/escape: ret_local            ct check accepted the escape
FAIL p106/escape: ret_temp             ct check accepted the escape
FAIL p106/escape: bind_temp            ct check accepted the escape
FAIL p106/escape: ret_local            ct check --types accepted the escape
FAIL p106/escape: ret_temp             ct check --types accepted the escape
FAIL p106/escape: bind_temp            ct check --types accepted the escape
ok   ret_literal / owner_scope / ret_param / ret_field / ret_immortal_owner / allow_escape
exit=1
```

### 绿证（实现后）

```console
$ ct-ast build ret_local.ct
ret_local.ct:4:12: warning: borrowed 'Str' view escapes 'return': the local 'String' owner's lifetime ends with this frame; return an owning 'String' or a caller-owned view
exit=0
$ ct-ast check ret_local.ct
ret_local.ct:4:12: error: borrowed 'Str' view escapes 'return': ...
exit=1
$ ct-ast build ret_temp.ct
ret_temp.ct:2:22: warning: borrowed 'Str' view escapes 'return': the temporary 'String' owner's lifetime ends at the end of this expression; bind the owner to a local first
exit=0
$ ct-ast check --types ret_temp.ct
ret_temp.ct:2:22: error: borrowed 'Str' view escapes 'return': ...
exit=1
```

探针 `test/ast/p106_str_escape.sh`（已挂 `check-ast`）28/28 通过：9 个负例
（局部 owner 返回、临时接收者返回、局部视图绑定返回、`get`/`s[i]`、视图的视图、声明临时视图、
赋值临时视图、UTF-16 对、`str_slice` 转手）与 19 个正例 / `ct check` / `ct check --types` 断言（immortal 字面量、owner 在作用域、
参数借用、字段借用、全局 owner、immortal owning 局部、`ct: allow-escape`；两种 check 对负例报 error、
对安全形态保持 0）。

### 边界与误报风险（诚实清单）

- 当前 emitter 在「返回借用视图」时把局部 owning 句柄的 `release` 放在 `return` 之后
  （不可达），所以这两类形态在 v0.88.0 产物上表现为**泄漏**而不是 ASan 可见的 UAF；
  lint 按 spec §4.70 的所有权契约拦截该形态，避免释放逻辑调整后变成悬垂。报告的
  `owner's lifetime ends with this frame` 按契约措辞，不声称当前一定 free。
- 跨过程转手（`Str f() { return g(); }`、返回参数视图再转手）不报，归契约 + ASan
  （与 E79-6 的 P-4.5 同一透传边界）。
- `U16String.to_utf8()` / `U16Str.to_utf8()` 返回的 `Str` 不借用接收者（内部新分配），
  故不在白名单内、不报；这类「返回新建 buffer 的视图」仍是跨方法边界。
- 局部 owning 句柄若通过字段 / 参数间接共享（`String t = p->name.copy();`、局部副本），
  可能被保守报出；这是可接受的误报方向（宁可多报，不漏报直接形态）。
- 从数组 / 切片元素借用（`arr[i].as_str()`）按容器存储处理，不报；容器 owner 的生命周期
  仍归契约（[LANG-22](../lang/lang-22-nonimmortal-view-store-lint.md) 的存储位置告警另计）。
- 只覆盖 `Str` / `U16Str`；切片 `T[]` 行为不变（`p79_places` 全绿）。

### 文档与版本

- spec §4.70 增加「视图逃逸 lint（SH-106）」条目；`docs/guide-for-c-programmers.md`
  §3.2 / §3.4 / §7 的「当前没有 Str 逃逸 lint」改为 v0.88.2 的 warning 口径。
- 版本 v0.88.2（PKG-23 占用 v0.88.1 后顺延）；五处 `CTC_VERSION` 与 golden / ABI banner
  同提交刷新。
- 验证：`test/ast/p79_places.sh`、`p80_retain.sh`、`p80_methods.sh`、`p80_literal.sh`、
  `p80_cstr.sh`、`p106_str_escape.sh` 全绿；`selfhost/check-all.sh`（私有 `TMPDIR`）与
  `test/docs/check-docs.py` 见收口输出。

## 复核（REV，2026-11-22）：**verified**

从 `git archive c1b54d2f` 同链自举 ct-ast v0.88.2，`test/ast/p106_str_escape.sh`
28/28（9 负例 + 7 正例 + 12 条 check/`--types` 断言）；基线 `1ea0502a` 上 15 条负例
红、13 条正例绿，红证可复现。`ct build` warning（exit 0）/ `ct check` 与 `--types`
error（exit 1）与 E79-6 同口径；JSON `type:"str_escape"`；`/* ct: allow-escape */`
同行豁免、异行不豁免。

REV 新增反例：`cross_proc`（参数 relay 不误报；局部 owner 经调用转手为已声明漏报
边界）、`arr_cases`（`arr[i].as_str()` 参数/字段/数组元素不误报；局部数组元素返回
静默，与诚实清单「容器存储」一致）、`u16_paths`（`U16Str` 负例报、`to_utf8` 新分配
不报）、`owner_scope2`（owner 在作用域 0 误报）。

五处 `CTC_VERSION`=0.88.2、51 banner、p80/p81/p82 断言、g0/g8/g6（283 条）/
check-docs/warnings（502/0）/sanitizer（588）全绿；提交只含 SH-106 自己的路径，
与 PKG-23 的版本/golden 冲突已解决（v0.88.1→v0.88.2 顺延）。完整逐条输出见
[2026-11-22-pkg23-sh106-rev-verdict.md](../../docs/reviews/2026-11-22-pkg23-sh106-rev-verdict.md)
§3。

**非阻断记录**：本 issue 没有独立的 `test(...) 红` 提交（探针随 `c1b54d2f` 落地），
严格 T-7 形式不成立；红证内容已独立复现。`selfhost/check-ast.sh` 的 SH-106 钩子
当前在 `00eb6df1`，重写历史时应移入本提交（见复核 §4），重写后需按新 sha 复跑
28/28。`status` 置 `verified`。
