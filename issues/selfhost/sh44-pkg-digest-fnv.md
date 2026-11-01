# SH-44 · `ct.lock` 的内容摘要用 FNV-1a + 加法折叠，非抗碰撞

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（包管理 `tool/pkg`） |
| 严重度 | Medium（`ct install` 的离线校验以此为准；摘要可被构造出碰撞，供应链信任面偏薄） |
| 锚点 | commit `61e35e4`（`v0.16.1`，2026-11-01） |
| 文件 | [Pkg.h.ct:249-282](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L249-L282)、[:284-318](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L284-L318)、[:684-690](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L684-L690) |
| 状态 | 已修（2026-11-01）：`Pkg.h.ct` 改 SHA-256（路径排序 + `路径\n` + 内容），lock 写 `sha256:<64 hex>`，旧格式显式报「unsupported digest」；`test/pkg/run.sh` 夹具同步 |

## 现象

包摘要由三个非密码学构件拼成：

```c
/* FNV-1a over a string, the same fold the cache key uses. */
unsigned long pkg_digest(const char *s)  { /* h ^= c; h *= 16777619; */ }
unsigned long file_digest(const char *path) { /* 同上，按字节读文件 */ }

/* Additively fold every regular file under `dir` … */
total += self->file_digest(full) ^ self->pkg_digest(r);   /* 逐文件相加 */
```

得到的 `dir_digest` 写进 `ct.lock`（`Pkg.h.ct:688`），`ct install` 离线时据此判断「摘要相符」。
FNV-1a 是**校验和**，不是摘要：没有抗原像性 / 抗第二原像性，且逐文件**加法折叠**还可互相抵消
（两个文件的差异可以配平）。

## 影响

- 若 `ct.lock` 或 `vendor/` 被改动，攻击者可以构造出相同 `dir_digest` 的文件树，
  `ct install` 会照常放行——这正是 lock 文件要防的那类场景；
- 报告口径「`ct.lock` 被改动后无法被察觉」略重（正常改动会失配），准确说法是
  **可被刻意构造碰撞**。

## 修复建议

1. 换成 SHA-256（BLAKE3 亦可），逐文件出摘要后按**路径排序**再整体哈希，去掉加法折叠；
2. 摘要字段加算法前缀（如 `sha256:`），旧格式显式报「不支持的摘要格式」，不做静默降级；
3. 迁移会让现有 `ct.lock` 失效——需明确是否接受（属兼容性变更，需授权），并同步
   `test/pkg/run.sh` 的夹具（其中已有摘要不符的负例）；
4. `ct.lock` 可选验签属独立议题，不在本条内。

## 验收

- 新 lock 的摘要为 64 位十六进制（或带前缀），同一内容在不同机器 / 不同 `readdir` 顺序下稳定；
- 篡改 `vendor/` 任一文件的**同尺寸**改动必须失配（现有负例已覆盖尺寸不同的情形）；
- `test/pkg/run.sh` 全绿；九关全绿。

## 关联

- 文档口径：README「`ct install` 离线校验 `ct.lock` 与 `vendor/`」
- [SH-43](sh43-build-no-cc.md)：同一轮第三方评估的工具链条目
