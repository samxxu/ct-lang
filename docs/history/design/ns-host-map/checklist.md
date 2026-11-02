# 检查表：命名空间宿主 map（SH-20）

按 `spec.md` 的语义逐条核对；每项均以运行结果为准，不以读码代替。

- [x] `map trait T for namespace A::B { … }` 能编过，`for` 后其它写法报错。
- [x] 命名空间宿主的包装函数与 vtable 命名符合 `spec.md` §4：
      `hal` + `hal_Writer` → `hal_Writer_write` / `hal_Writer_vtable`（trait C 名已带前缀时不重复）。
- [x] `Trait::ns` 装箱发射 `(struct T_iface){ (void *)0, &T_vtable }`，运行时 `self` 为 NULL。
- [x] `Trait::ns(...)` 仍是限定调用，不产生装箱。
- [x] 命名空间宿主拒绝直绑：`a namespace host has no self: bind with a wrapper call`。
- [x] 非接口上下文使用宿主值报 `a namespace host value is only usable as an interface value`。
- [x] 找不到 map 报 `no map binds trait 'T' to namespace '<宿主路径>'`，位置在装箱处。
- [x] `pub` trait 时 vtable 跨单元导出：`.h` 出 `extern`、声明单元 `.c` 给定义。
- [x] `--emit-map` 的 maps 每条带 `"host": "instance"|"namespace"`，实例宿主路径行为不变。
- [x] 实例宿主（含直绑、限定实例、宏实参）行为无回归。
- [x] 生成物 `-Wall -Wextra -std=c99` 零告警。
- [x] `docs/language-spec.md` §4.10 中英对称更新，含两种宿主、NULL self、命名、导出、
      禁止直绑与三条诊断。
- [x] `issues/selfhost/ct-ast-map-requires-instance.md` 与 `issues/README.md` 处置行改为已修。
- [x] `bash selfhost/check-all.sh` 九关全绿；未 bump 版本、未改既有 golden。
