# v0-PH-88 S88c 度量与 sharp edge：发射器按 kind 切片（v0.88.0）

> **S88c 交付物**。切片：`backend/emit/Emitter.h.ct` 的五个 kind 判别函数
> （`emit_node` / `emit_expr` / `emit_type_decl` / `emit_inline` / `emit_field`）。
> 控制组 = 基线 `47a8f786`（v0.87.0）；实验组 = 基线 + S88a 切片 + S88b fixpoint 参数化。
> 探针：`p88_emit`（切片清单 + 变异自测 + 66 语料逐字节）、`p88_fixpoint`（2/3 轮）、
> `p88_metrics`（本文数字复算）。原始输出见 [test/probes/p88_evidence.txt](../../test/probes/p88_evidence.txt)。

<!-- p88-metrics: emitter_before=8876 emitter_after=11085 total_slices=76 expr_slices=34
     node_slices=26 decl_slices=6 inline_slices=8 field_slices=2
     emitted_before=48223 emitted_after=90652 io_cap=2048
     (SH-117 后复测：out/ref owning 赋值点补 release 旧值（sb_assign）并把 ref/out
      形参登记进类型表（sb_push_params），Emitter.h.ct 9814 -> 9830；P-3.5 的
      `String`/`Str` → `char *` 检查与 `ref` 显式 release 硬错在 Expr.h.ct，
      发射 C 52218 -> 52282)
     (SH-118 后复测：`chk_brace_init` 跳过 `{ 0 }` 聚合零填充与 String/Str 字段的
      字符串字面量，发射 C 52282 -> 52304)
     (v1-PH-0 S0.5 后复测：五个判别函数的 if 链改为 84 臂的穷尽 match，76 个
      `em_*` 切片各占一臂；`expr_ctype` / `maybe_box` / `chk_type` 同步改为
      NodeKind match。动作等价由 66 语料逐字节、345 诊断逐字、2 轮自举不动点复核)
     (S1a-0 C2n-3 后复测：Emitter/Init/Emit* 的持久文本改 pool 文本、生成成员
      路径/初始化项/诊断改 run-scoped builder，Emitter.h.ct 10218 行；发射 C
      66858 行（仅 .c）。切片清单仍为 76，判别式仍各读 1 次，本次不改 kind 分支)
     (S1a-0 C2o 后复测：Lexer/Parser/Symbols 的 token/导入/限定名/导出表按需；
      Emitter.h.ct 不变（10218），发射 C 67123 行（仅 .c），切片清单仍为 76)
     (S1a-0 C2p-3 后复测：类型拼写/实例名按需；Emitter.h.ct 10218 -> 10214，
      发射 C 67123 -> 67577 行（仅 .c），切片清单仍为 76)
     (S1a-0 C2p-4 后复测：持久类型行改指针行（`MethodSig.ptype` /
      `Closure.ptype`/`pname` / ADT 字段、变体与标签名 / `map binding` 两侧 /
      `Symbols.ret_type` / 类型别名展开），发射器 `map binding` 的 pair 直接读
      pool 文本；Emitter.h.ct 10214 -> 10215，发射 C 67577 -> 67620 行
      （仅 .c），切片清单仍为 76)
     (S1a-0 C2p-5 后复测：`expr_type`/`expr_ctype` 的 38 处调用改 pool 文本入口、
      `sb_expr_type`/`emit_gsub_type` 新增 pool 形式、`write_abi_header` 的 fwd
      改指针行；`Emitter.h.ct` 10215 -> 10315，发射 C 67620 -> 68188 行
      （仅 .c），切片清单仍为 76，判别式仍各读 1 次)
     (S1a-0 C2p-6 后复测：`MapBuild.parse` 的 host 拼写、`Emitter.gtarg`/`gtparam`
      与 `emit_gsub_type` 的三个 scratch 行、match 结果临时量类型、`foreach`
      item 绑定、`_Atomic`/`_Alignas` 说明符改 pool 文本；`Emitter.h.ct`
      10315 -> 10318，发射 C 68188 -> 68338 行（仅 .c），切片清单仍为 76，
      判别式仍各读 1 次)
     (S1a-0 C2p-7 后复测：`parse_postfix` 的成员名、`parse_impl` 的方法名、
      `parse_enum_def` 的成员名、label/goto 名改 pool 文本，match 绑定名改
      指针行，`rewrite_init_names` 的标识符按整段 intern；`Emitter.h.ct`
      不变（10318），发射 C 68338 -> 68353 行（仅 .c），切片清单仍为 76，
      判别式仍各读 1 次)
     (S1a-0 C2p-8 后复测：发射器的 base/lifetime/vptr 读者行、Box/ADT 生命周期
      文本、impl/inst 名字、map recipe 参数类型与后缀、Run-scoped 初始化名、
      `Result` 操作数/列、Drop 字段类型改 pool 文本或精确块；`Emitter.h.ct`
      10318 -> 10321，发射 C 68353 -> 68377 行（仅 .c），切片清单仍为 76，
      判别式仍各读 1 次)
     (S1a-0 C2p-9 后复测：`ExprBinding`/`MapBuild`/`StmtLoop`/`StmtRangeText`/
      `StmtRangeScan`/`ExprCallCheck`/`ExprTypeText` 的 recipe、类型比较键与
      诊断改 pool 文本或 `ct_scratch_fmt`，`MapBind.params` 改指针行；
      `Emitter.h.ct` 不变（10321），发射 C 68377 -> 68571 行（仅 .c），
      切片清单仍为 76，判别式仍各读 1 次)
     (S1a-0 C2p-10 后复测：`static_ctype` 家族（`static_ctype_text` /
      `ctype_expand_text` / `fnptr_ret_text` / `peel_ptr_text` / `result_*_text` /
      `inst_subst_type_text`）与 Expr 调用点、ExprOptional / ExprPure / ExprTry /
      ExprSubscript 改 pool 文本；`Emitter.h.ct` 不变（10321），发射 C
      68571 -> 68633 行（仅 .c），切片清单仍为 76，判别式仍各读 1 次)
     (S1a-0 C2p-10 第二批复测：`chk_type_text` 家族（`chk_type` /
      `chk_assignable` / `chk_brace_init` / `chk_callptr_args` / `chk_mcall_args` /
      `closure_match` / `lit_coerce`）与 ExprClosure / ExprAdtCtor /
      ExprInstantiate / ExprTraitInst / ExprSubscript 改 pool 文本；
      `Emitter.h.ct` 不变（10321），发射 C 68633 -> 68726 行（仅 .c），
      切片清单仍为 76，判别式仍各读 1 次)
     (S1a-0 C2p-10 第三批复测：Stmt 的语句层文本（切片视图的 `{ptr,len}`
      复合字面量、Map 重复键解码与诊断、`_Alignas` 捕获、限定类型前瞻、
      yield/return/赋值/初始化器的类型行）与 StmtMatch / ParseSupport /
      StmtControl 改 pool 文本或 run-scoped 块；`Emitter.h.ct` 不变（10321），
      发射 C 68726 -> 68768 行（仅 .c），切片清单仍为 76，判别式仍各读 1 次)
     (S1a-0 C2p-10 第四批复测：Expr 的表达式层文本（`$` 目标名、`_Generic`
      选择、绑定转换的返回/接收者、静态 trait/struct 调用的实例与方法名、
      原子内建的类型、C 边界 handle 诊断）改 pool 文本 / `ct_scratch_fmt`；
      `inst_method_ret_text` 落在 TypeCheck；`Emitter.h.ct` 不变（10321），
      发射 C 68768 -> 68868 行（仅 .c），切片清单仍为 76，判别式仍各读 1 次)
     (S1a-0 C2p-10 第五批复测：Parser 的解析器文本（`borrow` 的 struct 名、
      `_Alignas` 捕获、泛型边界、成员/结构体/enum/ADT/trait 的注册诊断、
      `impl` 实例与 trait 实例名、drop 字段诊断）改 pool 文本 /
      `ct_scratch_fmt` / run-scoped 块；`Emitter.h.ct` 不变（10321），
      发射 C 68868 -> 68903 行（仅 .c），切片清单仍为 76，判别式仍各读 1 次)
     (S1a-0 C2p-11 后复测：TypeCheck/Module/ModuleBoundary/Memory/Symbols/
      SymbolsTypeText/Pkg 的剩余 160 字节文本行改 pool 文本、裁剪视图或
      run-scoped 行；Emitter.h.ct 不变（10321），发射 C 68903 -> 68745 行
      （仅 .c，删除三个无调用方的 buffer 形式后净减），切片清单仍为 76，
      判别式仍各读 1 次)
     (LANG-26 后复测：`out` 写回转换与 `CT_BINDING_CONVERSION` 开关落在
      Expr.h.ct / Emitter.h.ct / Arena.h.ct；Emitter.h.ct 10343 -> 10415，
      发射 C 54413 -> 54712，切片清单不变)
     (LANG-29 S4/B5 后复测：表达式 `match` 的 statement-expression 发射与
      sb_assign 的 match 结果临时量类型回落落在 Emitter.h.ct；切片清单仍为 76，
      判别式仍各读 1 次)
     (LANG-29 S4/B4 后复测：`map binding` 的 aux 12 展开、pair 键归一与
      --emit-map 的 registry 跳过落在 Emitter.h.ct；切片清单仍为 76)
     (S1a-0 C1 后复测：map 表与 `MapBind` 参数并行表改堆块、`--emit-map` /
      `map_visible` 全表扫描改持槽位、`emit_recipe` 的 16 项暂存改按绑定分配，
      落在 Emitter.h.ct；Emitter.h.ct 10929 -> 10953，发射 C 59247 -> 59373，
      切片清单仍为 76。同批的 `MAX_PKG_DEPS` 只改 Pkg/Driver，Emitter.h.ct
      不变，发射 C 59373 -> 59667。S1a-0 C3 的 ADT 计数动态化改
      Symbols/Stmt/Parser，Emitter.h.ct 仍不变，发射 C 59667 -> 59805)
     (S1a-0 C2 后复测：raw 块收到 TEXT_LIMIT、缓存键 / 初始化文本 / pkg 锁文本
      改按需堆块，落在 Parser/Cache/Module/TypeCheck/Stmt/Pkg；Emitter.h.ct
      仍不变，发射 C 60111 -> 60462，切片清单仍为 76)
     (S1a-0 C2e 后复测：Pkg 的 17 处 MAX_PKG_CMD 命令/路径缓冲改为 owned 按需
      文本，只改 Pkg.h.ct；Emitter.h.ct 仍不变，发射 C 60462 -> 60851，切片清单
      仍为 76)
     (S1a-0 C2f/C2g 后复测：cc 命令行与 cflags/ldflags 累加器按需增长，落在
      Module/Driver/ModuleBoundary/main；Emitter.h.ct 仍不变，发射 C 60851 ->
      61005，切片清单仍为 76)
     (S1a-0 C2h 后复测：Pkg 的行读取改 `pkg_text_fgets`、index `seen` 改指针行、
      诊断消息改 `pkg_text_setf`，落在 Pkg.h.ct / main.ct；Emitter.h.ct 仍不变，
      发射 C 61005 -> 61169，切片清单仍为 76)
     (S1a-0 C2i 后复测：包目录/树扫描路径改 `pkg_pathf` 精确分配、`sha_collect` /
      `sha_sort` 改指针行、`copy_tree` / `split_spec` / `IndexRow.dir` 按需，只改
      Pkg.h.ct；Emitter.h.ct 仍不变，发射 C 61169 -> 61335，切片清单仍为 76)
     (S1a-0 C2j 后复测：manifest 的 dep 行改 `struct DepList`（每行一条精确字符串，
      递归安全），`remember_dep` 的重复行比较按 spec 全长；只改 Pkg.h.ct，
      Emitter.h.ct 仍不变，发射 C 61335 -> 61409，切片清单仍为 76)
     (S1a-0 C2l 后复测：`MAX_PATH` 退场的诊断/缓存切片。`Diag.file` 改记录
      持有的精确自有路径（`diag_reset` 释放），`Cache.paths` 的目录/键文件
      改自有块，Sh 增 `ct_text_fmt`/`ct_text_dup` 与 run-scoped scratch 池。
      Emitter.h.ct 不变（10965），发射 C 61465 -> 61718，切片清单仍为 76)
     (S1a-0 C2m 后复测：Unit.path/shim_*、Module 的 outdir/map_path/
      model_path 与导入解析、Driver 的默认输出/`-I` 根、Emitter 的
      `.c`/`.h`/header guard、ModuleBoundary 的 root/candidate 全部改
      `char *` 或 run-scoped scratch 块；Emitter.h.ct 10965 -> 10966，
      发射 C 61718 -> 61636，切片清单仍为 76)
     (S1a-0 C2k 后复测：`MAX_PKG_PATH` 退场，store / 锁行 / 索引 / 锁根路径
      改精确自有字符串，落在 Pkg.h.ct 与 Driver.h.ct；Emitter.h.ct 仍不变，
      发射 C 61409 -> 61465，切片清单仍为 76)
     (v1-PH-2 S1a-1 A3 后复测：`ExprOptional` 五个 optional 方法整段搬入
      `frontend/parse/ExprOptional.h.ct`，Emitter.h.ct 不变（10966），发射 C
      61812 -> 61989，切片清单仍为 76)
     (v1-PH-2 S1a-1 A4 后复测：`ExprTraitInst.parse_trait_inst_type` 搬入
      `frontend/parse/ExprTraitInst.h.ct`，Emitter.h.ct 不变（10966），发射 C
      61989 -> 62167，切片清单仍为 76)
     (v1-PH-2 S1a-1 前置后复测：`Symbols` 的 import 别名行由定长
      `char[24][160]` 改按需堆块（`ensure_alias_capacity`，24 倍增到
      `MAX_IMPORT_ALIASES_MAX`），只改 Symbols.h.ct；Emitter.h.ct 不变
      （10966），发射 C 62167 -> 62205，切片清单仍为 76)
     (v1-PH-2 S1a-1 A5 后复测：`ExprRecvMut.recv_mut_check` 搬入
      `frontend/parse/ExprRecvMut.h.ct`，Emitter.h.ct 不变（10966），发射 C
      62205 -> 62384，切片清单仍为 76)
     (v1-PH-2 S1a-1 A6 后复测：`ExprTry` 三个 `?` 方法搬入
      `frontend/parse/ExprTry.h.ct`，Emitter.h.ct 不变（10966），发射 C
      62384 -> 62564，切片清单仍为 76)
     (v1-PH-2 S1a-1 A1 后复测：`ExprTypes` 七个检查方法与
      `chk_type_static` / `closure_match` / `str_handle_value` 三个 helper 搬入
      `frontend/parse/ExprTypes.h.ct`，Emitter.h.ct 不变（10966），发射 C
      62564 -> 62745，切片清单仍为 76)
     (v1-PH-2 S1a-1 A7 后复测：`ExprBinding.binding_convert` 与 9 个
      `bind_conv_*` helper 闭包搬入 `frontend/parse/ExprBinding.h.ct`，
      Emitter.h.ct 不变（10966），发射 C 62745 -> 62927，切片清单仍为 76；Phase A 完成)
     (v1-PH-2 S1a-1 B1 后复测：`ExprOps` 的 6 个调用检查方法拆成
      `ExprCallCheck` trait，方法体搬入 `frontend/parse/ExprCallCheck.h.ct`，
      Emitter.h.ct 不变（10966），发射 C 62927 -> 63114，切片清单仍为 76)
     (v1-PH-2 S1a-1 B2 后复测：`ExprOps` 的 11 个闭包方法拆成
      `ExprClosure` trait，方法体与 6 个 closure helper 搬入
      `frontend/parse/ExprClosure.h.ct`，Emitter.h.ct 不变（10966），发射 C
      63114 -> 63302，切片清单仍为 76)
     (v1-PH-2 S1a-1 B3 后复测：`ExprOps` 的 10 个实例化方法拆成
      `ExprInstantiate` trait，方法体与 `expr_generic_param` 搬入
      `frontend/parse/ExprInstantiate.h.ct`，Emitter.h.ct 不变（10966），发射 C
      63302 -> 63491，切片清单仍为 76)
     (v1-PH-2 S1a-1 B4 后复测：`ExprOps` 的 4 个类型解析方法拆成
      `ExprTypeParse` trait，方法体、`type_only_qualifiers` 与
      `g_expr_inst_override` 搬入 `frontend/parse/ExprTypeParse.h.ct`，
      Emitter.h.ct 不变（10966），发射 C 63491 -> 63681，切片清单仍为 76)
     (v1-PH-2 S1a-1 B5 后复测：`ExprOps` 的 16 个静态类型方法拆成
      `ExprStaticType` trait，方法体与 14 个 ctype/token helper 搬入
      `frontend/parse/ExprStaticType.h.ct`，Emitter.h.ct 不变（10966），发射 C
      63681 -> 63872，切片清单仍为 76；Phase B 完成)
     (v1-PH-2 S1a-1 C1 后复测：`StmtOps` 的 4 个 match 方法拆成
      `StmtMatch` trait，方法体与 `match_expr_type_key` 搬入
      `frontend/parse/StmtMatch.h.ct`，Emitter.h.ct 不变（10966），发射 C
      63872 -> 64050，切片清单仍为 76)
     (v1-PH-2 S1a-1 C2 后复测：`StmtOps` 的 6 个循环方法拆成
      `StmtLoop` trait，方法体与 5 个 helper 搬入
      `frontend/parse/StmtLoop.h.ct`，Emitter.h.ct 不变（10966），发射 C
      64050 -> 64229，切片清单仍为 76)
     (v1-PH-2 S1a-1 C3 后复测：`StmtOps` 的 7 个 switch/label 方法拆成
      `StmtSwitch` trait，方法体与 3 个 helper 搬入
      `frontend/parse/StmtSwitch.h.ct`，Emitter.h.ct 不变（10966），发射 C
      64229 -> 64409，切片清单仍为 76)
     (v1-PH-2 S1a-1 C4 后复测：`StmtOps` 的 5 个控制流方法拆成
      `StmtControl` trait，方法体搬入 `frontend/parse/StmtControl.h.ct`，
      Emitter.h.ct 不变（10966），发射 C 64409 -> 64590，切片清单仍为 76)
     (v1-PH-2 S1a-1 C5 后复测：`StmtOps` 的 7 个未初始化跟踪方法拆成
      `StmtUninit` trait，方法体搬入 `frontend/parse/StmtUninit.h.ct`，
      Emitter.h.ct 不变（10966），发射 C 64590 -> 64772，切片清单仍为 76；
      Phase C 完成，StmtOps 只留 8 个文法方法)
     (v1-PH-2 S1a-1 D2 后复测：`EmitOps` 的 4 个 invariant 方法拆成
      `EmitInvariant` trait，方法体搬入 `backend/emit/EmitInvariant.h.ct`；
      Emitter.h.ct 10966 -> 10717，发射 C 64772 -> 64987，切片清单仍为 76)
     (v1-PH-2 S1a-1 D1 后复测：`EmitOps` 的 5 个 hoist 方法拆成
      `EmitHoist` trait，方法体与 2 个 helper 搬入
      `backend/emit/EmitHoist.h.ct`；Emitter.h.ct 10717 -> 10430，发射 C
      64987 -> 65203，切片清单仍为 76)
     (v1-PH-2 S1a-1 D3 后复测：`EmitOps` 的 4 个初始化器方法拆成
      `EmitInit` trait，方法体与 `sb_rewrite_init` 搬入
      `backend/emit/EmitInit.h.ct`；Emitter.h.ct 10430 -> 10153，发射 C
      65203 -> 65420，切片清单仍为 76；D1–D3 完成)
     (v1-PH-2 S1a-0 C2n-0 后复测：新增 `runtime/text/Intern.h.ct`
      （字符串驻留池，`TypeAlias.name`/`.target` 改 `const char *`），
      Emitter.h.ct 不变（10153），发射 C 65420 -> 65713（+202 新单元 +
      91 既有 .c：每文件新增一行前向声明，Symbols.c 的 8 处 ct_intern
      赋值与 13 行旧 snprintf 删除），切片清单仍为 76)
     (v1-PH-2 S1a-0 C2n-1 后复测：Symbols/Module/MapTable/Unit 的持久文本
      字段改 `const char *` + `ct_intern`/`ct_intern_join`，写点带显式 OOM
      分支；Emitter.h.ct 10153 -> 10154，发射 C 65713 -> 66061（Symbols/
      Parser/MapBuild 的写点行数与检查分支），切片清单仍为 76)
     (S1a-0 C4 后复测：`Limits.h.ct` 归并为 `CAP_LIMIT` / `TEXT_LIMIT` / `NODE_LIMIT`，
      删除 40 个 `*_MAX` 镜像宏并各留一个 `CAP_LIMIT`；`Emitter.h.ct` 10321 -> 10317，
      发射 C 68745 -> 68663 行（仅 .c；差值是每单元少掉的 `#define ..._MAX` 行），
      切片清单仍为 76，判别式仍各读 1 次)
     (S1b-S1 后复测：新增 `backend/tir/TModule` / `TBuilder` 与
      `backend/verify/Verifier` 三个单元（TIR typed shadow，只读 AST、默认
      不参与发射），Emitter.h.ct 不变，发射 C 68663 -> 73692（+5029：三个
      新单元的 .c/.h + 每个既有单元头部的三行前向声明），切片清单仍为 76)
     (S1b-S2 后复测：新增 `backend/lir/LModule` / `Lower` 两个单元与 CP2
      校验（`Emitter.h.ct` 10317 -> 10323，只增加了 metadata defer 副本的
      跳过与 node_mentions 剔除），发射 C 73692 -> 77933（+4241：两个新单元
      的 .c/.h + 每个既有单元头部的两行前向声明；LIR 默认关闭，用户语料
      生成物逐字节不变），切片清单仍为 76)
