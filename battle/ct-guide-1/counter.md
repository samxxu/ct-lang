# battle/ct-guide-1 反对席（REQ）——边界反证

> 席位：REQ（指引作者侧）。只证伪主张席的“必须改/必须补”边界，不负责提替代方案。
> 立场：接受 F1 / F2 / F3 / F6 / F7 / F9 的事实；对 F4 / F5 / F8 提出反证条件，
> 反证失败即接受改写。所有探针在 `/tmp/ct-guide-probe/`，从仓库根执行以加载 `lib/std`。

## E1 复跑主张席证据（命令 + 原始输出）

```console
$ ct --version
ct v0.84.1

$ ct check --types /tmp/ct-guide-probe/retlocal2.ct ; echo exit=$?
exit=0                      # 返回局部 String 的 as_str，--types 也静默

$ ct build /tmp/ct-guide-probe/t2c.ct 2>&1 | tail -1
'cc' ... '.ctbuild/t2c.c' '-o' 'a.out'      # make_p().view() 可编译

$ ct build /tmp/ct-guide-probe/vpush.ct 2>&1 | tail -1
'cc' ... '.ctbuild/vpush.c' '-o' 'a.out'    # Vec<Str> + push(Str) 可编译

$ ct build /tmp/ct-guide-probe/fieldstr.ct 2>&1 | head -1
... error: a borrowed 'Str' view cannot be a struct field ...

$ ct build /tmp/ct-guide-probe/mapstr.ct 2>&1 | head -1
... error: Map key type 'Str' is a borrowed view; use 'String' (owning)

$ ct build --debug-leaks /tmp/ct-guide-probe/vstr.ct 2>&1 | head -1
ctc: unknown option '--debug-leaks'
```

结论：主张席关于 F4 / F5 / F8 的实测可复现；反对席的反证条件均未触发。

## E2 锚点（含不利于己方的一条）

- **不利于己方**：`docs/language-spec.md:3061` 明确“绑定是副本、owning 负载按 move；
  ADT 本身不自动释放 payload（本阶段不生成 drop glue）”——这直接支持 F9，反对席无法反驳。
- `docs/language-spec.md:2926` 只写“借用类型不能作为容器**键**”，未写 `Vec` 元素；
  支持 F8 的“原表述过宽”，但同时也提醒不能反向写成“所有容器都可以”。
- `docs/language-spec.md:2861` 写 `ref` 可被存储/传给更长寿命位置：F3 事实成立；
  反对席只能争取“保留教学建议语气”，不能保留“生命周期 = 本次调用”的断言。
- `test/ast/p79_places.sh:184` 的 `slice escape` 只覆盖 `T[]`；`Str` 逃逸没有对应 lint，
  这是 F4/F5 的关键锚点，也是本席最不利的一条。

## E3 可证伪预测

若出现下列任一情况，主张席的 F4/F5/F8 结论失效：

1. `ct check --types`、`ct build` 或某个门禁对 `make_p().view()` / 返回局部 `Str` 视图
   报 warning 或 error（本席已跑 `ct check` 与 `ct check --types`，均静默）；
2. `Vec<Str>` 元素或 `push(Str)` 在 v0.84.1 被拒绝（本席已复跑，均通过）；
3. spec 在 §4.70 新增“借用视图不得作容器元素”的硬性条款（当前 `docs/language-spec.md`
   §4.70 无此条）。

## E4 代价

- 接受改写：指引约 40–60 行；新增 ADT 一节；不动实现。
- 拒绝改写：读者会照 `"x".to_string()`、`slice(1, len-1)` 写出编译失败或语义错的代码；
  `Vec<Str>` 被误标为硬错，导致无谓的 `String` 深拷贝。
- 两条路都不增加运行期成本；改写只增加文档维护面。

## E5 对主张席最强论点的 steelman

主张席最强的一点是“教学简化不能与实现相反”。反对席的 steelman 是：
**心智模型允许比编译器更严格**——例如“临时量取视图应避免”作为纪律并没有错，
错在把它写成“编译错（lint 抓直接形态）”，让读者以为编译器兜底。因此本席接受：
保留“应避免”的教学建议，但把事实改为“当前可编译、无 lint”；这既保住作者原意，
也不欺骗读者。F5 的“单线程内 owning 不悬垂”同样可以保留为口诀，只需补上
“Str 视图逃逸与跨线程 refcount 不在编译期兜底”。

## 反证结果

- F4 / F5 / F8 的反证条件均未触发，接受主张席改写。
- 唯一保留意见：F4/F5 的措辞应保留“建议避免”的教学语气，而不是简单删掉整句；
  由裁判在定稿时统一口径。
