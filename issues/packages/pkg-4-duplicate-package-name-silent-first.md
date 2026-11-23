# PKG-4 · 依赖图内同名包静默取首个，无警告无错误

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct get` / `ct update` 依赖解析） |
| 定性 | **Bug**（静默给出错误的包内容） |
| 严重度 | High |
| 锚点 | 工作树 `89b1124b`（`ct v0.53.0` 二进制实测） |
| 文件 | [Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct)（`get_one` / `fetch_git` 的 `seen[]` 只按 name 去重） |
| 状态 | verified |
| 处置证据 | **已修**（v0-PH-54 S2：SP-006/013；`Pkg.h.ct:2284-2291`、`:2872-2877` 报 `is required twice`） |

## 现象

`ct.pkg` 声明两个同名的包（不同目录或不同发布方），解析只取第一个，第二个被静默丢弃；版本范围一致时 `ct update` / `ct install` 都返回 0，构建用的是第一个包的内容。

## 最小复现

```sh
mkdir -p /tmp/p4/pubX/alpha /tmp/p4/pubY/alpha /tmp/p4/proj
printf 'name = alpha\nversion = 0.1.0\n' >/tmp/p4/pubX/alpha/ct.pkg
printf 'namespace alpha;\n\npub int which(void) { return 111; }\n' >/tmp/p4/pubX/alpha/Alpha.h.ct
printf 'name = alpha\nversion = 0.1.0\n' >/tmp/p4/pubY/alpha/ct.pkg
printf 'namespace alpha;\n\npub int which(void) { return 222; }\n' >/tmp/p4/pubY/alpha/Alpha.h.ct
printf 'name = demo\nversion = 0.1.0\ndep = ../pubX/alpha@^0.1.0\ndep = ../pubY/alpha@^0.1.0\n' >/tmp/p4/proj/ct.pkg
printf 'import alpha::Alpha;\nint main(void){ return 0; }\n' >/tmp/p4/proj/main.ct
cd /tmp/p4/proj && ct update && cat ct.lock && cat vendor/alpha/Alpha.h.ct && ct install; echo "rc=$?"
```

实际输出：

```text
updated 1 package(s)
alpha 0.1.0 dir ./../pubX/alpha sha256:55afb36…
pub int which(void) { return 111; }        # pubY 被丢弃
ct build -I vendor/alpha main.ct -o build
rc=0
```

版本范围不同时只有间接报错（`dependency '../pubY/alpha@^0.9.0' is not satisfied by ct.lock`），文案不指出「同名冲突」。

## 期望行为

- 依赖图内同名包（无论发布方）直接硬错：`ctc: package 'alpha' is required twice: <a> and <b>`。
- 裸名在索引中对应多个发布方时硬错：`ctc: 'alpha' is ambiguous; write <publisher>/<name>`。
- 判定见 [SP-013](../../docs/planning/ct-pkg-shared-store-requirements.md)。

## 交叉引用

- 提案 [§6](../../docs/proposals/ct-pkg-shared-store.md)、[§12 D3](../../docs/proposals/ct-pkg-shared-store.md)
- 需求 SP-013 / SP-014
- [PKG-5](pkg-5-cache-key-bare-name.md)（同名串用的另一半原因）

## 修复排期

S2（编译读 lock）：`seen[]` 改为按 `(publisher, name)` 记录，并在解析期做 name 唯一性检查。
