# 编辑器插件已迁出

VS Code 插件（语法高亮、snippets、跳转索引）已迁至独立仓库：

- 源码与问题：<https://github.com/samxxu/ct-vscode>
- 安装：在 VS Code 扩展市场搜索 `ct-vscode`

本目录不再保留插件代码。插件版本线与 `ct` 编译器版本线独立；语言新增关键字/模式时，在 `ct-vscode` 仓同步语法并跑它自己的 `npm test`。
