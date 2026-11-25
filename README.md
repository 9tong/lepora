# Lepora

极简、丝滑、原生 macOS 26/27 **Liquid Glass** Markdown 编辑器（Typora 原生替代方案）。

## 核心特性

- **原生 Swift 6 + macOS 26/27 Liquid Glass**：采用原生 SwiftUI / AppKit 与 `.glassEffect()` / `NSGlassEffectView` 液态玻璃界面；支持纯净浅色、深邃暗黑、暖意纸张、液态玻璃与跟随系统 5 套主题（位于顶部系统菜单 **视图 → 外观主题**）。
- **阅读模式 (WYSIWYG) 与源码模式无缝切换 (`⌘/`)**：
  - 实时支持 CommonMark + GFM 全套语法：1–6 级标题、粗斜体/删除线/高亮/下划线/上下标、精准对齐的任务清单、GitHub Callouts (`> [!TIP]` 等)、多语言代码高亮与一键复制、交互式表格（点击单元格浮现行列增删与对齐栏）。
  - 按 `⌘/` 毫秒级切换至 CodeMirror 6 源码模式，双向无损同步。
- **全量 LaTeX 数学公式渲染（离线 KaTeX + MathJax 3 SVG 自动兜底）**：
  - 全面支持 `$...$`、`\(...\)`、`$$...$$`、`\[...\]`、```` ```math ````、独立 AMS 环境（`\begin{equation/align/gather/multline/cases/eqnarray/pmatrix/...}`）及 `mhchem` 化学式 `\ce{...}`。
  - 点击任意公式原地展开编辑并实时预览，零网络依赖。
- **Mermaid 矢量图表实时渲染**：内置离线 Mermaid v11，随深浅色主题自动切换配色，点击展开源码编辑并防闪烁刷新。
- **图片插入与资产管理**：支持拖拽图片、`⌘V` 直接粘贴截图/剪贴板图片、`⇧⌘I` 选择文件；默认自动归档至同级 `<文档名>.assets/` 并写入相对路径（设置中可改），支持拖拽缩放宽度与在 Finder 中显示。
- **高效多文档与极简工作流**：
  - 顶部自适应 Liquid Glass 多文档标签栏（`⌘N` / `⌘W` / `⇧⌘[` / `⇧⌘]`）+ 左侧独立悬浮文件栏（支持全文+文件名实时搜索、同时打开文件与文件夹）+ 右侧轻透悬浮大纲（`⌥⌘O` 默认展开、可随时收起）。
  - 专注模式 (`⇧⌘F`)、打字机居中模式 (`⇧⌘T`)、快速跳转面板 (`⌘P` / `⌘K`)、查找替换 (`⌘F`)、一键导出 PDF 与离线独立 HTML（完整内嵌字体、公式、图表与图片）。

## 安装

前往本仓库的 **Releases** 页面下载最新 `Lepora-1.0.0-arm64.dmg`，双击挂载后将 `Lepora.app` 拖入 `Applications` 即可使用（适用于 Apple Silicon + macOS 26.0+）。

> 首次打开如遇 macOS 提示未公证的开发者应用，右键点击 `Lepora.app` 选择「打开」或在「系统设置 → 隐私与安全性」中允许即可。

## 从源码构建

```bash
# 编译 Release 版本原生应用 (build/Release/Lepora.app)
make build

# 打包 DMG 安装镜像 (build/Lepora-1.0.0-arm64.dmg)
make dmg

# 直接编译并安装到 /Applications/Lepora.app
make install

# 生成 Xcode 工程用于调试
make xcode
```
