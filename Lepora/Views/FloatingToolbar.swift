import SwiftUI
import AppKit

/// Descriptor for a native macOS NSMenu item used in toolbar dropdowns.
struct ToolbarMenuEntry {
    enum Kind {
        case item(title: String, symbol: String, isChecked: Bool = false, action: @MainActor () -> Void)
        case separator
    }
    let kind: Kind

    static func item(
        _ title: String,
        symbol: String,
        isChecked: Bool = false,
        action: @escaping @MainActor () -> Void
    ) -> ToolbarMenuEntry {
        ToolbarMenuEntry(kind: .item(title: title, symbol: symbol, isChecked: isChecked, action: action))
    }

    static var separator: ToolbarMenuEntry {
        ToolbarMenuEntry(kind: .separator)
    }
}

/// Pure AppKit mouseDown menu trigger that pops a native macOS NSMenu cleanly below the button
/// without triggering SwiftUI Menu/NSPopUpButton layout shifts or Liquid Glass interactive bounce jitter.
private struct NativeMenuTrigger: NSViewRepresentable {
    let entriesProvider: @MainActor () -> [ToolbarMenuEntry]
    let alignRight: Bool
    let onMenuOpenChange: @MainActor (Bool) -> Void
    let onHoverChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> MenuTriggerNSView {
        let view = MenuTriggerNSView()
        view.entriesProvider = entriesProvider
        view.alignRight = alignRight
        view.onMenuOpenChange = onMenuOpenChange
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ nsView: MenuTriggerNSView, context: Context) {
        nsView.entriesProvider = entriesProvider
        nsView.alignRight = alignRight
        nsView.onMenuOpenChange = onMenuOpenChange
        nsView.onHoverChange = onHoverChange
    }

    final class MenuTriggerNSView: NSView {
        var entriesProvider: (@MainActor () -> [ToolbarMenuEntry])?
        var alignRight: Bool = false
        var onMenuOpenChange: (@MainActor (Bool) -> Void)?
        var onHoverChange: (@MainActor (Bool) -> Void)?

        private var trackingAreaRef: NSTrackingArea?
        private var actionClosures: [Int: @MainActor () -> Void] = [:]

        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingAreaRef {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingAreaRef = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChange?(false)
        }

        override func mouseDown(with event: NSEvent) {
            guard let entries = entriesProvider?() else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            actionClosures.removeAll()

            for (index, entry) in entries.enumerated() {
                switch entry.kind {
                case .separator:
                    menu.addItem(.separator())
                case .item(let title, let symbol, let isChecked, let action):
                    let item = NSMenuItem(title: title, action: #selector(handleMenuItem(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    item.state = isChecked ? .on : .off
                    if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
                        img.isTemplate = true
                        item.image = img
                    }
                    actionClosures[index] = action
                    menu.addItem(item)
                }
            }

            onMenuOpenChange?(true)
            let menuWidth = menu.size.width
            let anchorX: CGFloat = (alignRight && menuWidth > 0) ? (bounds.width - menuWidth) : 0
            let anchorPoint = NSPoint(x: anchorX, y: bounds.height + 6)
            menu.popUp(positioning: nil, at: anchorPoint, in: self)
            onMenuOpenChange?(false)
            onHoverChange?(false)
        }

        @objc private func handleMenuItem(_ sender: NSMenuItem) {
            actionClosures[sender.tag]?()
        }
    }
}

private struct ToolbarIconMenuButton: View {
    let systemImage: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let helpText: String
    let alignRight: Bool
    let entriesProvider: @MainActor () -> [ToolbarMenuEntry]
    let onMenuOpenChange: @MainActor (Bool) -> Void

    @State private var isLocalHover = false
    @State private var isMenuOpen = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(isMenuOpen ? 0.11 : (isLocalHover ? 0.07 : 0)))
                .frame(width: 24, height: 24)
                .animation(.easeOut(duration: 0.12), value: isLocalHover)
                .animation(.easeOut(duration: 0.12), value: isMenuOpen)

            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(isMenuOpen ? Color.primary : Color.primary.opacity(0.86))
                .allowsHitTesting(false)

            NativeMenuTrigger(
                entriesProvider: entriesProvider,
                alignRight: alignRight,
                onMenuOpenChange: { open in
                    isMenuOpen = open
                    onMenuOpenChange(open)
                },
                onHoverChange: { hovering in
                    isLocalHover = hovering
                }
            )
        }
        .frame(width: 28, height: 28)
        .help(helpText)
    }
}

private struct ToolbarIconActionButton: View {
    let systemImage: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let isActive: Bool
    let helpText: String
    let action: () -> Void

    @State private var isLocalHover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(0.15)
                            : Color.primary.opacity(isLocalHover ? 0.07 : 0)
                    )
                    .frame(width: 24, height: 24)
                    .animation(.easeOut(duration: 0.12), value: isLocalHover)

                Image(systemName: systemImage)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isLocalHover = $0 }
        .help(helpText)
    }
}

