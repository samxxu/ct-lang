# battle/p39-2 单方案评审 — 反对席（REVIEW）对 C 的证伪

> 已读 `C-proposal.md`（190 行）与 `verdict.md`（193 行）。本席只证伪 C，不提替代方案。
> 环境：HEAD `ac040d1`，macOS arm64 / Apple clang 21 / llvm-nm / `ld` ld-27106.1；仓内零改动，本文件是唯一写盘产物。
> C 的自认前提（`C-proposal.md:25-27`）本席接受：O1 若读作「归档成员必须逐单元」，C 不成立。

## 1 问题一：`<base>.nm` 集合断言 + `ABI_VERSION` 是否解决 V5 / V15

**结论：密封模式下解决，但功劳在「本地化」，不在 `.nm` 清单；`--no-seal` 下它就是 A′，只改名不解决。**

- **V5（符号抢占）**：真正让 `api=999` 消失的是 `cc -r` 的本地化（`C-proposal.md:21`），`<base>.nm` 只是「本地化确实发生了」的冒烟探测器。密封模式下两者集合相同（`nm -g` = 导出 = `.abi.h` 原型），清单**不携带**任何 `.abi.h` 之外的信息，因此它不是「更强的快照」，而是「密封动作的断言」。
- **V15（std 增长）**：密封模式把它结构性消掉——新增 std `pub` 函数被本地化，`nm -g` 不变、`ABI_VERSION` 不动，这是**正确**结果（V15 的病是「非 ABI 符号面暴露」，不是「符号数变了」）。这一点 C 确实优于 A，本席承认。
- **但 `--no-seal` 回到 A′**：`C-proposal.md:97` 的「逐条写入 `.nm` + 哈希并入 `<BASE>_ABI_VERSION`」= A′ 的清单 + 版本宏。`ABI_VERSION` 是生成出来的宏，**没有任何机制强制消费者读取它**；V5 在 `--no-seal` 下照旧成立（内部符号仍 external，同名 `helper` 仍可替换）。「版本会变」是**可发现**，不是**不可发生**——这与 A 被否的理由（检测≠预防）同构。
- 另有一处名不副实：C 声称清单与 `.abi.h`「互为校验」（`:39`），但二者由**同一份导出扫描**生成（`:59`）——同源派生量的互等是恒真式，不能充当校验。真正的独立校验只有 `nm` 对归档的实测集合。

## 2 问题二：`--no-seal` 是否让 J-1 名存实亡

**会，且不需要用户「滥用」——C 自己的规则就把 Linux 推向它。**

- `C-proposal.md:81`：「任一候选在 Linux 实测通过前，Linux 的 `--lib` **不得发布密封形态**；只能显式 `--no-seal`」。即：**两个目标平台里的一个，唯一可发布路径就是非洁净路径**。J-1（`question.md:18`）没有平台限定语，按此 C 的 J-1 在 Linux 上不成立。
- `C-proposal.md:123` 的失败处置把 `--no-seal` 写进错误提示：「平台本地化选项不支持 → 硬错，打印……可用 `--no-seal` 显式换取非洁净归档」。这是**官方推荐逃生门**：任何 linker 版本差异、musl/Alpine、CI 容器，都会把用户导向它。
- 标注（`:113`）是文档层面的，不改变归档的符号面；一旦 `--no-seal` 产物被分发，消费者面对的就是 A 的 ABI。J-1 于是降级为「macOS 默认值」，而不是产品判据。
- **可证伪的判据改写**：若把 J-1 写成「默认密封即可」，那 A 同样可以声称「默认……（文档注明非 ABI）」，两者不可区分；J-1 的字面读（verdict 已采）不允许这种条件化。

## 3 问题三：Linux 未测 + `cc -r` 的 warning/确定性，是否把「不可移植」转移了

**是转移，不是消除；而且「只差一个 `-Wl` 参数」低估了两平台的前置差异。**

两个分支的语义不同，不是同一个参数的两种拼法：