-->

## 1 切片清单

判别式 = `self->arena->nodes[n].kind`；每个切片 = 一个 kind 的完整分支体
（含其注释），被判别函数以 `nk` 传入。切片函数是**文件级 static 函数**，不是
trait 方法：trait 方法数计入 `MAX_METHODS`（64），且 `EmitOps` 已接近该上限。

| 判别函数 | 切片前函数体 | 切片后判别体 | 切片数 | 覆盖 kind |
| --- | --- | --- | --- | --- |
| `emit_expr` | 1162 行 | 41 行 | 34 | 33（`N_BIN` 两支：comma / 其余） |
| `emit_node` | 980 行 | 40 行 | 26 | 28（`N_DECL`/`N_EXPR`/`N_BIN` 参与多支） |
| `emit_type_decl` | 199 行 | 13 行 | 6 | 5（`N_ENUM` 两支：ADT / C enum） |
| `emit_inline` | 154 行 | 15 行 | 8 | 8（`N_DECL || N_FIELD` 一支） |
| `emit_field` | 46 行 | 9 行 | 2 | 2 |
| **合计** | **2541 行** | **118 行** | **76** | — |

- **SH-120（v1-PH-1 S0）后的 live 校准**：`Emitter.h.ct` 10415 → 10446 行（+31：
  `String.h` 头名映射、八槽注释与实例胶水前的 retain/release 前置声明），发射 C
  54712 → 54792（+80：内建层拆分后的四个字符串单元、单元归属与前置声明）。上面 PH-88
  的历史数字保持不变；本文件头部的 `emitter_after` / `emitted_after` 是 p88_metrics 的
  live pin，随每次 emitter 变更同步。
