import SwiftUI
import AppKit

private struct UnifiedRecentEntry: Identifiable {
    enum Source {
        case openTab(DocumentTab)
        case recentFile(URL)
    }

    let id: String
    let title: String
    let url: URL?
    let isActive: Bool
    let isDirty: Bool
    let source: Source
}

private struct SidebarSnippet: Identifiable, Sendable {
    let id: Int
    let text: String
    let occurrenceIndex: Int
}

private struct SidebarSearchHit: Identifiable, Sendable {
    let id: String
    let title: String
    let tabID: UUID?
    let url: URL?
    let snippets: [SidebarSnippet]
    let matchCount: Int
    let titleMatched: Bool
}

struct LiquidGlassSidebar: View {
    @Bindable var session: DocumentSession
    var isFullScreen: Bool = false

    @State private var searchText: String = ""
    @State private var searchHits: [SidebarSearchHit] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @State private var isCreatingFile: Bool = false
    @State private var newFileName: String = ""
    @State private var hoveredEntryID: String?

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Unified, deduplicated list combining currently open documents and recently opened files.
    private var unifiedRecentEntries: [UnifiedRecentEntry] {
        var entries: [UnifiedRecentEntry] = []
        var seenPaths = Set<String>()

        for tab in session.tabs {
            let path = tab.fileURL?.standardizedFileURL.path
            if let path { seenPaths.insert(path) }
            entries.append(
                UnifiedRecentEntry(
                    id: "tab-\(tab.id.uuidString)",
                    title: tab.title,
                    url: tab.fileURL,
                    isActive: tab.id == session.activeTabID,
                    isDirty: tab.isDirty,
                    source: .openTab(tab)
                )
            )
        }

        for url in session.recentFiles {
            let std = url.standardizedFileURL
            if seenPaths.contains(std.path) { continue }
            seenPaths.insert(std.path)
            entries.append(
                UnifiedRecentEntry(
                    id: "recent-\(std.path)",
                    title: std.deletingPathExtension().lastPathComponent,
                    url: std,
                    isActive: false,
                    isDirty: false,
                    source: .recentFile(std)
                )
            )
        }

        return Array(entries.prefix(12))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top header strip: clears traffic lights in windowed mode; shows subtle title in fullscreen
            HStack {
                if isFullScreen {
                    Text("Lepora")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 14)
                }
                Spacer()
            }
            .frame(height: 44)

            // Search box + quick Open / New icons
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    TextField("搜索…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onChange(of: searchText) {
                            scheduleSearch(query: searchText)
                        }
                        .onSubmit {
                            if let first = searchHits.first {
                                session.openSearchMatch(tabID: first.tabID, url: first.url, query: searchText)
                            }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchHits = []
                            session.bridgeController?.clearFind()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Button {
                    session.openFilePanel()
                } label: {
                    OpenFolderIcon()
                        .frame(width: 14.5, height: 12.5)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开文件或文件夹 (⌘O)")

                Button {
                    session.createNewDocument()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("新建文档 (⌘N)")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()
                .opacity(0.35)

            // Search results or normal file list
            if isSearchActive {
                searchResultsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                filesContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 244)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 6)
        .alert("新建 Markdown 笔记", isPresented: $isCreatingFile) {
            TextField("文件名（例如 notes.md）", text: $newFileName)
            Button("取消", role: .cancel) { newFileName = "" }
            Button("创建") {
                session.createNewMarkdownFileInWorkspace(named: newFileName)
                newFileName = ""
            }
        }
    }

    // MARK: - Search Execution (Filename + Full-Text Content)

    private func scheduleSearch(query rawQuery: String) {
        searchTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchHits = []
            isSearching = false
            return
        }

        // Snapshot candidates on MainActor before scanning off the main thread
        let openTabsSnapshot: [(id: UUID, title: String, url: URL?, text: String)] = session.tabs.map { tab in
            let liveText = (tab.id == session.activeTabID) ? session.markdown : tab.markdown
            return (tab.id, tab.title, tab.fileURL?.standardizedFileURL, liveText)
        }
        let openPaths = Set(openTabsSnapshot.compactMap { $0.url?.path })

        var diskURLs: [URL] = []
        var seenDisk = openPaths

        for url in session.recentFiles {
            let std = url.standardizedFileURL
            if !seenDisk.contains(std.path) {
                seenDisk.insert(std.path)
                diskURLs.append(std)
            }
        }
        for node in FileTreeNode.flattenMarkdownFiles(from: session.fileTree) {
            let std = node.url.standardizedFileURL
            if !seenDisk.contains(std.path) {
                seenDisk.insert(std.path)
                diskURLs.append(std)
            }
        }

        let diskURLsSnapshot = diskURLs
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }

