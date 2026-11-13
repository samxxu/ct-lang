# battle/p42-1 主张席：C — 取消保留名豁免，52 条全部显式 `pub`

> REQ（主张 C）；基线 HEAD `1b14b63a`（v0.40.1）。本地工作树在并行 PH-41 会话中已前进（复核时 HEAD `989132b7`）且
> `Emitter.h.ct` 有未提交改动，故 `file:line` 一律用 `git show 1b14b63a:<path>` 复核（与草案 §2.3 一致）。
> 实验在 `/tmp/p42c`，仓库内只新增本文件。环境：macOS arm64 / Apple clang，基线 `/tmp/p42base/ct-ast`。

## 0 主张（C）

1. 删掉 D42-6 / L42-6 的「保留名无条件公开」；`pub` 是唯一开关：未写 `pub` 的方法不进 `.h`、定义 `static`、跨单元调用硬错（D42-2 三段式照旧）。
2. 迁移 **52 条 = std 43 + 其它 9** 全部显式加 `pub`（含 `retain`/`release`），清单由脚本列出，不依赖名字特判；`drop`/`handback` 不入规则：`delete`→`<S>_Drop_drop`（static），`borrow`→`<S>_Handback_handback`（static/vtable），都是 trait impl（D42-8）。
3. 生成代码按名调用元素方法时要求已 `pub`；`__elem_retain` 里的 `<Elem>_retain`/`<Elem>_release` 是唯一此类调用（`Emitter.h.ct:2017/2023/2026`）。未 `pub` 在解析/发射期报 **L42-7**：`element protocol method '<m>' must be pub`，不自动公开、不留给 `cc`（E1-d-3 是那种坏输出）。
4. 判定收敛到 `ct_method_is_pub(node)`（读 `N_METHOD.d`，今天无人写）；4 个调用点 `Emitter.h.ct:1957/2847/3385/2054` 全部改读它。

## 1 E1 — 可复制命令 + 原始输出
### E1-a 10 条保留名都是 source 方法（`drop`/`handback` 不在其中）
```console
$ git -C /Users/samxx/dsh-ws/ct-lang grep -hE '^    [A-Za-z_<>, *]+ (retain|release|drop|handback)\(\)' 1b14b63a -- '*.h.ct' | grep -oE '(retain|release|drop|handback)\(\)' | sort | uniq -c
      1 drop()
      6 release()
      4 retain()
```

10 条 = 4 `retain` + 6 `release`（8 std + 2 p31 `Box<T>`）；唯一 `drop()` 属 `impl Drop for Str`（trait impl，`Str.h.ct:23`）；`handback` 在 `.h.ct` 里 0 处（上表无该行）——D42-6 名单里的 `drop`/`handback` 无证据。

### E1-b 生成代码跨单元按名调 `Str_retain`/`Str_release`（L42-7 的触发点）
夹具 `/tmp/p42c/x/main.ct`：`Str s = str_from("hi"); Vec<Str> vs = {s}; printf("%d %d\n", vs.len(), vs.get(0).len); vs.release();`

```console
$ mkdir -p /tmp/p42c/x/out && printf '#include <stdio.h>\nint main(void)\n{\n    Str s = str_from("hi");\n    Vec<Str> vs = {s};\n    printf("%%d %%d\\n", vs.len(), vs.get(0).len);\n    vs.release();\n    return 0;\n}\n' > /tmp/p42c/x/main.ct && CT_STD_DIR=$PWD/lib/std /tmp/p42base/ct-ast build --emit-c /tmp/p42c/x/main.ct -o /tmp/p42c/x/out
$ grep -nHE 'Str_retain' /tmp/p42c/x/out/main.c /tmp/p42c/x/out/Str.h; grep -nE 'Str_release\(e\)' /tmp/p42c/x/out/main.c
/tmp/p42c/x/out/main.c:19:struct Str Str_retain(struct Str *);
/tmp/p42c/x/out/main.c:182:    *e = Str_retain(e);
/tmp/p42c/x/out/Str.h:28:struct Str Str_retain(struct Str *);
/tmp/p42c/x/out/main.c:187:    (void)Str_release(e);
```

