# LANG-18 · 包发布工程中的编译回归：泛型指针结构体字段解析失败

| 项 | 值 |
| --- | --- |
| 模块 | lang（parser / 结构体字段解析） |
| 定性 | 编译回归：同一文件普通字段正常，泛型指针字段报字段名错误 |
| 严重度 | **High**（阻断真实工程编译） |
| 状态 | open |
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
