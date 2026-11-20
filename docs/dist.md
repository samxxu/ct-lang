# 分发产物：`ct-linux-x64.tar.gz`

> 中文 · PH-83（v0.83.1）· 契约 [§4.4](planning/ct-pkg-get-contract.md)、[D-014](decisions/D-014.md) 第 6 条

每个 MINOR 发布一份 Linux x64 产物，供 `ct-pkg/index` 的 CI 与不装源码的用户钉版本使用。
产物**不入 git**（`dist/` 在 `.gitignore`）；发布时上传到 GitHub Release 的稳定 URL。

## 1. 产物

```text
ct-linux-x64.tar.gz           # 内含 ct 与 ctc -> ct 符号链接
ct-linux-x64.tar.gz.sha256    # `<hex>  ct-linux-x64.tar.gz`，sha256sum -c 可校验
```

```console
$ tar -tzf dist/ct-linux-x64.tar.gz
ct
ctc
$ tar -xzf dist/ct-linux-x64.tar.gz -C /tmp/ct-dist
$ /tmp/ct-dist/ct -v
ct v0.83.1
```

安装形态沿用单入口约定：把 `ct` 放进 `~/.local/bin`，`ctc` 是同一二进制的兼容别名
（`ln -s ct ctc`，tar 里已经是符号链接）。**不是**多文件运行时，也没有动态依赖。

稳定 URL（发布后）：

```text
https://github.com/samxxu/ct-lang/releases/download/v<MAJOR>.<MINOR>.<PATCH>/ct-linux-x64.tar.gz
https://github.com/samxxu/ct-lang/releases/download/v<MAJOR>.<MINOR>.<PATCH>/ct-linux-x64.tar.gz.sha256
```

index CI 钉版本时校验 sha256，再 `tar -xzf` 取 `ct`；不要 `curl | sh` 未校验的二进制。

## 2. 构建

同一套四级自举（L0 → L1 → L2 → ct-ast），只把最后一步换成 Linux x86-64 目标：

```console
# Linux 主机（权威路径；优先静态链接，缺静态 libc 时回退到宿主 glibc）
$ bash selfhost/make-dist.sh

# macOS 主机：zig cc 交叉编译到 static musl
$ ZIG=/path/to/zig bash selfhost/make-dist.sh --cross /path/to/zig
```

`make-dist.sh` 打印 `linkage`：`static`（Linux 静态）/ `static musl`（zig 交叉）/ `dynamic (host glibc …)`。
**glibc 基线**：动态产物只能在构建机的 glibc 及以上运行；需要最大兼容性时用 zig 的 static musl。
产物名固定为 `ct-linux-x64.tar.gz`，版本取 `selfhost/ct-ast/main.ct` 的 `CTC_VERSION`。

构建后 `make-dist.sh` 会做一次冒烟：在本机是 Linux 时直接跑 `./ct -v`；否则调用
`selfhost/run-linux-binary.sh`（见 §3）。两者都不可用时打印 `smoke: UNVERIFIED` 并**不**声称通过。

## 3. 在非 Linux 主机上验证 Linux 二进制

`selfhost/run-linux-binary.sh` 用 QEMU 启动一个最小 Linux（Alpine 内核 + 静态 busybox +
一次性 initramfs），把二进制放进去执行，转发 stdout 与退出码。资产不入 git，放在
`.temp/ph83/linux/`（或 `CT_LINUX_ASSETS` 指定的目录）：

```console
$ mkdir -p .temp/ph83/linux
$ curl -fsSL https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/netboot/vmlinuz-virt \
    -o .temp/ph83/linux/vmlinuz
$ curl -fsSL https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox \
    -o .temp/ph83/linux/busybox

$ sh selfhost/run-linux-binary.sh dist-ct/ct -v
ct v0.83.1
```

需要 `qemu-system-x86_64`、`cpio`、`gzip`；缺任一项时脚本退出 77（skip），不伪装成功。
这是本仓在 macOS 上验证 S83d 的路径：zig 交叉构建 + QEMU 启动 Linux 后跑 `ct -v`。

## 4. 验收（E83-6）

```console
$ sh test/ast/p83_dist.sh --require
ok   sha256sum -c accepts the artefact
ok   sha256 matches <hex>
ok   the tarball contains ct and ctc only
ok   unpacked ct is executable
ok   unpacked ctc is the ct symlink
ok   ELF 64-bit x86-64 (...)
ok   unpacked ct -v prints 'ct v0.83.1'
p83_dist: OK
```

`--require` 是收口/发布记录用的严格模式：产物缺失或无法在 Linux 上运行即失败。常规
`check-ast` 接线不带 `--require`，在没有 `dist/` 的 CI 上报 `skip`（77），不把“没产物”
记成通过。

## 5. 已知边界

| 项 | 现状 |
| --- | --- |
| 平台 | 只发 `linux-x64`（D-014 第 6 条最小产物）；macOS / Windows 产物不在 PH-83 范围 |
| 可复现 | 未做 bit-for-bit 复现：tar 的 mtime/uid 未归一，zig 版本也影响产物；发布以 `.sha256` 钉住当次产物 |
| 吊销 | 没有签名/pin 基础设施（D-014 第 6 条）；只提供 sha256 + 稳定 URL |
| 上传 | 本卡不 push、不打 tag；产物在本地 `dist/` 生成并验证，上传由发布动作执行 |
