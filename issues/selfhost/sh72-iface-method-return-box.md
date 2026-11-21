# SH-72 · 接口方法返回接口值在调用点报 `cannot infer the type to box`（类型其实可推）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 类型推断 / 装箱） |
| 严重度 | Medium（编译期响亮报错，无坏产物；但阻断「响应接口」这类合法消费） |
| 锚点 | `v0.44.1`（`13db6cad`，2026-11-15 复核） |
| 文件 | [TypeCheck.h.ct:331-382](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L331-L382)、[:610-612](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L610-L612) |
| 状态 | verified |
| 处置证据 | **fixed**（`5ff69ac3`，2026-11-15；回归 `test/ast/238_iface_ret_value`） |

## 现象

```c
HttpResponse res = req.send();     /* req: HttpRequest 接口值 */
```

```text
src/main.ct:41:34: error: cannot infer the type to box
```

改成丢弃返回值 `req.send();` 则编译、`cc` 与运行都是 rc=0。同族：把返回 `HttpRequest` 本身的
`header()` 结果装箱给变量同样失败（`src/main.ct:41:42: error: cannot infer the type to box`）。
自由函数工厂结果直接接方法也在同一位置失败：`main.ct:5:114: error: cannot infer the type to box`
（文档报的是 `7:114`，列号一致）。

## 最小复现

单文件 `/tmp/ctr/B/src/main.ct`（完整源码见 [SH-74](sh74-impl-iface-return-self-codegen.md#最小复现)，把
`req.send();` 换成 `HttpResponse res = req.send(); return res.status();`）：

```text
$ ct src/main.ct -o out.c ; echo $?
src/main.ct:41:34: error: cannot infer the type to box
1
```

对照组（同一份代码只改这一行）：

```text
$ ct src/main.ct -o out.c ; echo $?      # req.send();
0
$ cc -std=c99 out.c -o out && ./out ; echo $?
0
```

## 定性

规约规则是「只有**变量**或 `&变量`（以及「返回同款接口」的函数调用）能装箱；类型无法推断 → `die`」
（[language-spec.md:356](../../docs/language-spec.md#L356)）。但这里类型并非不可推断：

- `req` 的静态类型是 `HttpRequest` 接口值，`send` 的 vtable 槽是
  `struct HttpResponse_iface (*send)(void *)`（规约自己在 [§4.10.1](../../docs/language-spec.md#L649-L651)
  也承认「vtable 槽是合法的」）；
- 目标类型来自声明行（`HttpResponse res`），两侧其实是同一接口，本不需要装箱。

因此这是 `expr_type` 的实现缺口，不是语言语义的必然：`N_MCALL` 分支只处理 `aux==5`（静态 trait）、
`aux==6`（类型宿主）、`aux==9/10`（实例化固有方法），动态派发落到 `return -1`
（[TypeCheck.h.ct:331-382](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L331-L382)），
`maybe_box` 随即报「cannot infer」（[:610-612](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L610-L612)）。
报错文案也与事实不符——类型是可推的。

规约把现状登记为 0.44.1 的限制（[§4.10.1](../../docs/language-spec.md#L647-L651)），但同一段也写明
「缺的是调用点消费返回值」，即能力未落地，而非禁止。

## 影响面

- 只影响「接口方法返回接口值」的消费；丢弃返回值、返回 struct / struct 指针都不受影响。
- **合法绕法**：把 `send` 写成 `.h.ct` 里的 `pub` 自由函数，`HttpResponse res = http::send(req);`
  命中「返回同款接口的函数调用」路径。实测 `HttpRequest identity(HttpRequest r) { return r; }` 可用
  （`ct` / `cc` rc=0，运行输出 42）。代价是丢掉 `.send()` 这一跳的方法形态；在 SH-73 已要求逐跳落变量的
  前提下，额外成本很小。响应侧多实现仍可保留（接口类型不变）。
- 不破坏已有样例：修复只把原本报错的代码变绿，不改既有生成物。

## 修复代价

- 只动 `TypeCheck.h.ct` 的 `expr_type`：为动态派发的 `N_MCALL` 增加一个分支——用接收者的静态类型
  走 `iface_ref_type` 取出 trait 名，再按方法名查 trait 签名返回类型（与 `aux==5` 的查法同源）。
  约 30–60 行；不需要改发射器，不改变任何既有生成 C。
- 风险：需要正确处理「返回接口指针 / 接口数组元素」的 `addr` 语义，否则会把 `self` 取址规则搞混；
  建议与 [SH-74](sh74-impl-iface-return-self-codegen.md) 同一批次，先修 `&_self` 再放开消费，
  避免先制造一条 UAF 路径。

## 验收

- 上述最小复现改为 `HttpResponse res = req.send(); return res.status();` 后 `ct` / `cc` rc=0，
  运行输出与预期一致；
- 丢弃返回值、返回 struct、返回 struct 指针三种既有形态行为不变（现样例外加 `test/cases` 对照）；
- 新增一条正向夹具进 `check-ast.sh`，并与 SH-74 的 ASAN 夹具配套；
- `bash selfhost/check-all.sh` 十一关全绿。

## 关联

- [SH-74](sh74-impl-iface-return-self-codegen.md)：必须先修，否则本条的修复会直接暴露悬垂 `self`
- [SH-73](sh73-temp-receiver-dynamic-dispatch.md)：另一条被挡住的消费形态（临时值作接收者）
- 外部来源：`ct-http/docs/review/ct-http-0.1.0-blockers.md` §3（2026-11-15 独立复核）
