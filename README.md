# tern-zh-cn

Tern 终端的简体中文汉化插件。

[Tern](https://stencil.so/tern) 是 Stencil 的 Rust 原生终端，目前官方没有 i18n 框架。本插件用官方插件机制做"半汉化"：

- **中文命令面板**：以中文标题注册 50+ 个常用内置命令的包装，在命令面板（`Ctrl+Shift+P`）里直接打中文搜索，如"新建标签页""向右拆分""设置"。
- **静态文字替换**：用全局 CSS 把命令面板作用域页签（全部/命令/文件/会话/主机）和标签栏按钮文字换成中文。

![命令面板中的中文命令与作用域页签](docs/screenshot.png)

## 安装

```sh
tern plugin install github.com/maicent/tern-zh-cn
```

或在 Tern 的 Preferences › Plugins 里填同样的 GitHub 地址。

## 不能翻译的部分（原理限制）

- 内置命令的英文原行无法改名或隐藏（palette 行没有可选择器属性），但中文行排在同一列表里，搜索中文即可。
- 动态文本（toast 通知、错误消息、对话框内容、帮助文本）是运行时生成的字符串，插件没有文本拦截钩子。
- 工具提示（tooltip）文字来自 HTML `title` 属性，CSS 改不了。

## 实现方式

- `window.luau`：`tern.command` 注册中文包装命令，`run` 里调用对应内置命令（`cx:command(...)`），不改行为。
- `zh-cn.css`：`font-size: 0` 隐藏原文 + `::before { content: "中文" }` 注入翻译。Tern 的 CSS 引擎支持 `content` 与伪元素，详见 [Supported CSS](https://docs.stencil.so/tern/styles/css.html)。

## 维护说明

选择器基于 Tern 0.8.x 的内部 class（`tn-*`），升级 Tern 后若界面文字"复活"，需要对照新版本的 DOM 调整 `zh-cn.css`。排查工具：

```sh
tern serve --control /tmp/tern.sock   # headless 窗口
tern ctl --control /tmp/tern.sock tree    #  dump DOM
```

## License

MIT
