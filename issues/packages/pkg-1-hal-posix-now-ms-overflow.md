# PKG-1 · `ct-pkg/hal-posix` 的 `now_ms` 在开机约 24.8 天后回绕为负，违反单调契约

| 项 | 值 |
| --- | --- |
| 模块 | packages（外部仓库 `ct-pkg/hal-posix`） |
| 严重度 | **Medium** |
| 锚点 | `ct-pkg/hal-posix` tag `v1.0.0`（索引行 `sha256:b994b057117…`）；本仓库 `553d300`（`v0.18.0`） |
| 文件 | [PosixHal.h.ct#L61-L67](https://github.com/ct-pkg/hal-posix/blob/v1.0.0/PosixHal.h.ct#L61-L67)；契约见 [Clock.h.ct#L1-L13](https://github.com/ct-pkg/hal/blob/v1.0.0/Clock.h.ct#L1-L13) |
| 状态 | 已修（2026-11-02，`ct-pkg/hal-posix` commit `7a956ee`，`ct.pkg` 已改为 `1.0.1`；**tag / 索引尚未更新**，见「处置」） |

## 现象

`hal` 契约规定 `now_ms` 返回**单调不减**的毫秒数（`int now_ms();`），而平台包直接返回
自 `CLOCK_MONOTONIC` 起点（开机）以来的毫秒数并强转 `int`：

```ct
int hal_posix_now_ms(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}
```

## 证据

- `2^31 ms ≈ 24.86 天`。开机满 24.8 天后该值越过 `INT_MAX`，之后为负并继续递增——两次相邻调用
  仍「递增」，但整条序列不再单调不减，也失去「毫秒数」的可解释性（+24.8 天后再过 24.8 天又会回绕）。
- `ts.tv_sec * 1000` 在 `time_t`（64 位 `long`）里先算再转 `int`；只有最终转换溢出，但转换是
  实现定义行为，且 `INT_MIN` 起算的顺序比较会失败。
- 现有验证抓不到：`examples/wave1-demo/src/main.ct` 只做 `clock.now_ms()` 的相邻比较
  （`clock=1`），开机几十秒内不可能越界；`packages.yml` 的 host / aarch64 job 同样只跑 demo。
- 索引重构核对通过（`v1.0.0` 重算摘要与索引行一致），所以这不是分发问题，而是**已发布内容**的问题。

## 影响

长期运行的设备（网关、边缘节点）在开机 24.8 天后，任何依赖 `now_ms` 做超时 / 间隔 /
排序的逻辑都会出现负值比较错误；契约是 `hal 1.0.0` 冻结的，调用方会按「int + 单调」写代码。

## 修复建议

在 `ct-pkg/hal-posix` 内做**基线减法**（不改 `hal` 契约，`int` 足够表示从首次调用起的 24.8 天）：

```ct
static long g_t0_ms = -1;   /* 首次调用记为 0，之后返回相对毫秒 */

int hal_posix_now_ms(void)
{
    struct timespec ts;
    long ms;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    ms = (long)ts.tv_sec * 1000 + (long)(ts.tv_nsec / 1000000);
    if (g_t0_ms < 0) g_t0_ms = ms;
    return (int)(ms - g_t0_ms);
}
```

- 这是**补丁级**修复（行为仍是「单调不减的毫秒计数」），发 `v1.0.1`，更新 `ct-pkg/index` 的
  `tag` 与摘要，Wave 1 demo 无需改。
- 若要保留「开机绝对毫秒」语义，则必须把 `Clock.now_ms` 改成 `long`/`int64`——那是 `hal 2.0.0`，
  不在 1.x 内做。
- 顺带把 demo 或包内测试补一条「首次调用为 0」的断言（当前只测相邻单调）。

## 验证

在 `hal-posix` 内假造 `ts.tv_sec = 2^31/1000 + 1` 的探针，修复前后返回值符号相反；
真机上可用 `qemu` 或直接对 `struct timespec` 打桩验证，不必等 24.8 天。

## 处置（2026-11-02）

已在 `ct-pkg/hal-posix` 采用「基线减法」，commit `7a956ee`，`ct.pkg` 的 `version` 改为 `1.0.1`：

```ct
static long hal_posix_t0_ms = -1;

int hal_posix_now_ms(void)
{
    struct timespec ts;
    long ms;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    ms = (long)ts.tv_sec * 1000 + (long)(ts.tv_nsec / 1000000);
    if (hal_posix_t0_ms < 0) hal_posix_t0_ms = ms;
    return (int)(ms - hal_posix_t0_ms);
}
```

**确定性证据**：把 `clock_gettime` 打桩（`-Dclock_gettime=stub_clock_gettime`），同一份探针
分别在修复前后编译运行（`ct build` 生成的 C + 探针，macOS arm64，`-Wall -Wextra` 零告警）：

| 时刻 | 修复前 | 修复后 |
| --- | --- | --- |
| 开机 50 分钟（首次调用） | `3000000` | `0` |
| 再 400 ms | `3000400`（差 400） | `400`（差 400） |
| 开机 24.9 天 | **`-2147478649`** | `2144488647` |

**剩余限制**：`int` 毫秒仍有 24.8 天跨度，现在计的是**进程运行时长**而不是开机时长；
进程连续运行超过 24.8 天仍会回绕。要把这个也去掉只能改契约（`long` / `uint64`），
那是 `hal 2.0.0`，不在 1.x 内做。

**发布待办**（未执行，需显式授权）：

1. 在 `ct-pkg/hal-posix` 打 `v1.0.1` tag 并推送；
2. `ct-pkg/index` 里跑 `tools/refresh-index.sh`（或等夜间 workflow）更新 `hal-posix` 的 tag 与摘要；
3. `~/vscspace/ct-pkg/tools/repos.txt` 的 `hal-posix` 行从 `v1.0.0` 改为 `v1.0.1`。

**顺序要求**：本仓库 `examples/wave1-demo/src/main.ct` 已把 `clock` 行收紧为
`t2 >= t1 && t1 == 0`（期望输出仍是 `clock=1`，`demo.expected.out` 不变），这样绝对毫秒的回归
会在 `packages.yml` 的宿主与 aarch64 job 上直接失败。实测：同一份 demo 链接 `v1.0.0` 的
`hal-posix` 输出 `clock=0`，链接 `1.0.1` 输出 `clock=1`。因此**先发包与索引、再推本仓库**，
否则包门禁会在 `v1.0.0` 上红。
