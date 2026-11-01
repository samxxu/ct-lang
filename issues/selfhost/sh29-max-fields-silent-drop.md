# SH-29 · 第 65 个字段被静默丢弃（`MAX_FIELDS` 越界不报错）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 记录解析） |
| 严重度 | Medium |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [frontend/parse/Parser.h.ct:1016-1023](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1016-L1023)（tag 行）、[:1031-1036](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1031-L1036)（`pend_fields`） |
| 状态 | 已修（2026-10-31）：`register_field` 两处越界改硬报错 `too many fields in a record`；门禁断言 `fields`（`check-ast.sh` 的 `cap_check`） |

## 现象

`register_field` 对每个具名字段都调用（`parse_record_body` 无条件登记，不按类型过滤），
但写入前只有 `if (nfields < MAX_FIELDS) { …; nfields++; }`，**没有 `else` 分支**：
第 65 个及以后的字段既不进表，也不报错，还跳过了重名检查（重名检查在容量判断之前，对已登记项仍然有效，
但对被丢弃的字段无从比较）。

`structs[].fields[]` 是 vptr 初始化、`offsetof`、trait 默认体字段校验的共同数据源
（`Init.h.ct` 的 `emit_field_vptrs` / `emit_array_field_vptrs`、`Emitter.h.ct` 的 `default_missing_field`）。
字段被丢掉后：

- 需要 vptr 的值字段 / 数组字段不会初始化 → 运行期空 vptr；
- trait 默认体引用它时被误判为 `no field 'x'` → 编译失败。

这违反仓库「容量上限一律报错、不静默截断」（AGENTS §3 / language-spec §2）的约定。

## 证据

64 个 `int` + 第 65 个 `Inner in;`（`Inner` 有 trait）：

```text
$ ./ct-ast big.ct -o big.c ; echo $?
0
$ grep -n 'struct Big b' big.c
98:    struct Big b;                                      # 没有 .in.__t_vptr 初始化
```

边界探针（每档只差一个 `int`）：

```text
n=63  → struct Big b = { .in.__t_vptr = &Inner_T_vtable };   # 64 个字段，正常
n=64  → struct Big b;                                       # 65 个字段，第 65 个被丢弃
```

## 建议

在容量判断处返回硬错误，例如 `return self->sup->fail("too many fields in a record")`（消息与既有
`too many …` 家族一致），并在 `check-ast.sh` 加一条生成式上限用例（现有 TEST-9 的五个上限用例不含 fields）；
若不愿提高上限，至少保证第 65 个字段报错而不是静默丢弃。
