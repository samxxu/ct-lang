# wave1-demo — the `hal` traits and the standard library together

> English · [中文](#中文)

A single Ct program that uses the Wave 1 packages:

- [`hal`](https://github.com/ct-pkg/hal) — the contract: `Uart`, `Gpio`,
  `Log`, plus the namespace entry `Clock`;
- [`hal-posix`](https://github.com/ct-pkg/hal-posix) — one `posix_hal` instance
  that boxes into the three object traits; `Clock` is called as
  `hal::Clock.nowMs()`;
- [`std`](https://github.com/ct-pkg/std) — zero-cost mappings over `string.h`,
  `stdio.h` and `math.h` (`std::str`, `std::io`, `std::math`).

## Running it

> **TODO(2026-11-06, updated 2026-11-23):** `std` 0.20.0 is published and has an
> index row, so `ct get std` works. `hal` / `hal-posix` still have no `v0.1.0`
> tag or index row (the `1.x` line was withdrawn), so `ct get hal-posix` in the
> recipe below still fails. Until both are re-tagged and `ct-pkg/index` is
> refreshed, build against the checkouts:
>
> ```sh
> ct build -I ../../../ct-pkg/hal -I ../../../ct-pkg/hal-posix -I ../../../ct-pkg/std \
>     --ns-root ../../../ct-pkg/hal \
>     --cflags '-D_POSIX_C_SOURCE=200809L' --ldflags '-lm' src/main.ct -o build
> ```

```sh
mkdir -p /tmp/wave1 && cd /tmp/wave1
cp /path/to/examples/wave1-demo/src/main.ct .
printf 'name = wave1-demo\nversion = 0.1.0\n' > ct.pkg

ct get hal-posix       # pulls hal through the package's `dep`
ct get std
ct update
ct verify
ct install             # prints one command, e.g.
                       # ct build -I vendor/std -I vendor/hal -I vendor/hal-posix \
                       #   --cflags '-D_POSIX_C_SOURCE=200809L' --ldflags '-lm' main.ct -o build
```

Run the printed command, then `./build`; compare against
[demo.expected.out](demo.expected.out). The same tree serves macOS and Linux
(x86_64 / aarch64): `hal-posix` carries no `#ifdef`, and CI runs the aarch64
half under QEMU.

The first line (`hal`) comes from `Uart.send` on stdout; the rest come from
`std::io`, so the output is fixed and independent of the clock.

## 中文

同一个 Ct 程序把 Wave 1 的三个包放在一起用：`hal`（契约）、`hal-posix`
（一个 `posix_hal` 实例装箱成三个对象 trait；`Clock` 是 namespace 入口，
按 `hal::Clock.nowMs()` 调用）、`std`（`string.h` / `stdio.h` / `math.h` 的零成本映射）。

`std` 0.20.0 已发布并有索引行，`ct get std` 可用；`hal` / `hal-posix` 仍没有
`v0.1.0` tag 或索引行（1.x 版本线撤回后未重发），所以 `ct get hal-posix` 仍会
失败。在重新发布前，只能按上面的 `-I` 方式直接对着 `ct-pkg/` 的检出编译。

按上面的步骤在临时目录里 `ct get hal-posix`、`ct get std`，再 `ct update`
/ `ct verify` / `ct install`，执行 `ct install` 打印的那一条命令，最后
`./build` 并与 `demo.expected.out` 比对。输出第一行 `hal` 来自
`Uart.send`，其余来自 `std::io`，因此固定且与时钟无关。
