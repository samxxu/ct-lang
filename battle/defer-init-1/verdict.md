# battle/defer-init-1 判决

> **状态：`closed`**（2026-11-18；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **结论：B 胜。拒绝 `T *s = defer expr`；保留块级 `defer`。创建+清理用 `own`（有 Drop）或现有尾随块。若确需更短拼写，另立关键字/限定符，不复用 `defer`。**

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 语义清晰 | **B 胜** | `defer` 的既有语义是“延迟执行”；`defer expr` 变成“立即构造 + 延迟清理”，方向反转。语法位置可区分，但语义直觉不可接受。 |
| J-2 与 own/尾随块重叠 | **B 胜** | A 声称“非 Drop/标量指针只有 A”，被证伪：`int *p = malloc(...) defer { delete p; }` 与 Drop 版生成的 C 正是 A 的释放形状；A 只增加第三种拼写，不增加表达能力。 |
| J-3 语法歧义 | **A=fail** | 今天合法的 `struct Some *s = defer;`、`= defer(7)`（同名函数/前向声明）、`= defer + 1`、`int defer; int y = defer + 1;` 都会被 A 的“其后不是 `{`”规则误捕获；仅靠符号表无法在解析期消歧。 |
| J-4 控制流/错误路径 | **B 胜（A 未闭环）** | 尾随块四条出口 + `return err:`/`break err:` + 零值守卫实测正确；A 的逃逸/重赋值诊断需改 `Memory.h.ct`，且“只收 malloc/工厂”白名单不能保证 `free` 安全（返回 `&static` 的工厂仍会被接受）。 |
| J-5 兼容性 | **B 胜** | A 会改判今天合法的程序；`.h.ct` 还有既有矛盾（规范说块级 defer 可用，`parse_trailing_defer` 仍报错）。B 零 golden 变化。 |
| J-6 实现代价 | **B 胜** | B 0 行；A parser 80–100 + Mem/诊断 + 测试，且遗漏逃逸/`.h.ct` 两处；emitter 0 不等于总成本低。 |

## 2 采纳

1. **`defer` 只保留块形态**：`defer { … }`；`defer expr` 仍是普通标识符/语法错误。
2. **Drop 类型**：
   ```ct
   own Some *s = Some::new();
   ```
3. **无 Drop / 标量指针**：
   ```ct
   Some *s = Some::new() defer { delete s; };
   ```
   这是现有尾随块，不是新语法；四条出口、零值守卫、LIFO 已成立。
4. **要更短拼写**：另立 `owned`/`with`/`using` 这类明确关键字，语义写死“立即构造 + 退出释放”，不要复用 `defer`。
5. **文档**：把上面两种写法写进语言指南/示例，减少“必须加新语法”的需求。

## 3 不采纳

- `T *s = defer expr`：语义反转、语法歧义、与 own/尾随块重叠。
- 把 `defer` 当“延迟创建”：`s` 在作用域内不可用，语义无意义。
- 用 `defer` 自动猜 `delete/free`：Drop/非 Drop/静态/工厂返回 `&static` 的安全边界无法统一。
- 在 A 下改判 `defer` 标识符/函数名：破坏 C 超集兼容。

## 4 证据限制

- A 的“纯 desugar、emitter 0”成立，但 parser/诊断/兼容成本被低估；现有 defer/own/尾随块夹具全绿。
- `.h.ct` 尾随块拒绝是既有实现漂移，和本 battle 无关；另立 issue，不借 A 修。
- 未实现 A，因此“A 的逃逸/重赋值诊断”只有设计，没有运行证据。

## 5 下一步

- 不新增 `defer expr`；补文档示例：`own` 与尾随块。
- 若用户坚持更短拼写，另开提案评估 `owned T *s = expr;`（语义只做“构造 + 退出释放”）。
- 迁移/phase 编号工作不受本判决影响。
