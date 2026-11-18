# PH-69-R1 施工计划（跨单元可检）

> 状态：R1 未开工；本文件把 `ct check` 支持 `import` 的路径拆开，供下一次会话直接施工。
> 依据：`typecheck-semantic-plan.md` §3（v0-PH-69）、`phase69.md` §3 R1。

## 0 现状

- `ct check` 在 `Parser` 里直接拒绝 `import`：
  `Parser.h.ct:1438` → `'import' requires multi-file mode: use 'ct build' (ct check is single-unit)`；
- 多单元加载与单元图在 `frontend/module/Module.h.ct` 的 `build_main`（`1543` 起，约 1,000 行）里，
  加载、类型检查与发射**混在同一条流程**；没有“只检查不写产物”的开关；
- `Emitter` 的写入口是 `emit_program` / `write_header` / `write_map` / `write_model`
  （`backend/emit/Emitter.h.ct:2628`、`6228`、`5741`，导出在 `6539`–`6585`），
  没有 `no-write` 标志。

## 1 推荐路径（B）：给 Emitter 加 no-write，check 复用 build 的单元图

**为什么不是 A（拆 `build_main`）**：拆加载/检查/发射三相位是正确终态，但 `build_main`
与 30+ 个 emit 调用点交织，拆完还要保证 build 行为逐字节不变；一轮内做不完。

**B 的做法**

1. `Emitter` 加 `int no_write;` 与 `pub void ct_emit_set_no_write(int on)`；
2. `emit_program` / `write_header` / `write_map` / `write_model` 在 `no_write` 时
   只做校验与内存写入，不 `fopen`/`fprintf` 到磁盘；
3. `Module.build_main` 识别 `check_only` 环境：加载全部单元、跑解析/类型检查，
   跳过所有 emit 调用（或让它们变 no-op）；
4. `Driver` 的 `ct check`：先探测输入是否含 `import`（现有 `src_has_word` 可复用），
   含则走 `build_main` 的 check_only 分支，不含则保留现有单单元路径；
5. 退出码与诊断格式与单单元 `ct check` 一致；`--types` 透传。

**验收（R1）**

- `p69_unitgraph.sh`：一个双单元夹具（`lib.ct` + `main.ct`，`import`）跑
  `ct check --types main.ct` 退出 0、无产物（检查前后目录只有输入文件）；
- 负例：跨单元签名不匹配必须报错；
- `check-all` 11/11，golden 不变。

## 2 风险

| # | 风险 | 缓解 |
| --- | --- | --- |
| 1 | `build_main` 里 emit 调用点漏改，仍写文件 | 探针断言目录无新文件；CI 跑在干净树 |
| 2 | `check_only` 改变 build 行为 | 默认关闭；只由 `ct check` 打开 |
| 3 | 单元图加载失败路径的退出码不同 | 复用 build 的错误路径，补负例 |

## 3 估算

- Emitter no-write：0.5 天；
- `build_main` check_only 分支 + Driver 路由：1–2 天；
- 探针与回归：0.5 天。
