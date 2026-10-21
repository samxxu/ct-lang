# SH-12 · `map` 语法在 test/cases / examples 中无正例

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 测试覆盖） |
| 严重度 | **Medium** |
| 锚点 | commit `dde0dda`（2026-10-21） |
| 状态 | ✅ 已修复（2026-10-21，方案 A）：新增 `examples/08_map_binding/`（`map` + 实例级 vtable 派发，两个实例）；`test/run.sh` 支持首行 `//@ct-requires: ct-ast` 标记（L0 驱动器标 `skip`），实际由 `check-ast.sh` 的语料等价层编译比对；tutorial §9 已指向该例子。`test/cases` 仍不收录（同受 L0 驱动限制，且与 examples 重复） |

## 现象

Phase 11 声明 `map` 语法（`map trait T for instance x { m(params) -> CALL; }`）已完整实现并跨单元发射加固。
但整个测试套件中：

- **test/cases/（25 正例）**：**零** map 语法正例；grep `map trait .* for instance` 无命中。
- **examples/（7 正例）**：`07_dialect` 需要外部方言展开器先预处理，ct-ast 本身不能直接编译（报 `unexpected token (at 'ctrl')`）。其余 6 个例子均**不含** map 语法。
- **test/ast/（18 正例）**：仅 `13_map_instance`、`14_map_dispatch`、`15_map_args` 三个文件覆盖 map 语法。
- **test/ast/errors/（8 负例）**：全部是 map 语法的负例（`map_bad_arg.ct`、`map_dup.ct` 等）。
- **test/modules/（46+ .ct 文件）**：`map/`、`map_file/`、`map_file_build/` 覆盖 map 语法，但这是 Phase 11.2 之后的新增目录，check-ast.sh 之外的关卡不覆盖。

check-ast.sh 的 §5（metadata）覆盖 `--emit-map` 的 JSON 输出元数据（`test/ast/11_map` 其实**不含** map 语法——它测的是 trait + impl + 函数调用的元数据映射）；§3 的 `test/modules/map_unwritable` 钉住 build 模式发射；但**没有**单一入口能让新用户在 test/cases 或 examples 里看到 map 语法的**端到端正例**。

## 证据

```text
$ grep -rn 'map trait .* for instance' test/cases/ examples/  # 无命中
$ grep -rn 'map trait .* for instance' test/ast/               # 13_map_instance / 14_map_dispatch / 15_map_args
$ grep -rn 'map trait .* for instance' test/modules/           # map/、map_file/、map_file_build/
```

map 语法正确形态：

```c
// trait 定义
trait Controller { int send(char *buf, int len); }

// 普通 struct（不 use trait）
struct Uart { int fd; };

// 全局实例或局部变量
struct Uart uart1;

// 普通 C 函数签名里接收实例地址
static int mock_uart_send(struct Uart *u, char *buf, int len) { ... }

// map 语法：将 trait 方法绑定到普通函数调用
map trait Controller for instance uart1 {
    send(buf, len) -> mock_uart_send(&uart1, buf, len);
}

// 使用：装进 interface 值后派发
int main() {
    Controller c;       // 胖指针 { self, vt }
    c = uart1;          // 自动装箱
    c.send("x", 4);     // vptr 派发
}
```

## 影响

- Phase 11 已落地的 map 语法，新用户在 test/cases 或 examples 里**找不到端到端示例**（07_dialect 需要方言展开器）。
- map 正例集中在 test/ast/ 和 test/modules/，但这两个路径的文件不在 Phase 11 之前的"黄金"测试集中，文档里很少提到。
- tutorial.md（新用户第一入口）**未提及 map 语法**——章节 0–13 里没有任何 map 相关的段落或示例。

## 修复建议

1. 在 examples/ 新增 `08_map_binding/` 子目录，写一个独立、零依赖、ct-ast 可直接编译运行的 map 正例（`map trait Controller for instance uart1` + interface 值派发 + mock UART send），与 07_dialect 保持平级。
2. 在 test/cases/ 新增一个 map 正例（如 `30_map.ct`），钉住**单单元** map 行为（check-archive 的单单元关卡就能覆盖）。
3. 在 docs/tutorial.md 新增一个 §9「Map: 给普通 C 类型绑定 trait」，端到端示例 + 规范链接到 language-spec §4.10。
4. Phase 11 的 map 修复（build 模式发射、wrapper 生成）是在 2026-10-21 才落地的，例子应放在 examples/ 下作为"推荐用法"，避免 07_dialect 那样需要外部工具才能编的做法。

## 验证

- 新增正例：`ct` 零警告编过、生成物 `gcc -Wall -Wextra` 零告警、运行输出符合预期。
- `bash selfhost/check-all.sh` 八关全绿。
- tutorial.md 新增段落后，命令可直接粘贴执行（教程头部已声明）。
