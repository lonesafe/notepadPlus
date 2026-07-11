# Notepad++Mac

Notepad++Mac 是基于 Notepad++、Scintilla 和 Lexilla 构建的原生 macOS 文本与代码编辑器。该项目保留 Notepad++ 的多标签页、查找替换、语法高亮和常用编辑工作流，同时使用 Cocoa 重建 macOS 界面和平台功能。

## 主要功能

- 原生 Cocoa 与 Scintilla 编辑器，支持 Apple Silicon 和 Intel Mac
- 接近 Notepad++ 原版的多标签页界面，支持新建、关闭、拖动排序和溢出滚动
- 新建、打开、保存、另存为、保存全部、重新载入和外部文件变更检测
- 会话恢复和未保存文档的崩溃恢复快照
- 完整的查找、替换、文件中查找和标记面板
- 普通、扩展和正则表达式搜索，支持捕获组替换
- 基于 Lexilla 的语法高亮和 Notepad++ UDL 词法分析器
- Markdown 语法高亮与 WebKit 实时预览，快捷键 `⌘⇧M`
- JSON、JavaScript、HTML、Java、C、C++、C#、Go、Python 一键格式化，快捷键 `⌘⌥L`
- 行操作、注释、书签、代码折叠、缩放、编码和换行符转换
- 默认简体中文，可在偏好设置中实时切换英文
- Universal 2 应用，同时包含 `arm64` 和 `x86_64`

## 系统要求

- macOS 10.13 或更高版本
- 从源码构建需要完整安装的 Xcode 和 Xcode Command Line Tools

## 下载

可从 [Releases](https://github.com/lonesafe/notepadPlus/releases/latest) 下载最新的 ZIP 或 DMG。

当前发布包使用 GitHub Actions 自动构建并进行临时签名。它尚未使用 Apple Developer ID 公证；首次打开时如被 Gatekeeper 阻止，可在 Finder 中右键应用并选择“打开”。

## 本地构建

```bash
git clone https://github.com/lonesafe/notepadPlus.git
cd notepadPlus/PowerEditor/macos
make app
```

构建结果位于：

```text
PowerEditor/macos/build/Notepad++Mac.app
```

运行应用：

```bash
make run
```

运行全部单元测试和集成测试：

```bash
make test
```

## 自动构建与发布

仓库中的 [macos-release.yml](.github/workflows/macos-release.yml) 提供以下流程：

- 推送到 `main` 或 `master`：构建、测试并上传 Actions Artifact
- Pull Request：验证 Universal 2 构建和测试
- 推送 `v*` 标签：自动创建 GitHub Release，并上传 ZIP、DMG 和 SHA-256 校验文件
- 手动运行：可在 Actions 页面触发构建，也可填写版本标签创建 Release

创建正式版本示例：

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 项目结构

```text
PowerEditor/macos/                  macOS 应用、资源和测试
PowerEditor/macos/src/              Cocoa/Objective-C++ 实现
PowerEditor/macos/Resources/        Info.plist 与中英文资源
PowerEditor/macos/tests/            单元测试和集成测试
scintilla/cocoa/                    Scintilla Cocoa 框架
lexilla/                            语法高亮词法分析器
```

## 平台差异

Windows 版 Notepad++ 插件使用 PE DLL、Win32 窗口句柄和 Windows 消息，无法直接加载到 macOS 进程。Explorer 外壳扩展、注册表设置、系统托盘和 Win32 停靠面板同样需要使用 macOS API 重新实现。

## 许可证与上游项目

本项目遵循 [GNU GPL v3](LICENSE)。

- Notepad++：[notepad-plus-plus/notepad-plus-plus](https://github.com/notepad-plus-plus/notepad-plus-plus)
- Scintilla：[scintilla.org](https://www.scintilla.org/)
- Lexilla：[scintilla.org/Lexilla.html](https://www.scintilla.org/Lexilla.html)

感谢 Notepad++、Scintilla、Lexilla 及所有贡献者。
