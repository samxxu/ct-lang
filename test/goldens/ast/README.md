# ct-ast 静态 golden（SH-105 / gate 12）

本目录是 `ct-ast` 发射器的**静态期望**，每个 `test/cases/*.ct` 对应一份 `<case>.c`。
它不是 L1 的 `.expected.c`：两代发射器在注释丢弃、`const` vtable、指针空格、
前向声明与原型位置上不同（见 [goldens-l1-vs-ast.md](../../../docs/planning/j6-evidence/goldens-l1-vs-ast.md)）。
本门禁不读 `selfhost/l1` / `selfhost/l2`，L1/L2 退役后仍可独立运行。

## 生成

从仓库根执行，`<ct-ast>` 必须是本次收口的二进制（`ct-ast -v` 可查版本）：

```sh
for f in test/cases/*.ct; do
    b=$(basename "$f" .ct)
    CT_STD_DIR=$PWD/lib/std <ct-ast> "$f" -o "test/goldens/ast/$b.c"
done
```

生成版本：`ct-ast 0.88.3`（`v0.88.3`）。banner 含版本号，门禁比对时两侧都做
`s/v[0-9]+\.[0-9]+\.[0-9]+/vX/g` 归一化；golden 本身保留生成时的版本，不手工改写。

## 校验

```sh
bash selfhost/check-goldens-ast.sh /path/to/ct-ast
bash test/goldens/selftest-goldens-ast.sh /path/to/ct-ast   # 负例
```

判据：25/25 字节一致（banner 归一化后）；缺失 / 多出 golden、编译失败、字节不符均退出 1。