### E1-c 同名方法今天完全由 struct 的 `pub` 决定，与名字无关（C 的机制 / B 的泄漏面）
```console
$ CT_STD_DIR=$PWD/lib/std /tmp/p42base/ct-ast test/ast/227_vec_element_release/prog.ct -o /tmp/p42c/227b.c
$ grep -nE '^static .*Probe_retain' /tmp/p42c/227b.c
40:static struct Probe Probe_retain(struct Probe *);
411:static __attribute__((unused)) struct Probe Probe_retain(struct Probe *self) {
$ mkdir -p /tmp/p42c/y/out && printf 'pub struct Q {\n    int n;\n}\nimpl Q {\n    int get() { return self->n; }\n    Q retain() { return *self; }\n    void release() {}\n}\n' > /tmp/p42c/y/q.h.ct && printf '#include <stdio.h>\nimport q;\nint main(void) { struct Q q; q.n = 5; printf("%%d\\n", q.get()); return 0; }\n' > /tmp/p42c/y/main.ct && CT_STD_DIR=$PWD/lib/std /tmp/p42base/ct-ast build --emit-c /tmp/p42c/y/main.ct -o /tmp/p42c/y/out >/dev/null && grep -nHE 'Q_retain' /tmp/p42c/y/out/Q.h
20:struct Q Q_retain(struct Q *);
```

私有 struct 的元素方法已 `static`；`pub struct Q` 的同名方法（`main` 只调 `get()`）仍导出（夹具：`q.h.ct` = `pub struct Q{int n;}` + `impl Q{int get(){return self->n;} Q retain(){return *self;} void release(){}}`，`main.ct` = `import q;` 只调 `q.get()`）。C 只把这个开关从 struct 移到方法；B 会让第二段继续导出且无法关闭——L42-6 自认「`priv retain` 一类不存在」。

### E1-d C 的不利证据（3 条，主动列出）
1. **迁移 52 条 vs B 宣称的 42 条**（按 B 自己的谓词实算只有 8 条能自动公开，见 E5-3）：C 把 10 条保留名也变成手写（42→52）。
2. **今天 `pub` 写在 impl 里不可用**（C 的 52 条注解必须先有 R1；夹具：`struct C{int n;}` + `impl C{pub int get(){return self->n;}}`）：
```console
$ mkdir -p /tmp/p42c/fx3 && printf '#include <stdio.h>\nstruct C { int n; };\nimpl C {\n    pub int get() { return self->n; }\n}\nint main(void) { struct C c; c.n = 3; printf("%%d\\n", c.get()); return 0; }\n' > /tmp/p42c/fx3/prog.ct && CT_STD_DIR=$PWD/lib/std /tmp/p42base/ct-ast /tmp/p42c/fx3/prog.ct -o /tmp/p42c/fx3/prog.c; echo ct_rc=$?; grep -n 'pub int C_get' /tmp/p42c/fx3/prog.c
ct_rc=0
59:static __attribute__((unused)) pub int C_get(struct C *self) {
$ cc -std=c99 /tmp/p42c/fx3/prog.c -o /tmp/p42c/fx3/prog; echo cc_rc=$?
cc_rc=1
/tmp/p42c/fx3/prog.c:59:32: error: unknown type name 'pub'
```
3. **漏写 pub 的元素方法会掉到 cc/ld**（所以 L42-7 是必备件）——把 E1-b 生成物里的两个方法改成 private：
```console
$ cd /tmp/p42c && rm -rf neg2 && cp -r x/out neg2 && cd neg2 && perl -pi -e 's/^struct Str Str_retain/static struct Str Str_retain/; s/^void Str_release/static void Str_release/' Str.c Str.h
$ cc -std=c99 -I . *.c -o a.out 2>&1 | grep -E 'undefined-internal|ld: symbol'
./Str.h:28:19: warning: function 'Str_retain' has internal linkage but is not defined [-Wundefined-internal]
./Str.h:29:13: warning: function 'Str_release' has internal linkage but is not defined [-Wundefined-internal]
ld: symbol(s) not found for architecture arm64
```

