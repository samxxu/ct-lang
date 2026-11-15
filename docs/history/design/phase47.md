# Phase 47 — 容器键协议（`Str` 键，默认深拷贝）

> **状态：完成（2026-11-15；v0.47.0；S1–S6 全绿）**
> **归属**：本仓库维护规格与判据；实现由外部 harness 交付（[手册](../../design/phase46-52-handoff.md)）。
> **基线**：本卡最后一次提交；起点为 PH-46 收口提交（同一 `Map` 生成面）。
> **规模**：**520–820 行**（裁决席按 R47-4 上调：三份实现 + 键释放 + 诊断）。
> **版本**：`v0.47.0`（若采纳 U-4 A）。

## 0 一句话目标

让 `Map<Str, V>` 可用且默认安全：`Str` 键按长度+字节比较、`put` 时深拷贝、条目释放时释放键，内嵌 `\0` 不碰撞。

## 1 本卡做 / 本卡不做

| 做 | 不做 |
| --- | --- |
| 新增 `Map<Str,V>` 特化（第三份实现，与 `int` / `char*` 两份并列） | 不做 `put_owned`（`MapEntry` 无所有权位；见 D47-3′） |
| `Str` 键在 `put` 时**深拷贝**（`str_from_len(k.data,k.len)`），条目释放走键释放 | 不做任意用户类型键协议 |
| 每个条目增加「键释放」路径（`__key_release`），`release`/`remove`/覆盖写同步 | 不改 `char *` 键的借用语义（零迁移） |
| 诊断文案更新为四类键并指向深拷贝语义 | 不改线性扫描、插入序、`get` 返回指针形态 |
| `foreach` 暴露的键是**借用**，文档与夹具写明不得 `release` | 不做哈希、不改 `Map` 布局 |

## 2 前置依赖

PH-46 已收口（同一 `MapEntry` 发射面，v0.46.0）。`Map<Str, 用户 struct>` 夹具按已收口基线执行，不再退化为指针元素。

## 3 现状（实测）

| 探针 | rc | 输出 |
| --- | --- | --- |
| `Map<struct Str,int>` | 1 | `error: Map does not support key type 'struct Str' (use int, long or char *)` |
| `char buf[]; m.put(buf,1); 改 buf;` | 0 | `key1=0x0`（键只存指针，改缓冲即失效） |
| 泛型 `Map<K,V>` 的键比较 | — | `memcmp(&es[i].key,&k,sizeof(k))`；`Str` 为 16 字节（含 4 字节 padding），比较结果不确定 |

复现：

```sh
mkdir -p /tmp/p47 && cd /tmp/p47
# e2b.ct: Map<struct Str, int> m; m.h = 0;
# e5.ct : char buf[8]; m.put(buf,1); strcpy(buf,"key2"); m.get("key1")
"$work/ct-ast" e2b.ct -o e2b.c ; echo "type=$?"        # 1
"$work/ct-ast" e5.ct -o e5.c && cc -std=c99 e5.c -o e5 && ./e5   # 0 / key1=0x0
```

代码锚点：白名单 `selfhost/ct-ast/frontend/parse/Expr.h.ct:2174`；`char *` 特化 `lib/std/Vec.h.ct:219-296`；
泛型 `put` 的 `memcmp` `Vec.h.ct:370-376`；键只赋指针 `Vec.h.ct:391`；负例 `selfhost/check-ast.sh:6964`、`:7128`
（`L31_nested_map_key`、`map_key_bad`）。

## 4 修法方向

| 点 | 位置 | 改法 |
| --- | --- | --- |
| 白名单 | `Expr.h.ct:2174` | 增加 `Str`；文案 L47-1 |
| 第三份特化 | `lib/std/Vec.h.ct`（对照 `:219-296`） | `Map<Str,V>`：`len` 相等 + `memcmp(data,data,len)`；`foreach` 键只读 |
| 深拷贝 | 同上 `put`/覆盖分支 | `es[i].key = str_from_len(k.data, k.len)`；先释放旧键再覆盖 |
| 键释放 | 条目释放函数族 | 新增 `__key_release(Str *)` → `Str_release`；`release`/`remove`/覆盖写三处调用 |
| 诊断 | `Expr.h.ct:2174` | `Map does not support key type '<T>' (key types: int, long, char *, Str)` |

