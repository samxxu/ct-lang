# DOC-55 · `package-guide.md` 对 `ct verify` 与「唯一子进程」的两处失实

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `553d300`（2026-11-02，工作树 `v0.18.0`） |
| 文件 | [docs/package-guide.md](../../docs/package-guide.md#L76) L76 / L81（英文 L173 / L178） |
| 状态 | 已修（2026-11-02，`v0.18.0`）：L76/L173 改为「`ct verify` 只校验摘要，依赖覆盖由 `ct install` 判定」；L81/L178 限定「`ct get` 是包管理路径里唯一的子进程调用点」，并注明 `ct build` 默认经 `$CC` 派生子进程 |

## 现象

作者指南的「正确用法」一节给出两条与实现不符的断言：

```text
L76:   ct verify                    # 离线：校验 vendor/ 与 ct.lock 的摘要与依赖覆盖
L81:   `ct get` 可用 git（唯一的子进程调用点）；`ct update` / `ct verify` / `ct install` 零网络、
       零子进程。编译器本身（`ct compile` / `ct build --emit-c`）零网络。
```

## 证据

**一、「依赖覆盖」不在 `ct verify` 里。**

[`pkg_verify`](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1748-L1758) 只做摘要校验：

```ct
/* `ct verify`: the offline half of install -- no manifest, no command. */
static int pkg_verify(const char *prog)
{
    ...
    if (pkg_verify_lock(prog, lname, lver, &nlock) != 0) return 1;
    printf("verified %d package(s)\n", nlock);
    return 0;
}
```

清单依赖与 `ct.lock` 的覆盖比对只在 `install` 里做（[Pkg.h.ct:1241-1255](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1241-L1255)）：

```ct
for (i = 0; i < ndeps; i++) {
    ...
    if (!seen) {
        fprintf(stderr, "ctc: dependency '%s' is not satisfied by ct.lock\n", pdeps[i]);
        rc = 1;
    }
}
```

测试面也印证这一点：`test/pkg/run.sh` 的 verify 用例只覆盖摘要篡改（[run.sh:599-615](../../test/pkg/run.sh#L599-L615)），
没有「`ct.pkg` 声明了 `dep` 但 `ct.lock` 缺失」的 verify 负例。

**二、「`ct get` 是唯一子进程调用点」不成立。**

`ct build` 的默认路径（未给 `--emit-c`）会经 `system()` 调 `$CC`：

```ct
/* frontend/module/Module.h.ct:1078-1080 */
ccpath = self->cc;
if (!ccpath) ccpath = getenv("CC");
if (!ccpath || !*ccpath) ccpath = "cc";
```

Phase 17 的文档（D17-9）已按「`ct compile` / `ct build --emit-c` 零子进程，`ct build` 默认代为编译」
表述；本指南的绝对化措辞与它冲突。

## 影响

- 作者会把 `ct verify` 当成「依赖齐全性检查」，漏订 `dep` 直到 `ct install` 才失败；
- 「唯一子进程」是对外契约式陈述，安全/嵌入场景会据此判断工具链行为，写反了会误导审计。

## 修复建议

1. L76 / L173 改为：`ct verify` 只校验 `vendor/` 与 `ct.lock` 的摘要；**依赖覆盖由 `ct install` 校验**
   （或若决定让 verify 也校验依赖，那是一次行为变更，应单独走决策，不在文档里先写）。
2. L81 / L178 限定主语：`ct get` 是**包管理路径**里唯一的子进程调用点；编译器侧 `ct compile` /
   `ct build --emit-c` 零子进程，`ct build` 默认经 `$CC` 派生子进程。

## 验证

`ct verify` 在「`ct.pkg` 多出一条未锁定的 `dep`」的项目上仍打印 `verified N package(s)` 并退出 0；
`ct build` 在 `PATH` 里放一个只会写标记的假 `cc`，可观察到 `system()` 调用。
