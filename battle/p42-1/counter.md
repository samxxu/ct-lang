# battle/p42-1 counter — 反对席（REVIEW）主张 B

| 字段 | 值 |
| --- | --- |
| 争点 | 默认私有后生成代码按名调用的元素方法如何保持可见：A 按名 / **B 协议** / C 全显式 pub |
| 主张 | **B**：只对元素生命周期协议自动公开，其余一律要求显式 `pub` |
| 基线 | HEAD `093198be`（v0.40.1）；`/tmp/p42base/ct-ast` 自报 `ct-ast v0.40.1` |
## 1 主张（规则、集合、迁移、谓词位置）
- **规则**：`visible(m, owner) = ct_method_is_pub(m) || elem_protocol(owner, m)`；`elem_protocol` 仅当 `m.name ∈ {retain, release}` 且 `elem_has_life("struct <owner>")`（模板实例传实例名如 `Box_int`；容器按 `Emitter.h.ct:1786` 直接算协议）。判定复用 `:1778` 的 `elem_has_life`（`retain` 返回自身类型 + `release` 同时存在），**不是任意同名方法**（§2.4 反例）。
- **公开的含义**：与写 `pub` 等价——进 `.h` + external + 可跨单元调用，不是只给链接。硬证据：模板实例 `Box<int>` 的消费单元没有自己的元素方法原型，只能从 `/tmp/p42b/owned/elem.h:21-22` 取；external-only 不进 `.h` 会落到 implicit declaration，故 B 必须含 `.h`。
- **集合**：52 = **44 手工 + 8 协议自动**。8 = std 6（`Vec`/`Map`/`Str` 各 retain+release）+ 其它 2（`p31_cross_unit_owned/elem.h.ct:8-14` 的 `Box<T>`）。问题稿“42+10”的 10 是按名匹配（std 8 + 其它 2）；其中 `Option::release`、`Result::release` 不满足协议（§2.5 `(void)e`），必须手工 `pub` → **44+8**。
- **`drop`/`handback` 移出保留名集合**（D42-8）：trait impl 恒 `static`（`Emitter.h.ct:2517-2519/:2521/:2816` 一带），消费单元自带 static 副本（§2.3 `nm` 为 `t`）；它们无需 pub，且 A 对 handback 的“按名公开”在 `:2521` 硬编码 `static` 前无法实现。
- **谓词位置**：一处。把 `elem_has_life`（`:1778`）+ `elem_ret_ctype`（`:1740`）抽成 `(arena, sym, type)` 形态，折进 D42-3 的 `ct_method_is_pub(m, owner)`；4 个判定点（`:1687/:1729`、`:2020`、`:2910`、`:3448`）与解析期 L42-4 都只调它，不写 parser/emitter 两套。
## 2 E1 复现命令 + 原始输出
### 2.1 生成代码只按名调用 `retain`/`release`（仓库内夹具）
```console
$ cd /Users/samxx/dsh-ws/ct-lang && /tmp/p42base/ct-ast test/ast/227_vec_element_release/prog.ct -o /tmp/p42b/e1/a.c && grep -n -E "(Probe|Str)_(retain|release)\(e\)" /tmp/p42b/e1/a.c
364:    *e = Probe_retain(e);
369:    (void)Probe_release(e);
374:    *e = Str_retain(e);
379:    (void)Str_release(e);
```
### 2.2 跨单元：消费者按名调用，定义在元素单元
```console
$ mkdir -p /tmp/p42b/xu && cd /tmp/p42b/xu && printf 'pub struct Probe { int id; }\nimpl Probe {\n    Probe retain() { return *self; }\n    void release() { }\n}\n' > elem.h.ct && printf 'import elem;\nint main(void) {\n    struct Probe p; Vec<Probe> v;\n    p.id = 1; v.h = 0; v.push(p); v.release();\n    return 0;\n}\n' > main.ct
$ cd /Users/samxx/dsh-ws/ct-lang && rm -rf /tmp/p42b/xu/out && mkdir /tmp/p42b/xu/out && /tmp/p42base/ct-ast build --emit-c /tmp/p42b/xu/main.ct -o /tmp/p42b/xu/out && grep -n -E "Probe_(retain|release)" /tmp/p42b/xu/out/main.c /tmp/p42b/xu/out/elem.c
/tmp/p42b/xu/out/main.c:20:struct Probe Probe_retain(struct Probe *);
/tmp/p42b/xu/out/main.c:21:void Probe_release(struct Probe *);
/tmp/p42b/xu/out/main.c:183:    *e = Probe_retain(e);
/tmp/p42b/xu/out/main.c:188:    (void)Probe_release(e);
/tmp/p42b/xu/out/elem.c:16:struct Probe Probe_retain(struct Probe *self) {
/tmp/p42b/xu/out/elem.c:21:void Probe_release(struct Probe *self) {
$ cd /tmp/p42b/xu/out && cc -std=c99 -c main.c -o main.o && cc -std=c99 -c elem.c -o elem.o && nm -u main.o | grep -E "Probe_(retain|release)" && nm -g elem.o | grep -E "Probe_(retain|release)" && cc main.o elem.o -o prog.bin && ./prog.bin; echo rc=$?
_Probe_release
_Probe_retain
0000000000000028 T _Probe_release
0000000000000000 T _Probe_retain
rc=0
```
**模拟 PH-42 翻默认**（只改生成物：删 `elem.h` 两条原型，`elem.c` 定义改 `static`）：
```console
$ ... && cc main.o elem.o -o priv.bin 2>&1; echo "link rc=$?"
Undefined symbols for architecture arm64:
  "_Probe_release", referenced from: _Vec_Probe__elem_release in main.o
  "_Probe_retain", referenced from: _Vec_Probe__elem_retain in main.o
clang: error: linker command failed with exit code 1 (use -v to see invocation)
link rc=1
```
### 2.3 `drop`/`handback` 是 static / trait impl（移出保留名的依据）
```console
$ grep -n -E "impl Drop for Str|void drop\(\)" lib/std/Str.h.ct
23:impl Drop for Str {
24:    void drop() {
$ grep -n "R_Drop_drop" /tmp/p42b/drop/out/main.c; nm /tmp/p42b/drop/out/main.o | grep -i drop
15:static void __attribute__((unused)) R_Drop_drop(void *self);
23:static void __attribute__((unused)) R_Drop_drop(void *self) {
31:    if (p) { R_Drop_drop(p); free(p); p = 0; }
000000000000005c t _R_Drop_drop
$ grep -n "Conn_Handback_handback" /tmp/p42b/hb/out/main.c /tmp/p42b/hb/out/elem.c
main.c:14:static void __attribute__((unused)) Conn_Handback_handback(void *self);
elem.c:14:static void __attribute__((unused)) Conn_Handback_handback(void *self);
elem.c:16:static void __attribute__((unused)) Conn_Handback_handback(void *self) {
```
### 2.4 不利于 B 的证据：谓词按类型结构，不含“是否被当元素用”
```console
$ grep -n -A2 -E "__elem_retain\(struct (Probe|WrongRet|OnlyRel) \*e\)$" /tmp/p42b/e1/probe.c
531: Vec_Probe__elem_retain(struct Probe *e)      # retain 返回自身类型 + release
533:    *e = Probe_retain(e);
541: Vec_WrongRet__elem_retain(struct WrongRet *e) # retain 返回 int
543:    (void)e;
551: Vec_OnlyRel__elem_retain(struct OnlyRel *e)    # 只有 release
553:    (void)e;
$ grep -n -E "Probe_(retain|release)" /tmp/p42b/xu/t3.c   # struct Probe 无 pub
34:static struct Probe Probe_retain(struct Probe *);
35:static void Probe_release(struct Probe *);
234:static __attribute__((unused)) struct Probe Probe_retain(struct Probe *self) {
```
`Probe` 与容器毫无“声明意图”，仅因方法形状命中就被生成代码调用（也就会被 B 自动公开）——谓词不能分辨意图。且 life 单独用会误伤私有 struct（`t3.c` 全 `static`），故 B 的条件必须是 `elem_has_life && decl_is_pub(N_STRUCT, owner)`；这是“谓词要加护栏”的代价，也是与 A 的分界（A 只看名字）。
### 2.5 B 的精确性（对照 A）：同名但非协议的方法不被公开
```console
$ /tmp/p42base/ct-ast /tmp/p42b/e1/stdprobe.ct -o /tmp/p42b/e1/stdprobe.c && grep -n -A2 -E "__elem_(retain|release)\((struct )?(Vec_int|Map_char_p_int|Str|Option_int|Result_int_int) \*e\)$" /tmp/p42b/e1/stdprobe.c
Vec_Vec__int__elem_retain → *e = Vec_int_retain(e);    Vec_Str__elem_retain → *e = Str_retain(e);
Vec_Map__char__p__int__elem_retain → *e = Map_char_p_int_retain(e);
Vec_Option__int__elem_retain → (void)e;                Vec_Result__int__int__elem_retain → (void)e;
```
即 `Option::release` / `Result::release` 同名但**不**被生成代码调用，B 不自动公开（须手工 `pub`）；A 会一并按名公开。这是 42+10 → **44+8** 的直接依据。
## 3 E2 `file:line` 锚点（HEAD，至少一利一弊）
| 方向 | 锚点 | 内容 |
| --- | --- | --- |
| 利 B | `Emitter.h.ct:2017/:2023/:2026` | 生成代码硬写 `<elem>_retain`/`<elem>_release`，名字由编译器拼 |
| 利 B | `Emitter.h.ct:1778`（`:1800-1806`、`:1822-1832`） | 协议判定已存在且校验 `retain` 返回自身类型，非按名 |
| 利 B | `Emitter.h.ct:2517-2519/:2521/:2816` | Drop/Handback 前向声明与 trait impl 定义恒 `static`，无跨单元链接需求 |
| 利 B | `Vec.h.ct:176/:187`、`:509/:517`；`Str.h.ct:132/:138`；`p31_cross_unit_owned/elem.h.ct:8-14` | 8 条协议方法可枚举 |
| 不利 B | `Emitter.h.ct:1778` 签名 `(struct Emitter *self, …)`；`:1740` 同 | 谓词绑 Emitter（`self->arena`/`self->sym`、`ct_impls`、`ct_inst`），parser 不能直接用；抽取约 130 行 |
| 不利 B | `docs/language-spec.md:642-644`、`:2248` | 现状所有方法对外；impl 可晚于首次使用生效 → 解析期谓词可能判 false |
| 不利 B | `Emitter.h.ct:3448`、`:2910`、`:1687/:1729` | 可见性判定散在 4 处，B 必须全折进同一谓词，否则头/符号/诊断不一致 |
## 4 E3 可证伪预测
| # | 若 B 成立，运行 X 应得 Y | 反证 |
| --- | --- | --- |
| P1 | §2.2 夹具翻默认后、`Probe.retain/release` 未写 `pub`：`nm -u main.o` 有 `_Probe_retain/_Probe_release`，`nm -g elem.o` 为 `T`，链接 rc=0，`elem.h` 含两条原型 | 变 `t`/缺原型/链接失败 → B 失败 |
| P2 | `WrongRet.retain`、`OnlyRel.release`、`Option::release`、`Result::release` 翻默认后仍 `t`、不进 `.h`、跨单元调用 L42-4 硬错；helper 仍 `(void)e` | 出现 `T`/进 `.h` → B 退化成 A |
| P3 | `Str::drop`、`Conn::Handback_handback` 任何单元 `nm` 只出现 `t`，永无 `T`，无人需写 `pub` | 出现 `T` → 移出保留名集合错误 |
## 5 E4 代价
- **改动点**：`Emitter.h.ct` 4 个判定点（`:1687/:1729`、`:2020`、`:2910`、`:3448`）+ `ct_method_is_pub` 加 `owner` 形参；`elem_has_life`（`:1778-1835`）+ `elem_ret_ctype`（`:1740-1767`）移到共用层（约 130 行移动）；共用层 +100~130；解析期 L42-4 另需 `Parser.h.ct`/`Expr.h.ct` 各 1 个调用点。总 **3 文件，净增约 20–40 行**。
- **谓词复制风险（真实）**：`elem_has_life` 依赖 Emitter 的 arena/sym/impl 表/实例表；`N_IMPL`/`N_METHOD` 常量在 `Parser.h.ct:58/:60` 与 `Emitter.h.ct:63/:74` 各一份，抽到共用层要收拢；且 impl 晚于使用仍生效（`language-spec.md:2248`），解析期可能判 false。缓解：**发射期权威**，解析期只做保守拒绝（用户可补 `pub`），绝不写第二套。
- **迁移**：44 手工（std 37 = 43 − 6；其它 7 = 9 − 2）+ 8 自动；脚本核对 44/8/52 与 8 条清单。门禁：E42-5 由 42/10 改 **44/8**；E42-6 不变（B 含 `.h`，52 条原型集不变）；E42-8 不变（`ABI_HASH` 只 hash `pub` 自由函数，`Emitter.h.ct:5250-5265`）；E42-7 不变（foreign-element 副本仍 `static`，`:1692`）。
- **回退**：谓词是一个 `||` 分支，删掉即回 C；44 条 `pub` 在 B 下仍合法，无需回退；R5a→R5b 顺序不变。
## 6 E5 对 C 的最强 steelman 与逐条反驳
**C 最强论**（引原文）：问题稿“C 取消豁免，全部由作者写 `pub`（迁移 52 条手工）”、D42-1“默认私有，`pub` opt-in”——可见性只由源码语法决定，J-1 可逐字机械测试（未写 pub 不进 `.h`、不 external），无隐藏 ABI 规则；J-3 的 52 条一次脚本核对；J-4 零谓词（D42-3 只读 `N_METHOD.d` 一位）。B 只是把 A 的“按名”换成“按结构”，仍是自动公开，还把 Emitter 私有 life 谓词塞进可见性判定，用户看不出某方法为何被导出，并引入解析期/发射期两时点。
**反驳**：
1. **B 不是按名**：A 才按名（10 条）。§2.4/2.5 证明同名 `WrongRet.retain`、`OnlyRel.release`、`Option::release` 在 B 下保持 private；A 会把它们全公开。B = 生成代码真会调用的两个名字 × 结构谓词，一个谓词可穷举。
2. **“源码可判断”同样要求 C 把编译器 ABI 写进源码**：C 要作者在 44 处写 `pub` 满足 `__elem_retain` 的调用；B 让生成器为自己的调用负责，作者只写语义。B 的谓词不是新魔法：`elem_has_life` 已在 HEAD、已由 p31/227 覆盖；A 的 10 条按名清单反而无结构依据。
3. **J-4 一处判定成立**：协议折进 `ct_method_is_pub(m, owner)` 后 4 个调用点无需各写例外；C 的“零谓词”代价是 52 处语法标记。谓词抽取是一次性移动（§5），不是长期复制。
4. **J-1 第一句是 C 的立场，不是中立判据**：B 承认 8 条具名例外（可枚举、可测），A 的 10 条按名例外不可测。若裁判坚持 J-1 字面冻结（未写 pub 一律不进 `.h`/不 external），C 是唯一合规解，B 主动撤回——这是判据选择，不是 B 的技术缺陷。
5. **J-5/ABI 不是 C 的独占优势**：B 的“公开”含 `.h`，52 条原型集与今天逐字相同；`ABI_HASH` 只 hash `pub` 自由函数（`:5250-5265`），B/C 的 `.abi.h` 等价。
6. **C 的真实优势是规则统一**，代价是 44 条永久注解 + “新增容器/std 方法漏标 → 自举链链接失败”（R42-1/R42-3）的长期失败模式；B 把失败模式从“作者记忆”移到“一个可测谓词”，这是核心收益。
## 7 结论
- **B 胜出条件**：J-1 允许按元素协议划定的具名例外（8 条）；`elem_has_life` 抽成一处且发射期权威（解析期保守即可）；接受 44 条手工迁移；`drop/handback` 出集合（§2.3）；E42-5 计数改 44/8。
- **B 不成立条件**：J-1 按字面冻结（则 C 唯一合规）；或谓词无法共享、parser/emitter 必须两套（J-4 失守）；或“自动公开 8 条进 `.h`”不被接受（则应选 C，external-only 变体对模板实例不可行，§1 已证）。
- 条件内：**B 优于 C**——C 的 44 条注解不能消除编译器对这两个名字的依赖，只是把内部 ABI 知识转嫁给作者；B 把豁免从 10 条按名收到 8 条按协议，且保留 header/ABI 不变式。
