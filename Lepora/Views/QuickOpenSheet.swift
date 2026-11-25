import SwiftUI

private struct QuickEntry: Identifiable {
    enum Kind {
        case file(URL)
        case heading(OutlineItem)
        case command(String, () -> Void)
    }

    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let kind: Kind
}

struct QuickOpenSheet: View {
    @Bindable var session: DocumentSession
    @Bindable var settings: AppSettings

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isFieldFocused: Bool

    private var entries: [QuickEntry] {
        var all: [QuickEntry] = []

        // 0. Open tabs
        if session.tabs.count > 1 {
            for tab in session.tabs where tab.id != session.activeTabID {
                all.append(
                    QuickEntry(
                        id: "tab-\(tab.id.uuidString)",
                        title: tab.title,
                        subtitle: tab.isDirty ? "已打开标签页 · 未保存" : "已打开标签页",
                        icon: "doc.on.doc",
                        kind: .command(tab.title, { session.selectTab(tab.id) })
                    )
                )
            }
        }

        // 1. Headings in current document
        for h in session.outline {
            all.append(
                QuickEntry(
                    id: "heading-\(h.id)",
                    title: h.text,
                    subtitle: "H\(h.level) · 当前文档大纲",
                    icon: "number",
                    kind: .heading(h)
                )
            )
        }

        // 2. Files in workspace
        let files = FileTreeNode.flattenMarkdownFiles(from: session.fileTree)
        for f in files {
            all.append(
                QuickEntry(
                    id: "file-\(f.url.path)",
                    title: f.name,
                    subtitle: f.url.deletingLastPathComponent().lastPathComponent,
                    icon: "doc.text",
                    kind: .file(f.url)
                )
            )
        }

        // 3. Built-in quick commands
        let commands: [(String, String, String, () -> Void)] = [
            ("切换阅读模式 / 源码模式", "⌘/", "chevron.left.forwardslash.chevron.right", { session.toggleEditorMode() }),
            ("切换专注模式 (Focus Mode)", "⇧⌘F", "scope", {
                settings.focusMode.toggle()
                session.applySettings(settings)
            }),
            ("切换打字机模式 (Typewriter Mode)", "⇧⌘T", "text.aligncenter", {
                settings.typewriterMode.toggle()
                session.applySettings(settings)
            }),
            ("插入块级 LaTeX 公式 ($$…$$)", "⌥⌘B", "function", { session.execCommand("displayMath") }),
            ("插入行内 LaTeX 公式 ($…$)", "KaTeX / MathJax", "x.squareroot", { session.execCommand("inlineMath") }),
            ("插入 Mermaid 流程图", "⌥⌘M", "point.3.connected.trianglepath.dotted", { session.execCommand("mermaid") }),
            ("插入 GFM 表格 (3×3)", "⌥⌘T", "tablecells", { session.execCommand("table") }),
            ("插入图片…", "⇧⌘I", "photo", { session.insertImagePanel() }),
            ("导出为 PDF…", "⇧⌘E", "doc.richtext", { session.exportPDF() }),
            ("导出为独立 HTML…", "⌥⇧⌘E", "globe", { session.exportHTML() }),
            ("切换液态玻璃画布主题", "Liquid Glass", "sparkles", {
                settings.theme = (settings.theme == .translucent) ? .system : .translucent
                session.applySettings(settings)
            }),
        ]

        for (idx, cmd) in commands.enumerated() {
            all.append(
                QuickEntry(
                    id: "cmd-\(idx)",
                    title: cmd.0,
                    subtitle: cmd.1,
                    icon: cmd.2,
                    kind: .command(cmd.0, cmd.3)
                )
            )
        }

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Array(all.prefix(14))
        }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("搜索文件、大纲标题或快捷命令…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFieldFocused)
                    .onSubmit {
                        runSelected()
                    }
                    .onChange(of: query) {
                        selectedIndex = 0
                    }
                Text("ESC")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().opacity(0.35)

            if entries.isEmpty {
                Text("没有找到匹配项")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                            Button {
                                selectedIndex = index
                                runSelected()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 13))
                                        .foregroundStyle(index == selectedIndex ? Color.accentColor : .secondary)
                                        .frame(width: 20)
                                    Text(item.title)
                                        .font(.system(size: 13, weight: index == selectedIndex ? .semibold : .regular))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(item.subtitle)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    if index == selectedIndex {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.14))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 330)
            }
        }
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 32, y: 14)
        .onAppear {
            selectedIndex = 0
            isFieldFocused = true
        }
        .onKeyPress(.upArrow) {
            if !entries.isEmpty {
                selectedIndex = (selectedIndex - 1 + entries.count) % entries.count
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !entries.isEmpty {
                selectedIndex = (selectedIndex + 1) % entries.count
            }
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private func runSelected() {
        guard entries.indices.contains(selectedIndex) else { return }
        let entry = entries[selectedIndex]
        dismiss()
        switch entry.kind {
        case .file(let url):
            session.openFile(url)
        case .heading(let item):
            session.jumpToOutlineItem(item)
        case .command(_, let action):
            action()
        }
    }

    private func dismiss() {
        withAnimation(.snappy(duration: 0.18)) {
            session.isQuickOpenVisible = false
        }
    }
}