- **v1-PH-2 S8（IR-2）后的 live 校准**：`Emitter.h.ct` 11065 → 11088 行（+23：
  `ct_emit_bind_plan` 取代裸 `builtin_live` 指针，内建头文件改由
  `LModulePlan` 提供），新增 `backend/tir/TGraph.h.ct` 一个单元（语义判活与实例
  环检测），发射 C 87910 → 88858（+948：TGraph 单元 + 发射器计划绑定）。
  默认 `ct build` 由 LIR 打印函数体；用户语料/自举发射 C 与 AST 路径逐字节相同。
  切片清单仍为 76。
- **v1-PH-2 S9（全局默认 strict）后的 live 校准**：`Emitter.h.ct` 11088 → 11085
  行（-3：四条系统 include 收进 `Emitter.shim.h`，`.h.ct` 只写自己的 shim），
  发射 C 88858 → 88919（+61：每个单元一条 shim include 取代原来的 3–5 条系统
  include，`ct build` 把 shim 复制进产物目录）。
  `p88_metrics` 的 baseline 树按它自己的年代用显式 allow 发射。
- **v1-PH-2 S8b（源码狗粮化）后的 live 校准**：每个片按实际发射 C 行数推进头部的
  `emitted_after` live pin；PH-88 的历史数字不动。
  - D1 `runtime/arena` 方法化：`Arena.c` 的两个池增长 helper 进 `ArenaOps`，发射 C
    88919 → 88923（+4：两条方法签名/调用形状）。
  - D1 `tool/` 方法化：`Diag` 的告警表增长器与 `Pkg` 的 17 个文本/池 helper 进
    `DiagStore` / `PkgOps`，发射 C 88923 → 88977（+54：方法签名、调用形状与
    `PkgOps` vtable 增长）；`Pkg` 仅余 3 个变参 builder 自由函数（真 trait 方法
    不能变参）。
  - D1 `frontend/sym` 方法化：`symbols_grow` 进 `SymbolOps`，发射 C
    88977 → 88979（+2：一条方法签名/调用形状）。
  - D2 `tool/sh` 容器化：run-scoped path pool 的 `char **` + count + capacity
    三件套改一个 `Vec<char *>`，发射 C 88979 → 89453（+474：内建 `Vec` 实例
    `Vec.c` 进入产物；编译器自身第一次使用容器）。
  - D5 `runtime/text` 错误路径：Intern 的插入/增长入口改 `Result`（`grow()?`
    传播、`errdefer` 释放半成品块），公共 `ct_intern*` 保持 NULL 契约；发射 C
    89453 → 90663（+1210：内建 `Result` 实例 `Result.c` 进入产物，Intern 内部
    错误路径改 Result）。
  - D2 `tool/pkg` 容器化：`Pkg.owned` 的 `char **` + count + capacity 三件套
    改 `Vec<char *>`，发射 C 90663 → 90652（-11：注册表增长代码收进容器）。