### E1-e 52 = 43 + 9 的机械清单
```console
$ cd /Users/samxx/dsh-ws/ct-lang && for f in lib/std/*.h.ct examples/38_ecosystem_reuse/src/eco.h.ct test/modules/p29_generic_struct/shapes.h.ct test/modules/p31_cross_unit_owned/elem.h.ct test/modules/p34_inherent/lib.h.ct; do perl -0777 -pe 's{/\*.*?\*/}{}gs' "$f" | awk -v F="$f" '/^impl .* for /{tr=1;next} /^}/{tr=0} !tr && !/^    (if|while|for|switch|return|else)[ (]/ && /^    (static )?[A-Za-z_*].*\([^;]*\)[[:space:]]*\{?[[:space:]]*$/ {n++} END{print F, n+0}'; done | awk '{if ($1 ~ /^lib\/std/) s+=$2; else o+=$2} END{print "std",s,"other",o,"all",s+o}'
std 43 other 9 all 52
```

脚本剥注释、跳过 `impl … for`、只数固有 impl 的方法行。**草案 §6.1 脚本逐字实跑得 `Option 8 / Result 11 / Str 3 / Vec 24`（46，不是 43）**——它把 Vec 注释行与 `impl Drop for Str` 的 `drop` 也算进去；E42-5 的「43」须换成上面的口径。

## 2 E2 — HEAD `1b14b63a` 锚点（利 / 不利都列）

| 判定 | 锚点 | 内容 |
| --- | --- | --- |
| 利 | `Emitter.h.ct:2847` | `if (!decl_is_pub(N_STRUCT, …)) fputs("static …")`：可见性今天就是一个布尔开关，C 改成按方法读，不加名字判定 |
| 利 | `Emitter.h.ct:2017/2023/2026` | 生成代码按名调用只有 `%s_retain(e)`/`%s_release(e)`；`:2454/2944/3593` 的 `Drop_drop`、`:2459/3578` 的 `Handback_handback` 都是 static/vtable，不属此类 |
| 利 | `Emitter.h.ct:1778`、`:1801-1805` | `elem_has_life` 是 emitter-static、按**实例**求值、还要 `elem_ret_ctype`（`:1740`）做类型代入；解析器/`Expr` 无法复用 |
| 利 | `Expr.h.ct:2244-2246` | 已有**第二个**协议谓词（只看名字、不看返回类型）。B 的「复用 `elem_has_life`」实际要合并两套谓词，J-4 更差 |
| 利 | `Emitter.h.ct:1981-1983`、`:1938` | 元素方法原型只对 plain struct 发射；容器实例的 retain/release 是消费方同单元 static 副本，L42-7 只需覆盖 plain-struct 元素 |
| 不利 | `Emitter.h.ct:1957/2847/3385/2054`；`lib/std/Vec.h.ct:176`、`lib/std/Str.h.ct:132`；`Parser.h.ct:3116`、`:3151` | C 要改全部 4 处判定点（R2；`1957` 是漏写 pub 会静默掉到 cc 的点）；`pub` 解析要覆盖模板与固有两条路径，后者今天在 `static` 后直接 `parse_type`，`pub` 被当返回类型名（E1-d-2），`N_METHOD.d` 从未被写 |

## 3 E3 — 可证伪预测

| # | 若 C 成立，运行 X 应得 Y |
| --- | --- |
| P1 | R5a+R5b 后 E1-b 消费者仍链接运行：`nm` 仍 `T _Str_retain`/`U _Str_retain`，stdout 仍 `1 2`；`Map<char*,int>` 消费者 stdout 仍 `2 2` |
| P2 | 只从 `Str::retain` 去掉 `pub`：rc=1、恰一条 `error: element protocol method 'retain' must be pub`（L42-7），stderr 无 `cc` 行——与 E1-d-3 的 ld 输出对照；只从 `Vec::len` 去掉 `pub` 则报 L42-4「private … add 'pub'」，不是 L42-7 |
| P3 | 用户 `impl Q { Q retain(); void release(); }` 不写 `pub`：`Q.h` 无原型、`nm -g` 无 `Q_retain`、兄弟单元调用报 L42-4；同形方法不再被自动公开 |
| P4 | E42-6：迁移前后 `Str.h` 原型集合 sha256 相同（两条仍在）；`Vec.h`/`Option.h`/`Result.h` 本来就没有方法原型；不同即 C 的链接性改错。另：`grep -rn 'is_reserved_name\|"retain"' selfhost/ct-ast` 只在元素 helper 发射处命中 |

## 4 E4 — 代价

