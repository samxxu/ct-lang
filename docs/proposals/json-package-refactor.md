# 计划：`json` 包重构

| 项 | 值 |
| --- | --- |
| 状态 | **计划**（2026-11-12；只写方案与顺序，本轮不动手） |
| 对象 | `ct-pkg/json`（仓库外维护；本仓不再引入子模块） |
| 依据 | 生产可用性评估（只读实测，仓库外产物，未入库）；本文引用的行号已按包内 `json.ct` 复核 |
| 已定决策 | 不实现可变 DOM；需要建树、改节点、深拷贝时直接用 cJSON（`docs/proposals/ct-pkg-agent-runtime.md`，2026-11-12） |
| 不做 | 可变 DOM、流式/SAX、C ABI 导出（等 Phase 39 `ct build --lib`） |

## 0 现状

- 形态：单文件 `json.ct`（2286 行），库 + demo + 自测同文件；`main`（`json.ct:2275`）驱动 125 条 `ok` 断言与 20 条错误用例，golden 是同目录的 `json.expected.out`。
- 读取模型：一次性全量校验 + `JsonView{start,len}` 只读切片，查找时重扫（`json.ct:126-141`、`1590-1623`）。
- 写入模型：调用方给缓冲区，`JsonOut` 追写，深度栈在结构体里（`json.ct:92-101`、`690-704`）。
- 分配：全文无 `malloc/free/realloc/calloc`；解析实测约 1.9 GB/s（38.9 MB / 21 ms）。
- 定位：进 ct-pkg、不进 `std`；版本 `0.1.x`，1.0 前 API 可变。迁出 `examples/` 只完成"能装进包"，不等于"可对外承诺"。

## 1 最该还的结构债：逐 kind 的 ops 对象

现状：`trait JsonValue` + 7 个空 ops 结构体（`json.ct:884-918`），7 个 `impl JsonValue for ...`（`json.ct:964-1533`）共 **77 个方法**；其中 **40 个是"kind 不对"的桩**，方法体合计约 **166 行**（含多行签名；早前估算的"34 个 / 约 136 行"没把 `member` 这类两行签名计入，本文按实测数字）。桩的形态完全一致：

```ct
int count(struct JsonDoc *doc, struct JsonView v) {
    doc->read_err = JSON_READ_KIND;
    return -1;            /* 或 return 0; / return jv_missing_view(); */
}
```

为什么是债：

1. 每个 kind 要写 11 个方法，真正有实现的只有 37 个，其余是复制粘贴；
2. 新增一个 kind（或改一个 trait 方法签名）要动 7 处；
3. 7 个 ops 结构体是纯实现细节，却因为 `use JsonValue` 进入生成的 C 头文件（实测消费方会看到 `JsonObjectOps` 等），导出面被污染。

消法（二选一）：

- **方案 A（推荐）**：删掉 `trait JsonValue` 与 7 个 ops 结构体，改成**单个函数按 `kind` 做 `switch` 分发**（Object / Array / String / Number / True / False / Null 七个分支），错误分支统一落到 `JSON_READ_KIND`。收益：77 个方法收敛成 7 个入口函数，桩全部消失，导出面自动干净。代价：`JsonValue` 这个公开类型消失，调用方由"接口值"改成直接传 `JsonView` + 函数族（它本来就只是 `{ops, vtable}` 的包装）。
- **方案 B**：保留接口形态，但改成**固有方法**（`JsonView` 上的 `kind()` / `count()` / `at()` …），不做 vtable，方法体内 `switch`。收益：调用点仍像方法；代价：`JsonView` 的体积与语义都要重新定义。

裁定：走方案 A。当前 7 个 ops 结构体只是空壳、不承载状态，保留接口形态没有额外价值，而方案 A 同时解决"桩"和"导出面污染"。工作量约 **250–320 行改动（净减 150 行左右）**，属于机械重构，golden 必须逐字节不变。

## 2 六项生产缺口：优先级与规模