- **v1-PH-2 S7-c（REQ-MEM-2 写入摘要）后的 live 校准**：`Emitter.h.ct` 仍为
  11065 行；新增 `frontend/parse/Mem2Writes.h.ct` 一个单元，发射 C 87080 → 87839
  （+759：定义出口的直接写扫描、一层组合与调用点判定）。发射器与切片清单不变。
- **v1-PH-2 S6（泛型 ADT）后的 live 校准**：`Emitter.h.ct` 10944 → 11065 行
  （+109：ADT 模板行不发射、实例布局走同一个 `emit_adt_layout_body`、实例按需
  预发射与 `adt_row_for_emit` 的模板→实例映射），发射 C 86371 → 86930
  （+552：模板/实例注册、嵌套实例解析与泛型 impl 的 `self` 类型；`--ir=on`
  与 AST 路径逐字节相同）。切片清单仍为 76；实例表随 `CAP_LIMIT` 增长。
- **v1-PH-2 S6b（按 unit 遮蔽内置 Option/Result）后的 live 校准**：发射 C
  86930 → 87080（+150：模板行按 unit 解析、`StructInst`/`StructImpl` 的
  `tmpl_row` 身份、阴影实例的 `ct_adt_*` 编码与 `?` 的内置判定，以及不遮蔽
  模板的 build-wide 兼容回退；`Emitter.h.ct` 行数不变，切片清单仍为 76）。