| | macOS（`:64`） | Linux 候选（`:75-79`） |
| --- | --- | --- |
| 机制 | **名字白名单**（列出保留者，其余 private-external） | **可见性本地化**（对 hidden 符号本地化） |
| 前置 | 导出名带前导 `_`（`:59` 生成 `.exports`） | 导出定义必须**已有 `visibility("default")`**，否则导出也会被本地化 |
| 依赖 | 名字拼写必须与 Mach-O 一致 | 依赖 D39-5（`docs/design/phase39-draft.md:59`）的「导出定义注入 `visibility("default")`」已实现——HEAD 尚未实现（verdict §3 的 V12） |

C 的 `:48` 明写每个单元以 `-fvisibility=hidden` 编译，而 `:145-153` 的 §8「未验证项」**没有一项**是「导出定义是否真的带 default 可见性」。本席 E1-r3-a 证明这个缺口是实的：在 HEAD 的发射器下（无 attribute 注入），`-fvisibility=hidden` + 名字白名单会**把导出也本地化**，`ld` 仍 `rc=0`。

## 4 E1-r3（新增，不重复前两轮）

夹具 `/tmp/p39c`：`api.c`（`int lib_api(void){return 7;}`）、`ctor.c`（`__attribute__((constructor)) static void ct_init(void){write(1,"CTOR-RAN\n",9);}`），模拟「逐单元 `.o` + 一个带 constructor 的无关单元」。

### E1-r3-a 名字白名单不覆盖 hidden：导出被静默本地化

```console
$ cc -std=c99 -fvisibility=hidden -c api.c -o api.o ctor.c  # api.o 的 _lib_api 变 hidden
$ printf '_lib_api\n' > exp.txt
$ cc -r -Wl,-exported_symbols_list,exp.txt -o sealed.o api.o ctor.o 2>warn.txt
seal rc=0
$ cat warn.txt
ld: warning: ignoring unexpected dylib '/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk/usr/lib/libSystem.B.tbd'
$ nm -g --defined-only sealed.o
                                    # 空：导出被一起本地化
$ ar rcs libseal.a sealed.o && cc -std=c99 cons.c libseal.a -o c
Undefined symbols for architecture arm64:
  "_lib_api", referenced from:
      _main in cons-1b5d62.o
clang: error: linker command failed with exit code 1
```

对照：同一对象不套 `-fvisibility=hidden`（`api_vis.o`，`T _lib_api`）时密封正常，`nm -g` 恰为 `_lib_api`。**结论**：C 的 macOS 分支正确性依赖一个 C 未列入 §8 的前置（导出定义带 default 可见性）；Linux 的 `--localize-hidden` 对该前置的依赖是**结构性**的，不是候选排序问题。

### E1-r3-b 单成员密封改变静态链接语义：未使用单元也被链入并运行 constructor

```console
$ ar rcs libunit.a api.o ctor.o            # O1 形态：逐成员
$ cc -std=c99 cons.c libunit.a -o unit_consumer && ./unit_consumer
unit run rc=0                               # 无输出：ctor.o 未被拉入
$ ar rcs libseal_vis.a sealed_vis.o          # C 形态：单成员密封
$ cc -std=c99 cons.c libseal_vis.a -o seal_consumer2 && ./seal_consumer2
CTOR-RAN
seal run rc=0
```

消费者只调用 `lib_api`，`ctor` 单元与它无关；**逐成员归档不运行该 constructor，单成员密封必然运行**。这是「静态链接语义不变」（J-3）的直接反例，且 C 的 §8.3（`:149`）只验证「constructor **不丢**」，未验证「**不多**」——两者是相反方向的断言。若 PH-39 的 R6（V13：`build` 不发射 `__ct_init`）被修好，这个差异就直接进入生产行为的差异。

### E1-r3-c 每次 `cc -r` 都带 warning；确定性本机通过

20 次运行中 2/2 出现同一条 `ld: warning: ignoring unexpected dylib ...`（见上），与「构建零警告」的项目基线与 G3 冲突；C 在 `:152` 承认但未给方案。**对 C 有利的一条**：两次 `cc -r`（间隔 1s）产出 sha256 相同——`62f25c08…98d7`（`sealed_vis.o` 与 `sealed_vis2.o`），故 E39-5 的确定性担忧在本机不成立，本席如实记录。

