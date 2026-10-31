# 任务：`.h.ct` 规则落地（第三十批）

依据：`docs/design/batch30-header-rule/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析侧

- `Module.h.ct`：`resolve_import` 两遍搜索（先所有根的 `.h.ct`，再所有根的 `.ct` 用于具名诊断）。
- 具名诊断：`only a .h.ct unit can be imported: rename 'x.ct' to 'x.h.ct'`。

## [x] T2 发射 / 缓存 / 编译模式

- `Module.h.ct`：只有 `is_hdr` 单元写头；`write_header` 按输入路径后缀判断。
- `Emit.h.ct`：实现单元不包含自己的头；`pub` 类型在实现单元的 `.c` 里发射。
- `Cache.h.ct`：`hit(outc, key, need_h)`，实现单元不要求 `.h`。

## [x] T3 迁移与 fixture

- 被导入单元改名：ct-ast 3 个、`bindings/mock-hal/uart`、`test/modules/**` 27 个。
- `hdr` / `hdr_prologue` 入口改 `main.h.ct`；`ns_dir/build.args`、`hdr/build.args` 同步。
- L2 designed goldens：8 个改名单元的 `*.expected.{c,h}` 只按路径变化重生成。

## [x] T4 关卡与文档

- `check-ast.sh`：split 产物断言、路径更新、corpus「无 `.h`」、compile 契约两条、负例。
- `check-warnings.sh` / `ct-tour.sh` / `test/pkg/run.sh` 适配。
- `docs/roadmap.md` 文件命名表落地说明、`docs/language-spec.md` 分叉表、
  tutorial / bindings README / selfhost README 的路径。
- `bash selfhost/check-all.sh` → 九关全绿。
- 提交拆分：`feat(build): only a .h.ct unit publishes a header`、
  `docs(spec): record the .h.ct rule`。不 bump 版本。