**D47-3′（冻结）**：删除 `put_owned`。`Str` 键默认深拷贝；`char *` 键维持借用并在文档写明生命周期。
理由：`MapEntry` 只有 `key`/`value` 两个字段、`ct_buf` 无空位，加所有权位会改布局与全部 `Map` golden。

**D47-6（冻结）**：`foreach` 暴露的 `Str` 键是**借用**；用户不得 `release`，否则与条目释放双释放。

## 5 任务切分

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| S0 | 只读核对三份实现与两条负例；产出「键比较矩阵」（`int`/`char*`/`Str` 的取用、覆盖、释放） | 无提交 |
| S1 | 红证：`Map<Str,int>` 类型硬错 + 改缓冲失效 + padding 比较不可靠 | `test: PH-47 红` |
| S2 | `Str` 特化（比较/put/get/remove/foreach/from） | ≤150 行 |
| S3 | 深拷贝 + `__key_release` 三处 | ≤150 行 |
| S4 | 诊断文案 + 两条既有负例断言同步 | ≤3 文件 |
| S5 | 文档：键契约（深拷贝/借用/释放）+ `foreach` 借用 | 或 `blocked-by` |
| S6 | 收口 | §6 |

## 6 验收判据

| ID | 命令 / 比对 | 通过条件 | 失败条件 |
| --- | --- | --- | --- |
| E47-1 | `p47_str_key`：`Str a=str_from_len("a\0b",3), b=str_from_len("a\0c",3); m.put(a,1); m.put(b,2);` 运行输出 `len=2 v1=1 v2=2`；另加失效负例：改源 `Str` 后原键仍命中 | 输出逐字相等 | 任一值错 |
| E47-2 | `p47_release` + `check-sanitizers.sh`：覆盖写/`remove`/`release` 后 ASAN/UBSAN 无报告；释放计数 = put 次数 | rc=0 且计数相等 | 双释放/UAF/计数不等 |
| E47-3 | 基线快照 `/tmp/p47/before-*.c` vs 收口后 `cmp`，覆盖 `Map<char*,V>` 与 `Map<int,V>` | `cmp` 全 rc=0 | 任一 diff |
| E47-4 | `p47_errors.sh`：`Map<struct X,V>` rc=1、文案 L47-1、不落 `.c`；两条既有负例（`check-ast.sh:6964`、`:7128`）更新后仍 rc=1 | 逐字命中 | 漏报/降级 |
| E47-5 | `p47_foreach`：键借用可读；文档断言「不得 release 键」；运行无崩溃 | rc=0 | 崩溃 |
| E47-6 | `bash selfhost/check-ast.sh` + `check-all.sh` | `0 failed`；末行 11 green | 任一失败 |
| E47-7 | 红证链（T-7） | 父提交 + `baseline:` | 同提交 |

## 7 范围外归属

| 项 | 归属 |
| --- | --- |
| 任意用户类型键 | 需求池（触发：第二个真实包必须自定义键） |
| `Map` 的 `has` | PH-50 |
| `Map` 元素完整性 | PH-46 |
| 哈希/有序 | 不做 |

## 8 风险与回滚

| 风险 | 信号 | 回滚 |
| --- | --- | --- |
| 深拷贝后键释放漏一处（覆盖写/remove） | ASAN 泄漏或 E47-2 计数不等 | 回滚 S3，重做三处调用 |
| `foreach` 借用被误 release | 双释放 | 回滚 S5 文档前，夹具先锁死 |
| `Str` 特化与既有两份不一致 | E47-3 有 diff | 回滚 S2 |
| 负例文案变化被当成放宽 | 既有断言 rc=0 | 回滚 S4；文案变更必须登记 |
| `Map<char*,V>` golden 漂移 | `check-goldens` 红 | 回滚 S3 的共享分支改动 |

### 9 收口记录（2026-11-15）

| 项 | 结果 |
| --- | --- |
| E47-1 | `241_map_str_key`：嵌入 NUL、源 Str 释放后仍命中；compile/build 输出一致 |
| E47-2 | `242_map_str_release`：put/覆盖/remove/release 计数各一次，`live=0`；ASAN/UBSAN 绿 |
| E47-3 | `Map<int>` / `Map<char *>` 产物与基线逐字节一致 |
| E47-4 | `p47_map_struct_key` 文案四类键；两条既有负例更新 |
| E47-5 | `foreach` 键借用可读；文档写明不得 release |
| E47-6 | check-all 11/11；check-ast 1382/0 |

tag/push：`v0.47.0` annotated tag 与分支自动 push。