## 5 E2-r3（新增锚点，未在前两轮使用）

| # | 锚点 | 内容 | 方向 |
| --- | --- | --- | --- |
| E2-r3-1 | `C-proposal.md:48` | 「逐单元 `.c` → `cc -std=c99 -fvisibility=hidden …… -c`」 | 对 C 不利：把 hidden 当默认，导出可见性前置被隐去；E1-r3-a 即其后果 |
| E2-r3-2 | `C-proposal.md:145-153` | §8 七项未验证清单 | 对 C 不利：**不含**「导出定义是否带 `visibility("default")`」与「未使用单元 constructor 是否被多链」，而这两项是 J-1/J-3 的承重项 |
| E2-r3-3 | `docs/design/phase39-draft.md:59`（D39-5） | 「导出定义注入 `visibility("default")`，中间对象加 `-fvisibility=hidden`」 | 对 C 有利：前置确有卡面依据；但属未实现项（V12），C 不能在评审中当作已成立的机制 |

## 6 C 是否满足 J-1…J-5（逐条）

| 判据 | 判定 | 依据 |
| --- | --- | --- |
| J-1 ABI 洁净 | **不满足（仅 macOS 默认密封满足）** | Linux 唯一路径是 `--no-seal`（`:81`）→ 归档仍含 vtable/`Str_*`；J-1 无平台限定语 |
| J-2 平台可移植 | **不满足（严格读）** | 名义同一命令、实质两种语义 + 两个前置（`_` 前缀 / default 可见性）；Linux 未实测（`:147`）；按 verdict 对 B 的同一严格读，不能判成立 |
| J-3 静态链接语义不变 | **不满足** | E1-r3-b：单成员密封使未使用单元的 constructor 被链入并运行；C 只验「不丢」不验「不多」 |
| J-4 成本 ≤2 文件 ≤120 行 | **不满足（按对 B 的同一口径）** | C 自认 `:159-166`：实现 2 文件 60–90 行 + 夹具/门禁 2 文件 40–60 行 = 4 文件；且改 O1/§3.2/D39-5/O3/E39-2——verdict 判 B 不成立用的正是「改冻结卡交付物形态」这一口径 |
| J-5 可复现 | **成立（macOS）** | E1-r3 全部可重跑；确定性两次一致；Linux 标 `skip` 非默绿。warning 未消是 J-5 的残余风险但不是默绿 |

**结论**：C 不满足 J-1/J-2/J-3/J-4，不得按 §7.10 出口 1 采纳；应走出口 2 登记 open-question，或按下述失效条件修订后重审。

## 7 C 的失效条件（任一成立即须重开）

1. Linux 上 GNU ld 的 `-r --localize-hidden` 不被接受、或本地化后导出丢失 → 密封模式只在 macOS 存在，J-1 按平台碎裂。
2. 密封归档中未被消费者引用的单元仍被链入并执行 constructor（本机已观测）→ J-3 不成立；R6 修好后升级为生产行为差异。
3. `--no-seal` 在任一目标平台成为**唯一**可用路径（Linux 现状即如此）→ J-1 名存实亡。
4. `cc -r` 的 `ld: warning:` 未消除而门禁靠 allowlist 转绿 → 违反 J-5「不得默绿」与项目零警告基线。
5. `<base>.exports` 的前导 `_` 归一漏做/多做 → 导出被本地化（E1-r3-a 已观测：`ld` 退出 0、链接失败）→ 证明「1 个参数」实为「1 个参数 + 2 个前置」。

## 8 本席对 C 的最低修订要求（不改判据，只补承重项）

1. `--no-seal` 不产出可发布 `--lib` 归档（或从 `--lib` 移除，仅留内部调试）；否则删除 J-1 的平台无关主张。
2. §8 补入「导出 `visibility("default")` 注入已验证」与「未使用单元 constructor 不多链」两条，后者需新增判据（J-3 或 E39 系列）。
3. Linux 实测通过前，C 的 J-1/J-2 只能写 `skip`，不得写「成立」。
4. 消除 `cc -r` 的 `ld: warning:`，或证明它不进零警告门禁；不得 allowlist。
