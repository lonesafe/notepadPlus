# Notepad++Mac 构建说明

此目录是 Notepad++ 原生 macOS 移植层，不替换现有的 Windows `PowerEditor` 构建。

## 已实现功能

- 原生 Cocoa `ScintillaView` 编辑器和 Universal 2 构建
- 接近原版的多文档标签页、文件状态图标、新建按钮、关闭按钮和拖动排序
- 文件打开、保存、另存为、重新载入、批量保存和批量关闭
- 会话恢复、崩溃恢复快照和外部文件变更检测
- 查找、替换、文件中查找、标记和正则表达式搜索
- Lexilla 语法高亮、Notepad++ `langs.model.xml` 语言映射和完整 UDL 词法分析器
- Markdown 实时预览
- JSON、JavaScript、HTML、Java、C/C++、C#、Go、Python 格式化
- 中文默认界面和可实时切换的英文 i18n
- 编码、换行符、书签、折叠、缩放、行操作和状态栏

## 构建

```bash
cd PowerEditor/macos
make app
```

构建过程会编译 Scintilla Cocoa 框架和 Lexilla 动态库，并生成：

```text
PowerEditor/macos/build/Notepad++Mac.app
```

运行：

```bash
make run
```

测试：

```bash
make test
```

## macOS 平台边界

Windows 插件 DLL、Explorer 外壳扩展、注册表、系统托盘和 Win32 停靠窗口无法直接在 macOS 中加载。相关能力必须使用 Cocoa 和 macOS 系统 API 单独实现。