- **v1-PH-2 S5（ADT 模式 B：or / 守卫）后的 live 校准**：`Emitter.h.ct`
  10525 → 10944 行（+419：or-pattern 的 DNF 条件组、按组选绑定访问器、
  守卫 arm 的 flag 形状与 `emit_match_arm_ext`），发射 C 85158 → 86371
  （+1213：模式解析的 DNF/守卫、TIR `guard` 行与 LIR 回退检查；or/守卫的
  LIR 打印按 per-function fallback 回到 AST body seam，产物逐字节相同）。
  切片清单仍为 76；`io_names` 由 1024 提到 2048（S5 新增约 28 个 callee）。
- **v1-PH-2 S4（ADT 模式 A）后的 live 校准**：`Emitter.h.ct` 10467 → 10525 行
  （+58：arm 条件串与绑定访问路径的发射、非 ADT 主语的 `__ct_matchN` 声明、
  `emit_arm_conds` helper），发射 C 84025 → 85158（+1133：模式条件/路径的
  解析、检查与 AST/TIR/LIR 三处透传代码）。切片清单仍为 76，判别式仍各读 1 次；
  旧语料生成 C 与基线逐字节相同。
- **v1-PH-2 S3（D-029 函子签名糖）后的 live 校准**：`Emitter.h.ct` 10467 → 10467 行
  （发射器未改；糖在类型解析/声明检查与 LIR 打印层，见 `ExprTypeParse.h.ct`、
  `ExprStaticType.h.ct`、`Lower.h.ct`），发射 C 83529 → 84025（+496：新增解析、
  签名检查与诊断代码）。切片清单仍为 76；旧语料 314 个可编译源文件的生成 C 与
  基线逐字节相同（D-029 §11）。