- **改动面**：`Symbols.h.ct` `ct_method_is_pub`（+8）；`Parser.h.ct` 3 条 impl 路径消费 `pub` + L42-2（+30–45）；`Emitter.h.ct` 4 个判定点 + `1957` 改按方法 + L42-7（+50–70）；`Expr.h.ct` L42-4/5 已有 R4，L42-7 若前移到 `inst_make` 再 +15–20。**合计约 330–460 行**，在卡面「编译器 320–560」内。
- **迁移**：8 个文件 52 行注解（`lib/std` 4 + `examples/38` 1 + `test/modules` 3）；R5a 行为不变。
- **门禁**：`check-ast`（E42-1…E42-8）、`header-diff`、`check-warnings`、`check-docs`；不新增硬门禁；E42-5 计数改用 E1-e 口径。
- **回退**：R5a 纯注解、R5b 前零行为变化，`git revert` 即回；R1/R2/R4/R7 各自可 revert。若改判 B：52 条 `pub` 原样保留，删 L42-7、在 4 个判定点加形状例外（约 40 行）即可——C 的迁移成本不浪费；B→C 则相反。

## 5 E5 — 对 B 的 steelman 与逐条反驳

**对方原文**：question.md:5「B 协议判定（`retain` 返回自身类型且 `release` 同时存在，复用 `elem_has_life`）自动公开」；草案 §3.4/D42-6「保留名豁免 10 条……无条件视为 `pub`」。**最强版 steelman（据原文重构）**：S1 元素协议是编译器契约，可见性应由契约推导，作者漏注解也破坏不了它；S2 零迁移，谓词已经写好；S3 没有「漏写 pub」这类错误，也就不需要 C 的 L42-7。

1. **谓词不是一套**：`Emitter.h.ct:1778` 检查「retain 返回自身类型」，`Expr.h.ct:2244-2246` 只检查「retain 与 release 都存在」。B 要「复用」就得先合并两者；C 对可见性不需要任何协议谓词，两个谓词原地不动（J-4）。
2. **求值时机不成立**：`elem_has_life` 按实例求值，可见性却在**声明单元**发射时确定；`lib/std` 发射时还没有消费者实例（E1-b 的 `Vec.h` 无方法原型，`Vec.c` 只有 `struct Vec_Str;` 前置声明）。B 在声明单元只能按模板形状过度近似 → 实际退回 A（按名/形状公开）。
3. **B 覆盖不了这 10 条**：`Option.h.ct:77`、`Result.h.ct:104` 只有 `release` 没有 `retain`，`elem_has_life`=0，但 `test/ast/215/216` 跨单元调用它们，必须 `pub`。B 自动公开的只有 8 条（Vec/Map/Str/Box），迁移量是 44 不是 42——「52=42+10」在 B 下本身不成立。
4. **B 制造泄漏且无退出开关**：E1-c 的 `pub struct Q` 无人使用也导出 `Q_retain`；B 让该导出无法撤销（没有 `priv` 拼写），并且对私有 struct 会去掉 `:2847` 的 `static`，给不可达类型留下全局符号，违反 J-1 的「不得 external」与 D42-2 第二段。
5. **「漏写」可用诊断消灭**：L42-7 把错误变成点名到方法、点名到修法的解析期错误，B 的「不可能漏」收益被覆盖。**10 条名单也不成立**：`drop`/`handback` 在 `.h.ct` 里 0 处固有定义（E1-a）；A 的名单与 B 的协议都建立在这个未核实前提上；C 的清单是脚本产出的 52 条，可逐条核对。

## 6 结论

**C 胜出，当且仅当**：J-1（不得按名自动公开、用户同名方法不写 `pub` 即私有）、J-3（52 条清单可机械列出）、J-4（不在 parser/emitter 复制协议谓词）被作为主判据，且 L42-7 随 PH-42 落地（C 不把错误留给 `cc`）。
**C 不成立 / 需改判的条件**（反证清单）：
1. 找到 `retain`/`release` 之外**由生成代码按用户方法名调用**的路径（`delete`/`handback`/vtable 已查，均不属此类）；若存在，C 的「全显式 pub」仍不够，需要新例外。
2. R5b 后仍能观察到「未写 `pub` 的方法 external 或进 `.h`」——J-1 直接失败；或 `elem_has_life` 被证明可在声明单元按模板求值、且与 `Expr.h.ct:2244` 的谓词合并后无回归——B 的第 2 条反驳失效。
3. 裁判把「52 条注解」的代价判高于泄漏与诊断价值（价值判断）；此时输的是成本，不是 J-1/J-3/J-4。
