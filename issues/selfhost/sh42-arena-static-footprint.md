# SH-42 · arena 的两个静态数组把装出的 `ct` 顶到 88MB

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 运行时） |
| 严重度 | Medium（功能正确、运行内存也低，但分发体积与「编译器很小」的定位不符） |
| 锚点 | commit `61e35e4`（`v0.16.1`，2026-11-01） |
| 文件 | [Arena.h.ct:48-56](../../selfhost/ct-ast/runtime/arena/Arena.h.ct#L48-L56)、[:124](../../selfhost/ct-ast/runtime/arena/Arena.h.ct#L124) |
| 状态 | 已修（2026-11-01）：Arena、`Symbols`、`Parser.g_maps`、`Module.g_units` 四处大表改 `calloc`；`ls -lh ct` **637K**、`__DATA` **589824 B** |

## 现象

`pub struct Arena` 里是两个按上限展开的固定数组，实例是文件作用域的 `static`：

```c
pub struct Arena {
    struct Node nodes[131072];   /* Node ≈ 528 B（9 个标量 + 3×160 char） */
    int  nnode;
    char strpool[262144];
    int  nstrpool;
} use ArenaOps;
...
static struct Arena g_arena;
```

131072 × 528 B ≈ **69 MB** 静态初始化数据直接进 `__data`，`strpool` 再加 256 KB。

## 证据

```text
$ ls -lh /tmp/ctbin/ct
-rwxr-xr-x  88M   ct

$ size -m /tmp/ctbin/ct | grep "__DATA"
Segment __DATA: 105267200          # ≈ 100 MB

$ /usr/bin/time -l /tmp/ctbin/ct probe.ct -o p.c
maximum resident set size ≈ 2 MB   # 页按需映射，运行并不慢
```

即：**运行期没问题，问题只在安装包 / 分发体积**（以及「1.5 万行的编译器不该有 88MB」的叙事）。

## 影响

- 安装包、镜像层、CI 缓存都被放大 40 倍以上；
- 与 `AGENTS.md` 的「保持单文件、可一次读完」气质相反——读者会以为是编译产物没优化，而不是容量预分配。

## 修复建议

1. `nodes` / `strpool` 改为指针字段，首次使用时 `calloc`：
   - `alloc` 已经有 `nnode >= MAX_NODES` 的判界，保留上限语义即可；
   - `calloc` 失败要按本单元既有风格返回 `-1` / `die`，不要裸解引用；
2. `MAX_NODES` 保留为默认容量，另可加 `--max-nodes`（若要加，需同步 README / `language-spec` §7 / `usage` 文案，属能力变更）；
3. 不要动 L0 / L1 / L2；只改 ct-ast 运行时。

## 风险与验收

- `Arena` 是 `pub struct`，字段会落进生成头；改字段形状后，**自编不动点要求两个阶段生成物一致**，
  因此必须一次改完再跑门禁，不得在两版实现之间混跑；
- 验收：`ls -lh ct` < 5 MB、`size -m ct` 的 `__DATA` < 1 MB；`bash selfhost/check-ast.sh`（含自编不动点与
  全量语料）、`bash selfhost/check-all.sh` 九关全绿；`test/pkg` 与 `examples` 行为不变；
- 回归面：`test/ast/**` 的生成物不应有任何字节变化（Arena 不进生成物）。

## 关联

- [DOC-43](../docs/doc43-max-nodes-not-a-macro.md)：`MAX_NODES` 的宏 / 字面量双写问题（本条不动那处）
- [SH-1](max-funcs-headroom.md)：同样是「容量预分配」带来的账本问题
