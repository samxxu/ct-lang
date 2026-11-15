# SH-79 · `build --lib --emit-map` 静默成功但不写 JSON

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（build 驱动 / 选项分派） |
| 严重度 | **Medium**（工具输出静默丢失，CI 无法发现） |
| 优先级 | **P2** —— 不挡编译，但让「构建产物可审计」的承诺落空 |
| 状态 | open |
| 锚点 | `v0.53.1`（`55d89e2b`）；实测 `ct-ast v0.53.1`（HEAD 重建） |
| 类型 | **实现缺陷**（同一条 usage 里宣称的开关不生效） |

## 现象

`--emit-map` 在 compile 模式会写出 JSON；在 `build --lib` 下命令 rc=0，但目标文件不存在，
也没有任何 warning。

## 最小复现

```sh
mkdir -p lib && cat > lib/lib.h.ct <<'EOF'
namespace lib;
pub struct Box { int n; }
pub int box_get(struct Box *b) { return b->n; }
EOF
CT_STD_DIR=<repo>/lib/std ct build --lib --emit-map map.json -I . lib/lib.h.ct -o out
echo "rc=$?"; ls -l map.json
```

### 实际输出

```text
rc=0
ls: map.json: No such file or directory
```

compile 模式同参数正常：

```console
$ ct one.ct --emit-map cmap.json -o one.c
$ ls -l cmap.json
-rw-r--r--  1558 cmap.json
```

## 定性

**bug（A）**：usage 的 `build` 行明确列出 `[--emit-map <file|->]`
（[Driver.h.ct:242](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L242)），实现只在 compile 分支消费；
build 分支既不写文件也不报「不支持」，属静默丢失输出。

## 修复落点

- `tool/driver/Driver.h.ct`：把 `--emit-map` 的解析结果传给 build 驱动（不要只留在 compile 路径）；
- `frontend/module/Module.h.ct`：在 `--lib` 收口时按同一张映射表写 JSON（与 compile 同一序列化，
  避免两份格式）；
- 若不打算支持，则改为显式硬错 `--emit-map is not supported with --lib`，不能静默成功。

## 回归判据

| ID | 断言 |
| --- | --- |
| R1 | `build --lib --emit-map map.json` rc=0 且 `map.json` 存在、可被 `json.load` 解析 |
| R2 | map 的键集合与 compile 模式同一程序一致（同一编译器版本） |
| R3 | 不带 `--emit-map` 时行为零变化（不产生文件） |
| R4 | 若走「显式不支持」分支：rc=1，诊断含 `--emit-map`，且不写文件 |

## 文件族

`Driver` / `Module` 与 LANG-11、SH-76 同族，**必须串行发版**；根因不同，**不合并**。
