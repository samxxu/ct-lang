# P-7.4-4：`Map<Str,V>` key 块与 `str_slice`/`str_dup` 命名迁移

baseline: c3f2e0ea

> 日期：2026-11-20；DEV（隔离原型 `/tmp/p74`，由 [run.sh](run.sh) 重建）
> 原型补丁：[prototype.patch](prototype.patch)；[D-013](../../../decisions/D-013.md) §1.3。
> 主仓未改 `selfhost/**`、`lib/std/**`、`test/**`。

## 0. 结论

| 项 | 结果 |
| --- | --- |
| 编译 + 运行 + 行为等价（对照旧 `test/ast/241_map_str_key`） | **通过**：15 步输出逐步对齐，见 §3 |
| key 块：owning `String` 存储、借用 `Str` 查找 | **通过**：`put`/`get`/`has`/`at`/`remove`/`clear`/`release` |
| `str_slice` 返回借用视图 | **通过**：`str_slice(s,1,3)` 的 `len=3`、零分配（无 `ct_str_live` 增量） |
| 深拷贝改名 `str_dup` | **通过**：`str_dup(view)` 得到 `refs=1` 的独立 owning 句柄 |
| 负例：`Map<Str,V>`（借用作存储 key） | **通过**：硬错并给出迁移方向 |
| 原始输出 / 退出码 | §3；harness `3 passed, 0 failed`，退出码 0 |

## 1. 原型改动

| 位置 | 改动 |
| --- | --- |
| `lib/std/Str.h.ct` | 新增 `str_slice(Str,int,int)`（视图）、`str_dup(Str)`（深拷贝）、`str_dup_len`；新增 `impl<V> Map<String,V>` key 块 |
| `selfhost/ct-ast/frontend/parse/Expr.h.ct` | `Map` key 白名单加 `struct String`；`Map<Str,V>` 在通用白名单前单独拒绝并给迁移提示 |
| `selfhost/ct-ast/frontend/parse/Expr.h.ct` | 实例方法解析按 impl 块的**具体度**选块（`Map<String,V>` 覆盖泛型 `Map<K,V>`） |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct` | 同上的 emit 侧 shadow 规则：更具体的块拥有同名方法，且与声明先后无关 |
| `test/p74/map_str/**` | 正例、负例、期望输出 |

为什么 key 是 `String` 而不是 `Str`：A.4 P-4.2 把 `Map<Str,int>` 列为**借用出现在存储位置**的硬错；
key 块必须把借用 key 深拷贝成 owning 句柄。原型的 `put(Str k, V v)` 接受借用查找键，内部用
`str_dup` 语义分配独立 key；`get`/`has`/`remove` 只读借用，不分配。

## 2. 命令

```console
$ cd /tmp/p74-evidence
$ CT_STD_DIR=$PWD/lib/std test/p74/.build/ct-ast --allow-c-boundary \
      test/p74/map_str/prog.ct -o /tmp/map.c
$ cc -Wall -Wextra -std=c99 /tmp/map.c -o /tmp/map
$ /tmp/map
$ CT_STD_DIR=$PWD/lib/std test/p74/.build/ct-ast --allow-c-boundary \
      test/p74/map_str/neg_map_str.ct -o /tmp/n.c    # 期望非 0
$ CT_AST=test/p74/.build/ct-ast bash test/p74/map_str.sh
```

## 3. 原始输出

```console
$ /tmp/map
put a=1 b=1
len=2 v1=1 v2=2
has a2=1 missing=0
entry0 key len=3 starts=97 value=1
overwrite=1 v1=7 len=2
remove=1 len=1
get after remove=7
release=0
view=3 own=3 ownrefs=1
key len=3
$ echo $?
0
```

与旧 `test/ast/241_map_str_key/prog.expected.out` 的行为对照：

| 旧输出 | 新输出 | 等价性 |
| --- | --- | --- |
| `len=2 v1=1 v2=2` | 同 | 内容比较（`len` + `memcmp`），嵌入 NUL 是数据 |
| `source released: len=2 v1=1` | 由 `has a2=1 missing=0` 覆盖 | key 深拷贝，源句柄释放后仍可查 |
| `key len=3 starts-a=1 second=0 value=1` | `entry0 key len=3 starts=97 value=1` | `entry` 返回借用副本；`byte_at(0)=97='a'` |
| `overwrite=1 v1=7 len=2` | 同 | 覆盖时不增长，旧 key/value 各释放一次 |
| `remove=1 len=1` / `get after remove: 7` | 同 | 尾部左移，存活条目句柄不变 |
| `release=0` | 同 | 最后一个句柄释放全部 key/value |

`cc -Wall -Wextra -std=c99` 退出 0、stderr 0 字节。

负例：

```console
$ test/p74/.build/ct-ast --allow-c-boundary test/p74/map_str/neg_map_str.ct -o /tmp/n.c
test/p74/map_str/neg_map_str.ct:4:19: error: Map key type 'Str' is a borrowed view; use 'String' (owning) or the legacy 'std::str::Str'
$ echo $?
1
```

整体 harness：

```console
$ CT_AST=test/p74/.build/ct-ast bash test/p74/map_str.sh
PASS map_str (owning key, borrow lookup, slice/dup) compile+run+behaviour
PASS map_str empty-handle release path (no abort)
PASS neg_map_str (borrowed key refused, migration named)
summary: 3 passed, 0 failed
$ echo $?
0
```

## 4. 限制

1. **key 分配不计入 `ct_str_live`**：实例方法内联 `malloc`，原型的存活计数只覆盖 `str_dup`/`String`
   路径；泄漏侧因此靠 ASan（`asan.md`）而不是该计数。
2. **`from(...)` 只做追加**：原型 `Map<String,V>.from` 不合并重复 key（旧块会覆盖）；本证据没有
   用 brace 构造，产品实现必须补齐覆盖语义。
3. **`entry`/`foreach` 返回借用副本**（D47-6 原语义）：调用方 `release` 会破坏条目，原型的测试
   只读；没有新增借用检查。
4. **key 比较是 O(n) 逐字节**，没有哈希索引，与旧 `Map` 相同；`String` key 的 `memcmp` 使用
   `len`，嵌入 NUL 当数据。
5. 只证明 `Map<String,int>`；`Map<String,String>`、`Map<String,Vec<...>>` 的 value glue 未逐个跑。