struct FloatingToolbar: View {
    @Bindable var session: DocumentSession
    @Bindable var settings: AppSettings

    @State private var isHovered: Bool = false
    @State private var isMenuActive: Bool = false

    private var effectiveOpacity: Double {
        if isHovered || isMenuActive || !session.isTypingMinimalMode {
            return 1.0
        }
        return 0.28
    }

    var body: some View {
        HStack(spacing: 8) {
            // Quick Insert menu pill
            ToolbarIconMenuButton(
                systemImage: "plus",
                fontSize: 13,
                fontWeight: .semibold,
                helpText: "插入图片 / 公式 / Mermaid / 表格",
                alignRight: false,
                entriesProvider: { insertMenuEntries },
                onMenuOpenChange: { isMenuActive = $0 }
            )
            .frame(width: 30, height: 30)
            .glassEffect(.regular, in: .capsule)

            // Core writing modes cluster
            HStack(spacing: 2) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        session.toggleEditorMode()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: session.editorMode.iconName)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(session.editorMode == .wysiwyg ? "阅读" : "源码")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .frame(width: 58, height: 28)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(session.editorMode == .source ? Color.accentColor : Color.primary)
                .help("切换阅读模式 / 源码模式 (⌘/)")

                Divider()
                    .frame(height: 14)
                    .opacity(0.35)

                ToolbarIconActionButton(
                    systemImage: "scope",
                    fontSize: 12.5,
                    fontWeight: .medium,
                    isActive: settings.focusMode,
                    helpText: "专注模式 (⇧⌘F)"
                ) {
                    withAnimation(.snappy(duration: 0.2)) {
                        settings.focusMode.toggle()
                    }
                    session.applySettings(settings)
                }

                ToolbarIconActionButton(
                    systemImage: "text.aligncenter",
                    fontSize: 12.5,
                    fontWeight: .medium,
                    isActive: settings.typewriterMode,
                    helpText: "打字机模式 (⇧⌘T)"
                ) {
                    withAnimation(.snappy(duration: 0.2)) {
                        settings.typewriterMode.toggle()
                    }
                    session.applySettings(settings)
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 30)
            .glassEffect(.regular, in: .capsule)

            // Export & Floating Outline toggle cluster
            HStack(spacing: 2) {
                ToolbarIconMenuButton(
                    systemImage: "square.and.arrow.up",
                    fontSize: 12.5,
                    fontWeight: .medium,
                    helpText: "导出与更多操作",
                    alignRight: true,
                    entriesProvider: { exportMenuEntries },
                    onMenuOpenChange: { isMenuActive = $0 }
                )

                ToolbarIconActionButton(
                    systemImage: "list.bullet.indent",
                    fontSize: 12.5,
                    fontWeight: .medium,
                    isActive: session.isOutlineVisible,
                    helpText: session.isOutlineVisible ? "收起右侧大纲 (⌥⌘O)" : "展开右侧大纲 (⌥⌘O)"
                ) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        session.isOutlineVisible.toggle()
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 30)
            .glassEffect(.regular, in: .capsule)
        }
        .opacity(effectiveOpacity)
        .animation(.easeInOut(duration: 0.2), value: effectiveOpacity)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var insertMenuEntries: [ToolbarMenuEntry] {
        [
            .item("插入图片…", symbol: "photo") { session.insertImagePanel() },
            .separator,
            .item("行内公式 ($…$)", symbol: "x.squareroot") { session.execCommand("inlineMath") },
            .item("块级公式 ($$…$$)", symbol: "function") { session.execCommand("displayMath") },
            .item("Mermaid 图表", symbol: "point.3.connected.trianglepath.dotted") { session.execCommand("mermaid") },
            .separator,
            .item("表格 (3×3)", symbol: "tablecells") { session.execCommand("table") },
            .item("代码块", symbol: "chevron.left.forwardslash.chevron.right") { session.execCommand("codeBlock", arg: "swift") },
            .item("任务清单", symbol: "checklist") { session.execCommand("taskList") },
            .item("提示标注 (Callout)", symbol: "lightbulb") { session.execCommand("callout", arg: "tip") },
        ]
    }

    private var exportMenuEntries: [ToolbarMenuEntry] {
        [
            .item("导出为 PDF…", symbol: "doc.richtext") { session.exportPDF() },
            .item("导出为独立 HTML…", symbol: "globe") { session.exportHTML() },
            .separator,
            .item("查找与替换 (⌘F)", symbol: "magnifyingglass") { session.openFindBar() },
            .item("快速跳转与命令 (⌘P)", symbol: "command") {
                withAnimation(.snappy(duration: 0.18)) {
                    session.isQuickOpenVisible = true
                }
            },
        ]
    }
}
