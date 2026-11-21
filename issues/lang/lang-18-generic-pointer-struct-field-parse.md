# LANG-18 · 包发布工程中的编译回归：泛型指针结构体字段解析失败

| 项 | 值 |
| --- | --- |
| 模块 | lang（parser / 结构体字段解析） |
| 定性 | 编译回归：同一文件普通字段正常，泛型指针字段报字段名错误 |
| 严重度 | **High**（阻断真实工程编译） |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-22，REV：修复 `7b332432`（v0.61.1）+ `test/ast/286_generic_ptr_field` 在 HEAD `38cd4ae4` 复跑 rc=0；原拼写 `Map<Str,int>` 现按 J-4a 拒绝，改用 `Map<String,int>` 验证字段解析） |
| 锚点 | v0.60.0（`14a99b27`） |
| 实测版本 | v0.60.0 |
| 承诺出处 | [语言规范 §4.51](../../docs/language-spec.md)（泛型 struct 已落地；`Map<K,V>` 是泛型 struct） |

## CT 承诺了什么

语言规范 §4.51 写明泛型 struct 与内置 `Map<K,V>` 均已落地。泛型类型作为字段是既有形态；
指针字段（`T *name;`）也是既有 struct 语法。两者组合不应当被解析器拒绝。

## 现象

结构体字段声明为泛型指针时，编译器把类型后的字段名当成非法 token。在真实工程上使用时实测，
编译错误形如：

```console
$ ct build
<file>.ct:84: error: expected a field name
```

同一文件里的普通字段（非泛型、非指针）正常。`ct build` 与直接编译该单元同样失败。
疑似 0.58 到 0.60 之间引入的退化。

## 最小复现

```console
$ mkdir -p /tmp/lang18 && cd /tmp/lang18
$ cat > t.ct <<'EOF'
struct Doc {
    Map<Str, int> *index;
}
EOF
$ ct build t.ct
error: expected a field name
$ echo $?
1
```

对照：把字段换成 `Map<Str, int> index;`（值类型）或 `int *index;` 均可通过。

## 期望行为

`Map<Str, int> *index;` 作为结构体字段应被正常解析并生成对应 C 字段；不得要求加括号或改写成 typedef。
若语法上确实不支持泛型指针字段，应在 parse 阶段给出「不支持」的明确诊断，而不是 `expected a field name`。

## 影响

以泛型容器作为索引字段的类型无法编译，工程只能退化成 `void *` 或平行数组，破坏类型安全；
该写法在 0.58 之前可用，本次属回归。

## 关联

- [LANG-9](lang-9-struct-field-visibility-abi.md)：结构体字段的解析与发射。
- [LANG-17](lang-17-preprocessor-line-truncation.md)：同属「编译失败/静默改义」的回归族。

## 本仓评估（2026-11-16）

- **受理：是**
- **定性：实现缺陷（回归）**——泛型 struct 与指针字段都是既有能力，组合后编译失败。
- **依据：** 语言规范 §4.51（[language-spec.md](../../docs/language-spec.md)）写明泛型 struct
  与内置 `Map<K,V>` 已落地；struct 指针字段是既有语法。代码路径上，
  `Parser.h.ct:2039` 依赖 `parse_type` 把首 declarator 的 `*` 收进 `typebuf`，
  而 `:2074` 在 token 仍为 `*` 时报 `expected a field name`，说明泛型类型后的 `*` 未被收进。
- **优先级 / 落点：** P0；`v0.61.x` patch（回归不走 phase）。补 `Map<Str, int> *field;`
  与 `Vec<int> *field;` 两个夹具，并确认 0.58 的旧产物仍可编译。

## 处置（v0.61.1）

- 复核：当前 `HEAD` 已能编译 `Map<Str, int> *index;`，新增 `test/ast/286_generic_ptr_field` 固化；
- 提交 `7b332432`；`check-ast` 1451/0。

## 处置（REV/REQ，2026-11-22）

**结论：`verified`。** 修复提交 `7b332432`（`fix: process new toolchain and lang issues (v0.61.1)`）
已含 LANG-18 夹具，且是 HEAD `38cd4ae4` 的祖先。在干净归档 HEAD 重建 ct-ast v0.88.2 复跑：

```console
$ /tmp/ct-head-rev/.temp/b/ct-ast test/ast/286_generic_ptr_field/prog.ct -o /tmp/286.c
$ cc /tmp/286.c -o /tmp/286 && /tmp/286
1
$ echo $?
0
```

另写最小探针确认字段解析本身：

```ct
struct Doc {
    Map<String, int> *index;
    Vec<int> *v;
}
```

```console
$ ct-ast t2.ct -o t2.c ; echo $?
0
$ grep -n 'index\|v;' t2.c | head -2
58:    struct Map_String_int * index;
59:    struct Vec_int * v;
```

**口径说明**：原报告的 `Map<Str, int>` 现在会被 J-4a（`Map` 键必须是 owning `String`）拒绝，
报 `Map key type 'Str' is a borrowed view; use 'String' (owning)`；这是后续 phase 的独立语义收紧，
不是本条解析回归复现。用 `Map<String,int>` / `Vec<int>` 指针字段验证，解析与发射均正常。
`test/ast/286_generic_ptr_field` 即该回归的固化夹具。
