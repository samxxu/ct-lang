# TEST-19 · 夹具依赖 `printf` 参数求值顺序（x86-64 与 arm64 结果不同）

| 项 | 值 |
| --- | --- |
| 模块 | test（`test/ast/**` 的行为夹具） |
| 类型 | 测试夹具缺陷（依赖未指定行为，导致 CI 只在 x86-64 上红） |
| 严重度 | Medium（CI 假失败；不涉及编译器产物） |
| 状态 | `open`（DEV 已处置，待复核） |
| 锚点 | `v0.63.0`（`369a2606`） |
| 承诺出处 | [AGENTS §6 验证](../../AGENTS.md)；[ci.yml](../../.github/workflows/ci.yml) 的 `ubuntu-gcc` 权威 job |

## 现象

`ubuntu-gcc` 在 v0.63.0 上红：

```console
  FAIL  241_map_str_key: program output differs: … remove=1 len=2 …
  FAIL  p47/map-str-key: Map<Str, V> key protocol failed
```

本机（macOS arm64 / Apple clang）与 podman **arm64** 的 gcc 13 都绿；podman
`--arch amd64 docker.io/library/gcc:13` 复现：

```console
$ gcc -std=c99 241.c -o 241 && ./241
…
remove=1 len=2          # 期望 remove=1 len=1
```

## 根因

夹具写的是 `printf("remove=%d len=%d\n", m.remove(b), m.len());`。C 的实参求值顺序
未指定：GCC/x86-64 从右往左（先算 `len()` → 2），Apple clang/arm64 从左往右 → 1。
夹具把"两个有副作用的实参"放进同一次调用，属测试自身缺陷（3.9 `test-fix`）。

## 处置（`test-fix`）

`test/ast/241_map_str_key/prog.ct` 改为两条语句（`removed = m.remove(b);` 再 `printf`），
`prog.expected.out` 不变。x86-64 复跑 `diff` 与期望一致。

## 未做（后续）

同样的模式目前只此一处（全仓 `.ct` 扫描确认）。建议在门禁里加一条"`printf` 实参里
同时出现变更调用与读取调用"的 lint；本轮未加，记在 [TEST-19 的跟进] 里。

## 关联

- [p47 探针](../../test/ast/p47_map.sh)：直接复用该夹具，故同一条根因；
- [SH-87](sh87-builtin-str-live-false-negative.md)：另一条未决 P1。