- **v1-PH-2 S2（D-028 下标协议）后的 live 校准**：`Emitter.h.ct` 10414 → 10467 行
  （+53：重载方法的 `$<enc(key)>` 符号后缀与 body seam 键，解析/类型匹配在
  `frontend/parse/ExprSubscript.h.ct`、`ExprTypeText.h.ct`），发射 C 82754 → 83529
  （+775：新增匹配/候选/诊断代码与 `Node.suffix` 行，生成物只对新语法变化；旧语料
  由 66 文件逐字节与 p52 夹具复核）。切片清单仍为 76。
- **v1-PH-1 S1（SH-94，纯搬移）后的 live 校准**：`Emitter.h.ct` 11257 → 11062 行
  （-195：`EmitterQuery` 11 个只读查询函数与 `EmitterMapText` 6 个 map recipe
  文本/可重复性函数整段搬出；函数体逐字节不变），发射 C 56610 → 57158（+548：
  新增两个单元的头/前置声明与搬移后的单元边界，行为由 70 语料逐字节与 25/25
  goldens 复核）。切片清单仍为 76，判别式仍各读 1 次。
- **v1-PH-1 S1 方法级拆分（SH-94，纯搬移）后的 live 校准**：`Emitter.h.ct`
  11062 → 10740 行（-322：`EmitterCore` 抽出 `struct Emitter` 与 `EmitOps`
  声明，`EmitterTry` 搬出 4 个 postfix `?` 方法；函数体逐字节不变），发射 C
  57158 → 57769（+611：四个 Core 与三个方法子单元的头/前置声明和单元边界；
  Expr/Stmt 的方法组同批）。切片清单仍为 76，判别式仍各读 1 次。方法与布局见
  [sh94-m1-core-layout](../design/sh94-m1-core-layout.md)。
- **v1-PH-2 S1b-S1（TIR typed shadow）后的 live 校准**：`Emitter.h.ct` 不变
  （10317），发射 C 68663 → 73692 行（+5029：`backend/tir/TModule`、
  `backend/tir/TBuilder`、`backend/verify/Verifier` 三个新单元的 `.c`/`.h`，
  外加每个既有单元头部的三行前向声明；TIR 默认关闭，用户语料生成物逐字节
  不变）。切片清单仍为 76，判别式仍各读 1 次。
- **v1-PH-2 S1b-S2c（LIR 全覆盖）后的 live 校准**：`Emitter.h.ct` 10376 → 10414
  （+38：impl 方法体与 plain-struct inherent 方法体的发射缝，hook 签名加
  `stmts` 模式），发射 C 79794 → 82754（+2960：TIR 的 ADT/结构体表，LIR 的
  match / 闭包 / `?` / 语句头提升 / 切片 / 字符串句柄 / switch / do-while /
  清理，V5/V6/V9 与 `bodies printed` 计数）。切片清单仍为 76，判别式仍各读
  1 次；语料 78/78 unit、295/295 函数体由 LIR 打印且逐字节，自举 72/72
  unit、1473 个函数体由 LIR 打印且整棵树逐字节。
