# wave1-demo — the four `hal` traits and the C library mappings together

> English · [中文](#中文)

A single CT program that uses the Wave 1 packages:

- [`hal`](https://github.com/ct-pkg/hal) — the contract: `Uart`, `Gpio`,
  `Clock`, `Log`;
- [`hal-posix`](https://github.com/ct-pkg/hal-posix) — one `posix_hal` instance
  that boxes into all four traits;
- [`clib`](https://github.com/ct-pkg/clib) — zero-cost mappings over
  `string.h`, `stdio.h` and `math.h`.

## Running it

```sh
mkdir -p /tmp/wave1 && cd /tmp/wave1
cp /path/to/examples/wave1-demo/src/main.ct .
printf 'name = wave1-demo\nversion = 0.1.0\n' > ct.pkg

ct get hal-posix       # pulls hal through the package's `dep`
ct get clib
ct update
ct verify
ct install             # prints one command, e.g.
                       # ct build -I vendor/clib -I vendor/hal -I vendor/hal-posix \
                       #   --cflags '-D_POSIX_C_SOURCE=200809L' --ldflags '-lm' main.ct -o build
```

Run the printed command, then `./build`; compare against
[demo.expected.out](demo.expected.out). The same tree serves macOS and Linux
(x86_64 / aarch64): `hal-posix` carries no `#ifdef`, and CI runs the aarch64
half under QEMU.

The first line (`hal`) comes from `Uart.send` on stdout; the rest come from
`clib::Stdio`, so the output is fixed and independent of the clock.

## 中文

同一个 CT 程序把 Wave 1 的三个包放在一起用：`hal`（契约）、`hal-posix`
（一个 `posix_hal` 实例装箱成四个 trait）、`clib`（`string` / `stdio` /
`math` 的零成本映射）。

按上面的步骤在临时目录里 `ct get hal-posix`、`ct get clib`，再 `ct update`
/ `ct verify` / `ct install`，执行 `ct install` 打印的那一条命令，最后
`./build` 并与 `demo.expected.out` 比对。输出第一行 `hal` 来自
`Uart.send`，其余来自 `clib::Stdio`，因此固定且与时钟无关。