| # | 缺口 | 现状证据 | 优先级 | 大致规模 |
| --- | --- | --- | --- | --- |
| 1 | 实数解码不保证正确舍入 | `as_double`（`json.ct:1284-1383`）取 19 位有效数字后逐次 ×/÷10；13 个样本 7 个 bit-exact，`0.30000000000000004` 读成 `0.3000000000000001` | **P0** | 120–200 行（精确十进制→double 的整数累积 + 舍入），golden 扩到 10⁶ 随机样本与 `strtod` 比对 |
| 2 | O(n²) 遍历 | `at()` / `member()` 每次重扫（`json.ct:997-1027`、`1084-1114`）；20k 数组全量遍历 1,240 ms | **P1** | 80–120 行（一次扫描把元素边界写进调用方提供的 `int` 缓冲，仍零 malloc），动 `JsonView` 与 `at`/`member`/`JsonIter` |
| 3 | 深度只有默认值、没有硬上限 | 默认 64（`json.ct:68`），`depth_limit` 可被调用方调高；110k 层 SIGSEGV | **P0** | 5–10 行（`depth_limit` 钳到硬上限，如 1024）+ 一条负例；改显式栈是大改，不做 |
| 4 | 输入 UTF-8 不校验 | `>= 0x80` 原样透传（`json.ct:209-211`），`0xFF 0xFE` 被接受 | **P0** | 60–90 行（`parse_strict` 开关 + UTF-8 校验器 + 新错误码），非 strict 行为保持不变 |
| 5 | writer 按 `strlen` 写，遇 `\u0000` 截断 | `as_string` 结果含 NUL 时写入器截断（`json.ct:817-831` 一带） | **P1** | 20–30 行（`string_len` / `key_len`，内部改成长度参数） |
| 6 | 输出截断静默，无错误码 | `cap=8` 请求 21 字节时 `finish()` 返回 21，缓冲只剩半截 JSON（`json.ct:852-866`） | **P1** | 15 行（新增 `JSON_EMIT_TRUNCATED` 与可判定的 `error()` 状态） |

顺序：先 3（最小、防崩）→ 4 → 1（P0 里最重）→ 2 → 5 → 6。每项单独提交、单独红证；P0 三项完成前不承诺 API 稳定。

## 3 包化拆分建议

目标结构（`docs/package-guide.md`：包根、`ct.pkg`、一单元一主类型、`pub` 才跨单元可见）：

```text
json/
├── ct.pkg
├── LICENSE
├── JsonDoc.h.ct      # 词法 + 校验 + 只读视图 + 错误定位（唯一 RFC 8259 词法实现）
├── JsonDoc.ct        # reader 实现
├── JsonOut.h.ct      # 追写器 + 转义 + 数值格式化
├── JsonOut.ct        # writer 实现
├── JsonValue.h.ct    # 分发（包内私有，不导出）
├── json_message.h.ct # 错误文案（唯一文案来源）
└── tests/            # 自测从 main 迁出，作为独立单元 + golden
```

四条硬要求：

1. **收敛导出面**：只 `pub` `JsonDoc` / `JsonView` / `JsonOut` / `parse_strict` 与 `json_message`；分发层保持包内私有（方案 A 之后天然满足）。
2. **公开布局里不许出现宏**：`JSON_OUT_DEPTH`（`json.ct:69`）现在用在导出结构体的字段宽度上（`json.ct:99-100`），而生成的头文件不带宏，消费方实测报 `use of undeclared identifier 'JSON_OUT_DEPTH'`。改成字段自己的固定长度，或把长度收进私有实现、公开面只暴露不透明状态。
3. **去掉 `static` 限制**：导出函数标 `pub`，内部辅助保持 `static`。当前几乎所有函数（含 `json_message`，`json.ct:1756`）都是 `static`，跨单元拿不到；拆单元后逐个决定可见性，并确认生成头只导出约定面。
4. **测试迁出 `main`**：断言现在绑在 `main` 与 golden 上（`json.ct:2275-2286`）。迁出 `examples/` 后本仓门禁不再覆盖它，包内必须有可运行的验收：`tests/` 单元 + 自己的 golden 比对脚本，并进包的 CI。

## 4 不做什么

- **不做可变 DOM**：建树 / 改节点 / 深拷贝用 cJSON（已定决策）。`json-dom` 若将来要做，是独立包、独立版本、依赖本包，不在本计划内。
- 不做流式/SAX：语义未定义（无回调契约、无错误恢复），cJSON 也没有；本期不主张。
- 不做 C ABI 导出：等 Phase 39 的 `ct build --lib`。

## 5 执行顺序

| 步 | 内容 | 交付判据 |
| --- | --- | --- |
| S0 | 单元拆分 + 导出面收敛 + 去宏 + 去 `static` + 测试迁出 | 消费方 `import` 可编可跑；生成头不含宏与 ops 结构体 |
| S1 | 深度硬上限（P0-3） | 任意 `depth_limit` 下 10⁶ 层不崩 |
| S2 | UTF-8 strict 开关（P0-4） | strict 拒非法 UTF-8；非 strict 行为不变 |
| S3 | 实数正确舍入（P0-1） | 10⁶ 随机 double 文本与 `strtod` 逐位相等 |
| S4 | 遍历索引（P1-2） | 20k 全量遍历 < 10 ms，内存仍由调用方持有 |
| S5 | `string_len`（P1-5） | 含 `\u0000` 的往返语义保持 |
| S6 | 截断错误码（P1-6） | 缓冲不足时返回可判定错误码 |
| S7 | fuzz + 基准进包 CI | 随机/变异输入零崩溃；基准可复现 |

每步独立提交、先红后绿；S0–S3 之间允许 API 破坏性变更（0.x），S4 起冻结对外签名。