- **v1-PH-2 S1b-S2b（LIR 发射缝）后的 live 校准**：`Emitter.h.ct` 10323 → 10376
  （+53：函数体 seam 的 hook 与 `ct_emit_ntmp`），发射 C 77933 → 79794
  （+1861：`backend/lir/Lower` 的 seam、方法/虚派发、数组 vptr 环、`foreach` /
    `loop` / 容器初值等行），76 切片与 34/26/6/8/2 不变；
  语料 78/78 逐字节、自举 65 个 `.c` unit 逐字节、seed 两轮由 gate 13 复核。
- **v1-PH-2 S1b-S2（LIR 子集）后的 live 校准**：`Emitter.h.ct` 10317 → 10323
  （+6：跳过 TIR 的 metadata defer 副本、`node_mentions` 不把它当作发射体），
  发射 C 73692 → 77933 行（+4241：`backend/lir/LModule`、`backend/lir/Lower`
  两个新单元的 `.c`/`.h`，外加每个既有单元头部的两行前向声明；LIR 默认关闭，
  用户语料生成物逐字节不变）。切片清单仍为 76，判别式仍各读 1 次。
- **LANG-29 S4/B4（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 11173 → 11257 行
  （+84：`map binding` 的 aux 12 recipe 展开、pair 键归一、候选歧义诊断与
  `--emit-map` registry 跳过），发射 C 56258 → 56610（+352：同一代码的生成物）。
  切片清单仍为 76，判别式仍各读 1 次；本次没有新增 kind 分支。
- **LANG-29 S4/B5（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 11086 → 11173 行
  （+87：表达式 `match` 的 statement-expression 发射、`emit_match_arm` 的通配位
  位测试与 `sb_assign` 的结果临时量类型回落），发射 C 55475 → 56258（+783：同一
  代码的生成物）。切片清单仍为 76，判别式仍各读 1 次；本次没有新增 kind 分支。
- **LANG-29 S3/B2（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 11003 → 11086 行
  （+83：ADT 固有 impl 的方法体发射、`match(self)` 的值解引用、方法调用与 pub
  原型的 ADT 回落），发射 C 55384 → 55475（+91：同一代码的生成物）。切片清单仍为
  76，判别式仍各读 1 次；本次没有新增 kind 分支。
- **LANG-29 S2/B3（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 10701 → 11003 行
  （+318：ADT payload 的 owning 判定、`sb` 作用域/参数/返回的通用 retain-release、
  按 variant 发射的 `T_retain`/`T_release` 与构造/绑定插入点），发射 C 55045 →
  55384（+339：同一代码的生成物，外加内建层调用点不变）。切片清单仍为 76，
  判别式仍各读 1 次；本次没有新增 kind 分支。
- **LANG-29 S1/B1（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 10446 → 10701 行
  （+255：ADT payload 布局闭合校验、按拓扑序防环/深度上限的实例壳预发射，及其
  单测注释），发射 C 54792 → 55045（+253：同一代码的生成物）。切片清单仍为 76，
  判别式仍各读 1 次；本次没有新增 kind 分支。
- `Emitter.h.ct`：8876 → 10415 行（**+1539，+17.3%**）。S88c 的增量来自 76 个
  函数头/参数/`(void)` 行与切片注释；后续阶段（SH-117、SH-118、v1-PH-0 S0.5、
  LANG-26）在同一文件继续增长，分支体本身逐字搬移（见 §3 的等价证据）。
- 每个判别函数的 `nodes[n].kind` 读数从 29/34/6/13/2 次降为 **各 1 次**；
  切片体内同结点 kind 的读取改为使用传入值 `nk`（`p88_emit` 逐个核对）。

## 2 编译/运行开销

| 指标 | 控制组 | 实验组 | 变化 |
| --- | --- | --- | --- |
| `ct-ast build --emit-c` 墙钟（5 次中位，同一台机） | 0.74 s | 0.76 s | +2.7%（噪声内） |
| `cc -Wall -Wextra -std=c99` 全产物（27 个 `.c`，5 次中位） | 0.62 s | 0.62 s | 0 |
| 发射 C 总行数（本版 ct-ast 对两棵树 `--emit-c`；实验组为 v0.88.1 复测） | 48,223 | 48,870 | +647（+1.34%） |
| 编译告警（`-Wall -Wextra -std=c99`） | 0 | 0 | 0 |
| 自举不动点 | 2 轮一致 | 2/3 轮一致 | — |

测量方法：同一目录、`TMPDIR` 私有、取 5 次 wall time 的中位数；`--emit-c` 只
计编译器自身时间，不含 `cc`。发射 C 行数用**同一版 ct-ast** 分别对基线树
（`git archive 47a8f786`）与当前树发射，隔离源码差异。

## 3 等价证据（D-017 A1）

- **第 1 层（测试语料）**：66 个语料（`test/cases/*.ct` + `examples/*/*.ct`）
  banner 归一后逐字节一致（`p88_emit` 第 3 项；清单
  [test/probes/p85_corpus_sha.tsv](../../test/probes/p85_corpus_sha.tsv)）。
- **诊断**：344 条负例 `exit + stderr sha256` 与
  [p86_error_diags.tsv](../../test/probes/p86_error_diags.tsv) 逐条一致
  （`p86_errors` 23/0；S1a-0 C1 把 `generic_too_many` 从负例改为增长正例，减 1）。
- **自举不动点**：`CT_FIXPOINT_ROUNDS=2` 与 `=3` 均逐字节一致（原始输出见 §5）。
- **第 2 层（编译器自身产物）**：允许差异；以不动点 + ASan + 行为测试验收。

## 4 sharp edge