            let results = await Task.detached(priority: .userInitiated) {
                var hits: [SidebarSearchHit] = []

                // 1. Search open documents (always includes unsaved edits)
                for tab in openTabsSnapshot {
                    if Task.isCancelled { return hits }
                    if let hit = Self.matchDocument(
                        id: "tab-\(tab.id.uuidString)",
                        title: tab.title,
                        tabID: tab.id,
                        url: tab.url,
                        content: tab.text,
                        query: query
                    ) {
                        hits.append(hit)
                    }
                }

                // 2. Search recent & workspace files on disk
                for url in diskURLsSnapshot {
                    if Task.isCancelled { return hits }
                    let title = url.deletingPathExtension().lastPathComponent
                    let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    if let hit = Self.matchDocument(
                        id: "file-\(url.path)",
                        title: title,
                        tabID: nil,
                        url: url,
                        content: content,
                        query: query
                    ) {
                        hits.append(hit)
                    }
                }

                // Rank title matches first, then higher match count
                hits.sort { a, b in
                    if a.titleMatched != b.titleMatched { return a.titleMatched }
                    return a.matchCount > b.matchCount
                }
                return hits
            }.value

            guard !Task.isCancelled else { return }
            searchHits = results
            isSearching = false
        }
    }

    nonisolated private static func matchDocument(
        id: String,
        title: String,
        tabID: UUID?,
        url: URL?,
        content: String,
        query: String
    ) -> SidebarSearchHit? {
        let titleMatched = title.localizedCaseInsensitiveContains(query)
        var matchCount = 0
        var snippets: [SidebarSnippet] = []

        var searchRange = content.startIndex..<content.endIndex
        while let found = content.range(of: query, options: [.caseInsensitive], range: searchRange) {
            if snippets.count < 3 {
                let text = extractSnippet(in: content, matchRange: found)
                if !text.isEmpty {
                    snippets.append(SidebarSnippet(id: matchCount, text: text, occurrenceIndex: matchCount))
                }
            }
            matchCount += 1
            if matchCount >= 99 { break }
            searchRange = found.upperBound..<content.endIndex
        }

        guard titleMatched || matchCount > 0 else { return nil }
        return SidebarSearchHit(
            id: id,
            title: title,
            tabID: tabID,
            url: url,
            snippets: snippets,
            matchCount: matchCount,
            titleMatched: titleMatched
        )
    }

    nonisolated private static func extractSnippet(in text: String, matchRange: Range<String.Index>) -> String {
        let lineRange = text.lineRange(for: matchRange)
        let line = text[lineRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[#*_`>]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if line.count <= 68 {
            return line
        }
        let start = text.index(matchRange.lowerBound, offsetBy: -18, limitedBy: lineRange.lowerBound) ?? lineRange.lowerBound
        let end = text.index(matchRange.upperBound, offsetBy: 42, limitedBy: lineRange.upperBound) ?? lineRange.upperBound
        let prefix = start > lineRange.lowerBound ? "…" : ""
        let suffix = end < lineRange.upperBound ? "…" : ""
        return prefix + text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines) + suffix
    }

    // MARK: - Search Results View

    @ViewBuilder
    private var searchResultsContent: some View {
        if searchHits.isEmpty && !isSearching {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("未找到匹配文档")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(searchHits) { hit in
                        VStack(alignment: .leading, spacing: 2) {
                            Button {
                                session.openSearchMatch(tabID: hit.tabID, url: hit.url, query: searchText, occurrenceIndex: 0)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: hit.tabID != nil ? "doc.text.fill" : "doc.text")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color.accentColor.opacity(0.85))
                                    Text(highlightedText(hit.title, query: searchText))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    if hit.matchCount > 0 {
                                        Text("\(hit.matchCount)")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.primary.opacity(0.06), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background {
                                    if hoveredEntryID == hit.id {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.primary.opacity(0.06))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredEntryID = hovering ? hit.id : (hoveredEntryID == hit.id ? nil : hoveredEntryID)
                            }

                            ForEach(hit.snippets) { snippet in
                                let snipID = "\(hit.id)-s-\(snippet.id)"
                                Button {
                                    session.openSearchMatch(
                                        tabID: hit.tabID,
                                        url: hit.url,
                                        query: searchText,
                                        occurrenceIndex: snippet.occurrenceIndex
                                    )
                                } label: {
                                    Text(highlightedText(snippet.text, query: searchText))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 22)
                                        .padding(.trailing, 8)
                                        .padding(.vertical, 3.5)
                                        .background {
                                            if hoveredEntryID == snipID {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color.primary.opacity(0.05))
                                            }
                                        }
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    hoveredEntryID = hovering ? snipID : (hoveredEntryID == snipID ? nil : hoveredEntryID)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }

    private func highlightedText(_ source: String, query: String) -> AttributedString {
        var attr = AttributedString(source)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return attr }

        var searchStart = attr.startIndex
        while searchStart < attr.endIndex,
              let range = attr[searchStart..<attr.endIndex].range(of: trimmed, options: [.caseInsensitive]) {
            attr[range].foregroundColor = .accentColor
            attr[range].font = .system(size: 11.5, weight: .semibold)
            searchStart = range.upperBound
        }
        return attr
    }

    // MARK: - Normal Files List

    @ViewBuilder
    private var filesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 1. Clean unified document list (no header bar)
                if !unifiedRecentEntries.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 1.5) {
                        ForEach(unifiedRecentEntries) { entry in
                            recentEntryRow(entry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }

                // 2. Folder Tree — ONLY shown when the user explicitly opened a folder
                if let ws = session.workspaceURL {
                    Divider()
                        .opacity(0.28)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)

                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(ws.lastPathComponent)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            isCreatingFile = true
                        } label: {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 11.5))
                        }
                        .buttonStyle(.plain)
                        .help("在文件夹中新建 .md 文件")

                        Button {
                            session.refreshFileTree()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .help("刷新目录")

                        Button {
                            session.closeWorkspace()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("关闭文件夹视图")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)

                    LazyVStack(alignment: .leading, spacing: 2) {
                        if session.fileTree.isEmpty {
                            Text("该目录暂无 Markdown 文件")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(session.fileTree) { node in
                                FileTreeRow(node: node, depth: 0, session: session)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func recentEntryRow(_ entry: UnifiedRecentEntry) -> some View {
        let isHovered = (hoveredEntryID == entry.id)

        HStack(spacing: 6) {
            if entry.isDirty {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            } else {
                Image(systemName: entry.url == nil ? "doc" : "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.isActive ? Color.accentColor : Color.secondary)
            }

            Text(entry.title)
                .font(.system(size: 12.2, weight: entry.isActive ? .semibold : .regular))
                .foregroundStyle(entry.isActive ? Color.primary : Color.primary.opacity(0.82))
                .lineLimit(1)

            Spacer(minLength: 4)

            if case .openTab(let tab) = entry.source, (isHovered || entry.isActive) {
                Button {
                    session.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Color.primary.opacity(isHovered ? 0.08 : 0), in: Circle())
                }
                .buttonStyle(.plain)
                .help("关闭标签页 (⌘W)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if entry.isActive {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            switch entry.source {
            case .openTab(let tab):
                session.selectTab(tab.id)
            case .recentFile(let url):
                session.openFile(url)
            }
        }
        .onHover { hovering in
            hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
        }
        .contextMenu {
            if case .openTab(let tab) = entry.source {
                Button("关闭标签页") {
                    session.closeTab(tab.id)
                }
            }
            if let url = entry.url {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
}

private struct OpenFolderIcon: View {
    var body: some View {
        OpenFolderShape()
            .stroke(
                Color.secondary,
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
            )
    }
}

private struct OpenFolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        // Back folder outline with top-left tab
        path.move(to: CGPoint(x: w * 0.08, y: h * 0.85))
        path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.22))
        path.addQuadCurve(to: CGPoint(x: w * 0.17, y: h * 0.12), control: CGPoint(x: w * 0.08, y: h * 0.12))
        path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.12))
        path.addLine(to: CGPoint(x: w * 0.49, y: h * 0.26))
        path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.26))
        path.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.35), control: CGPoint(x: w * 0.88, y: h * 0.26))
        path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.44))

        // Open angled front flap
        path.move(to: CGPoint(x: w * 0.08, y: h * 0.85))
        path.addLine(to: CGPoint(x: w * 0.21, y: h * 0.48))
        path.addQuadCurve(to: CGPoint(x: w * 0.29, y: h * 0.43), control: CGPoint(x: w * 0.22, y: h * 0.43))
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.43))
        path.addQuadCurve(to: CGPoint(x: w * 0.95, y: h * 0.51), control: CGPoint(x: w * 0.97, y: h * 0.43))
        path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.84))
        path.addQuadCurve(to: CGPoint(x: w * 0.76, y: h * 0.90), control: CGPoint(x: w * 0.82, y: h * 0.90))
        path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.90))
        path.addQuadCurve(to: CGPoint(x: w * 0.08, y: h * 0.85), control: CGPoint(x: w * 0.08, y: h * 0.90))

        return path
    }
}

private struct FileTreeRow: View {
    let node: FileTreeNode
    let depth: Int
    let session: DocumentSession
    @State private var isExpanded: Bool = true

    var body: some View {
        if node.isDirectory {
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text(node.name)
                            .font(.system(size: 12.2, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.88))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 12 + 6)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded, let children = node.children {
                    ForEach(children) { child in
                        FileTreeRow(node: child, depth: depth + 1, session: session)
                    }
                }
            }
        } else {
            let isSelected = session.fileURL?.standardizedFileURL == node.url.standardizedFileURL
            Button {
                session.openFile(node.url)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(node.name)
                        .font(.system(size: 12.2, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.82))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.leading, CGFloat(depth) * 12 + 18)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                }
                Button("复制路径") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.url.path, forType: .string)
                }
            }
        }
    }
}
