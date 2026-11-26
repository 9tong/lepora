import SwiftUI
import AppKit

@MainActor
final class LeporaAppDelegate: NSObject, NSApplicationDelegate {
    var pendingURLs: [URL] = []
    var onOpenURLs: (([URL]) -> Void)?
    var hasUnsavedDocuments: (() -> [DocumentTab])?

    func application(_ application: NSApplication, open urls: [URL]) {
        if let handler = onOpenURLs {
            handler(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirtyTabs = hasUnsavedDocuments?() ?? []
        guard !dirtyTabs.isEmpty else { return .terminateNow }

        let names = dirtyTabs.prefix(3).map(\.title).joined(separator: "、")
        let suffix = dirtyTabs.count > 3 ? " 等 \(dirtyTabs.count) 篇文档" : ""
        let alert = NSAlert()
        alert.messageText = "仍有未保存的文档"
        alert.informativeText = "“\(names)”\(suffix)尚未保存，确定要退出 Lepora 吗？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消退出")
        alert.addButton(withTitle: "直接退出")

        let res = alert.runModal()
        return res == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

@main
struct LeporaApp: App {
    @NSApplicationDelegateAdaptor(LeporaAppDelegate.self) private var appDelegate
    @State private var session = DocumentSession()
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            MainWorkspaceView(session: session, settings: settings)
                .frame(minWidth: 780, minHeight: 540)
                .onAppear {
                    configureWindowAppearance()
                    Self.syncAppearance(for: settings.theme)
                    Self.syncDockIcon(for: settings.theme)
                    appDelegate.hasUnsavedDocuments = {
                        session.tabs.filter(\.isDirty)
                    }
                    appDelegate.onOpenURLs = { urls in
                        for url in urls {
                            session.openURL(url)
                        }
                    }
                    if !appDelegate.pendingURLs.isEmpty {
                        let urls = appDelegate.pendingURLs
                        appDelegate.pendingURLs.removeAll()
                        for url in urls {
                            session.openURL(url)
                        }
                    }
                    // Silently warm up reusable NSOpenPanel right after first paint
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(700))
                        session.prewarmOpenPanelIfNeeded()
                    }
                }
        }
        .handlesExternalEvents(matching: ["*"])
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("新建文档") {
                    session.createNewDocument()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("打开文件或文件夹…") {
                    session.openFilePanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("打开工作区文件夹…") {
                    session.openFolderPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("保存") {
                    session.saveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("另存为…") {
                    session.saveDocumentAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("关闭标签页") {
                    session.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("上一个标签页") {
                    session.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("下一个标签页") {
                    session.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Divider()

                Button("导出为 PDF…") {
                    session.exportPDF()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("导出为独立 HTML…") {
                    session.exportHTML()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift, .option])

                Divider()

                Button("打开功能示例指南") {
                    session.openWelcomeShowcase()
                }
            }

            // Find & Quick Open in Edit menu
            CommandGroup(after: .textEditing) {
                Divider()
                Button("查找与替换") {
                    session.openFindBar()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("快速跳转与命令面板") {
                    withAnimation(.snappy(duration: 0.18)) {
                        session.isQuickOpenVisible.toggle()
                    }
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("命令面板") {
                    withAnimation(.snappy(duration: 0.18)) {
                        session.isQuickOpenVisible.toggle()
                    }
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            // Format & Paragraph menu (Typora shortcuts)
            CommandMenu("格式") {
                Button("一级标题") { session.execCommand("h1") }
                    .keyboardShortcut("1", modifiers: .command)
                Button("二级标题") { session.execCommand("h2") }
                    .keyboardShortcut("2", modifiers: .command)
                Button("三级标题") { session.execCommand("h3") }
                    .keyboardShortcut("3", modifiers: .command)
                Button("四级标题") { session.execCommand("h4") }
                    .keyboardShortcut("4", modifiers: .command)
                Button("正文段落") { session.execCommand("paragraph") }
                    .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("加粗") { session.execCommand("bold") }
                    .keyboardShortcut("b", modifiers: .command)
                Button("斜体") { session.execCommand("italic") }
                    .keyboardShortcut("i", modifiers: .command)
                Button("下划线") { session.execCommand("underline") }
                    .keyboardShortcut("u", modifiers: .command)
                Button("删除线") { session.execCommand("strike") }
                    .keyboardShortcut("x", modifiers: [.control, .shift])
                Button("高亮标记") { session.execCommand("highlight") }
                Button("行内代码") { session.execCommand("inlineCode") }
                    .keyboardShortcut("`", modifiers: .control)

                Divider()

                Button("插入图片…") { session.insertImagePanel() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("插入行内公式 ($…$)") { session.execCommand("inlineMath") }
                Button("插入块级公式 ($$…$$)") { session.execCommand("displayMath") }
                    .keyboardShortcut("b", modifiers: [.command, .option])
                Button("插入 Mermaid 图表") { session.execCommand("mermaid") }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Button("插入表格") { session.execCommand("table") }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Button("插入代码块") { session.execCommand("codeBlock", arg: "swift") }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("引用块") { session.execCommand("blockquote") }
                    .keyboardShortcut("q", modifiers: [.command, .option])
                Button("任务清单") { session.execCommand("taskList") }
                Button("分割线") { session.execCommand("hr") }
            }

            // View menu
            CommandMenu("视图") {
                Button(session.isSidebarVisible ? "收起左侧边栏" : "展开左侧边栏") {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        session.isSidebarVisible.toggle()
                    }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button(session.isOutlineVisible ? "收起右侧大纲" : "展开右侧大纲") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        session.isOutlineVisible.toggle()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .option])

                Button(session.editorMode == .wysiwyg ? "切换到源码模式" : "切换到阅读模式") {
                    withAnimation(.snappy(duration: 0.2)) {
                        session.toggleEditorMode()
                    }
                }
                .keyboardShortcut("/", modifiers: .command)

                Divider()

                Menu("外观主题") {
                    ForEach(EditorTheme.allCases) { theme in
                        Button {
                            settings.theme = theme
                            Self.syncAppearance(for: theme)
                            session.applySettings(settings)
                            Self.syncDockIcon(for: theme)
                        } label: {
                            HStack {
                                Text(theme.displayName)
                                if settings.theme == theme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Toggle("专注模式", isOn: $settings.focusMode)
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                Toggle("打字机模式", isOn: $settings.typewriterMode)
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("增大字号") {
                    settings.fontSize = min(24, settings.fontSize + 1)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("减小字号") {
                    settings.fontSize = max(12, settings.fontSize - 1)
                }
                .keyboardShortcut("-", modifiers: .command)
            }
        }

        Settings {
            SettingsView(settings: settings)
        }
    }

    /// Synchronizes AppKit window/app appearance directly instead of relying on SwiftUI's
    /// `.preferredColorScheme(nil)`, which fails to reset `NSWindow.appearance` back to system on macOS.
    static func syncAppearance(for theme: EditorTheme) {
        let target: NSAppearance? = {
            switch theme {
            case .system, .translucent:
                return nil
            case .light, .paper:
                return NSAppearance(named: .aqua)
            case .dark:
                return NSAppearance(named: .darkAqua)
            }
        }()
        NSApplication.shared.appearance = target
        for window in NSApplication.shared.windows {
            window.appearance = nil
        }
    }

    static func syncDockIcon(for theme: EditorTheme) {
        switch theme {
        case .system, .translucent:
            // Let macOS 26/27 natively render our Liquid Glass Assets.car icon (auto Light / Dark / Clear)
            NSApplication.shared.applicationIconImage = nil
        case .light, .paper:
            if let url = Bundle.main.url(forResource: "DockIconLight", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = img
            }
        case .dark:
            if let url = Bundle.main.url(forResource: "DockIconDark", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = img
            }
        }
    }

    private func configureWindowAppearance() {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                if window.toolbar == nil {
                    window.toolbar = NSToolbar(identifier: "LeporaUnifiedToolbar")
                }
                window.toolbarStyle = .unified
                window.titlebarSeparatorStyle = .none
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = false
                window.backgroundColor = .clear
                window.isOpaque = false
            }
        }
    }
}