| # | 坑 | 证据/后果 | 处置 |
| --- | --- | --- | --- |
| 1 | **不同 callee 名上限 512**：`Expr` 的 `io_names[512]` 记录全程序直接调用的源名，76 个切片把 ct-ast 自己的树推过上限（`too many distinct calls`，落在 `Pkg.h.ct`） | `ct-ast` 编译自己失败，自举链断 | 容量按 v0-PH-88 提到 1024（`io_names`/`io_owner`/`io_known`/`io_line` 与检查式），**只在 ct-ast 内部**；诊断文本不变，只是触发点后移 |
| 2 | 宏不跨单元：`io_names` 的维度写进 `Expr.h`，`#define` 只进 `Expr.c` | 用 `MAX_IO_CALLS` 宏时生成 C 报 `undeclared identifier` | 维度写死字面量 1024，检查式同数；注释说明原因 |
| 3 | `MAX_FUNCS` 曾是整程序顶层函数预算（512）；76 个新 free function 后 425 → 501 | 再切一批（>11 个函数）会撞顶 | SH-109 已把该表动态化（初值 512、安全阀 `MAX_FUNCS_MAX` 65536）；C2n-2 在同一单元只新增 `ct_internf` 这 1 个顶层 helper，表按需增长，不再是硬顶。历史 501/512 数字保留作对照 |
| 4 | `emit_node` 的 `N_DECL` 前处理**不返回**：它处理完后落回表达式语句支（`N_DECL` 也在该支的条件里） | 直接搬成函数会把原本的 fall-through 变成"已处理"，语义改变 | 该切片用三态：返回 `2` = 继续判别，其余返回值原样透传；判别处 `if (r != 2) return r;`。这是唯一一个 fall-through 支（脚本与探针均核对） |
| 5 | 方法体里的 `self` 在发射 C 中拼作 `_self`；切片是自由函数，`self` 是普通参数 | 如果切片签名写成方法会撞 `MAX_METHODS` 且改 vtable | 自由函数 + 显式 `struct Emitter *self` 参数；ABI/命名契约不变 |
| 6 | `String` 拼接/可增长 buffer **在本切片不适用** | 发射器是流式的：`self->out` 是 `FILE *`，逐 token `fputs/fprintf`，没有"先拼整行再写"的路径；剩余固定缓冲都受 `MAX_TEXT`=160 与 `header_guard(cap)` 的契约约束 | 不改：引入 `lib/std` 的 `String` 会给引导编译器增加一次分配器依赖与第二份 String 实现，收益为零（R88-3 的"必要时局部保留 buffer"）；登记为未覆盖项，供 M1/v1.1 复核 |
| 7 | **错误路径 `?`/errdefer 不适用**：L2 引导链不下降 v0-PH-40/v0-PH-44（v0-PH-86 battle A，REVIEW 已签），写进 ct-ast 源码会被原样发射成非法 C | 本切片保留原有 `return -1`/`fail_from`；没有可挂的 `?`/errdefer | 按 v0-PH-86 口径不改；与字面 `match` 同承接到 `v1-PH-0` |
| 8 | `-Wunused-variable`：切片里为了承接原函数顶部局部量（`c`/`op`/`m`）补声明，但有的分支只在嵌套作用域声明同名变量 | 首轮出现 1 条 unused 告警 | 切片内补 `(void)name;`；最终零告警 |

## 5 原始输出

```console
$ CT_FIXPOINT_ROUNDS=2 bash selfhost/check-ast.sh --fixpoint-only .temp/ct-ast
fixpoint: 2 rounds byte-identical
$ CT_FIXPOINT_ROUNDS=3 bash selfhost/check-ast.sh --fixpoint-only .temp/ct-ast
fixpoint: 3 rounds byte-identical
$ bash test/ast/p88_emit.sh .temp/ct-ast
  p88emit: slices=76
  p88emit: missing-arm negative is red
  p88emit: 66 corpus files are byte-identical
p88emit: 3 passed, 0 failed
$ bash selfhost/check-ast.sh          # 日常 2 轮
... self-compile (fixpoint: 2 rounds byte-identical) ...
```

## 6 与 v0-PH-85 spike 对照

v0-PH-85 的单切片 spike 是词法器 `next`（391 → 425 行，+8.7%；发射 C +42 行；
`--emit-c` 1053 → 994 ms，噪声内；零告警）。v0-PH-88 是**按 kind 切片**的另一种
形状：函数数增加更多（+76），行数 +5.6%，发射 C +0.88%，时间不变，零告警。
两者的共同结论一致：**切片本身不带来可测的运行时/构建开销**；差别在判据：
spike 只切一个方法，v0-PH-88 切 5 个判别函数并新增了"漏一个 kind 就掉切片"的清单
约束（`p88_emit` 的变异自测）。

## 7 未覆盖 / 遗留

1. 字面 `match` 未写进 ct-ast：L2 引导链不实现 v0-PH-84（证据
   [battle/p88-emit-match](../../battle/p88-emit-match/verdict.md)）；承接目标为
   **v1.0 seed cutover（`v1-PH-0`）**，届时把 76 个切片机械改成「一 kind 一臂，
   共用体调同一 helper」（v0-PH-84 无 or 模式）。
2. `String`/可增长 buffer 见 §4 第 6 条：判定不适用，未改。
3. `MAX_FUNCS` 已按 SH-109 动态化（初值 512 / 安全阀 65536），历史余量 11（501/512）
   不再是硬顶；C2n-2 的 `ct_internf` 是唯一新增的顶层 helper，容量按需增长。
