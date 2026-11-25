import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers

struct DocumentTab: Identifiable, Equatable {
    let id: UUID
    var fileURL: URL?
    var markdown: String
    var isDirty: Bool
    var editorMode: EditorMode
    var outline: [OutlineItem]
    var activeHeadingId: String
    var stats: DocumentStats
    var untitledNumber: Int
    var isWelcomePlaceholder: Bool

    var title: String {
        if let url = fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        if isWelcomePlaceholder {
            return "欢迎指南"
        }
        return untitledNumber <= 1 ? "未命名文档" : "未命名文档 \(untitledNumber)"
    }
}

/// Precomputed native UTType allowlist evaluated inside macOS's panel service (zero XPC delegate callbacks).
private enum MarkdownContentTypes {
    static let all: [UTType] = {
        let candidates: [UTType?] = [
            UTType("net.daringfireball.markdown"),
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "mdown"),
            UTType(filenameExtension: "mkd"),
            UTType(filenameExtension: "mdx"),
            UTType(filenameExtension: "rmd"),
            UTType(filenameExtension: "qmd"),
            .plainText,
            .utf8PlainText,
            .text,
        ]
        var seen = Set<String>()
        var result: [UTType] = []
        for t in candidates.compactMap({ $0 }) {
            if seen.insert(t.identifier).inserted {
                result.append(t)
            }
        }
        return result
    }()
}

@Observable
@MainActor
final class DocumentSession {
    // Multi-tab document state
    var tabs: [DocumentTab] = []
    var activeTabID: UUID

    // Active tab mirrored properties (for reactive UI)
    var fileURL: URL?
    var workspaceURL: URL?
    var fileTree: [FileTreeNode] = []
    var markdown: String = DocumentSession.welcomeMarkdown
    var isDirty: Bool = false
    var editorMode: EditorMode = .wysiwyg
    var outline: [OutlineItem] = []
    var activeHeadingId: String = ""
    var stats: DocumentStats = DocumentStats()

    // UI state
    var isSidebarVisible: Bool = true
    var isOutlineVisible: Bool = true
    var isFindBarVisible: Bool = false
    var isQuickOpenVisible: Bool = false
    var isTypingMinimalMode: Bool = false
    var toastMessage: String?

    // Find & Replace state
    var findQuery: String = ""
    var replaceQuery: String = ""
    var findCaseSensitive: Bool = false
    var findCurrentIndex: Int = 0
    var findTotalCount: Int = 0

    // Recent files
    var recentFiles: [URL] = []

    // Connected WebView bridge controller
    weak var bridgeController: EditorBridgeController?

    private let watcher = FileWatcher()
    private var reusableOpenPanel: NSOpenPanel?
    private var autoSaveTask: Task<Void, Never>?
    private var fileTreeScanTask: Task<Void, Never>?
    private var typingIdleTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var lastDiskSaveDate: Date = .distantPast
    private var nextUntitledCounter: Int = 1

    private let recentFilesKey = "lepora.recentFiles"

    init() {
        let initialTab = DocumentTab(
            id: UUID(),
            fileURL: nil,
            markdown: Self.welcomeMarkdown,
            isDirty: false,
            editorMode: .wysiwyg,
            outline: [],
            activeHeadingId: "",
            stats: DocumentStats(),
            untitledNumber: 0,
            isWelcomePlaceholder: true
        )
        self.tabs = [initialTab]
        self.activeTabID = initialTab.id
        self.markdown = initialTab.markdown
        loadRecentFiles()
    }

    var activeTabIndex: Int? {
        tabs.firstIndex(where: { $0.id == activeTabID })
    }

    var displayTitle: String {
        if let idx = activeTabIndex {
            return tabs[idx].title
        }
        return fileURL?.deletingPathExtension().lastPathComponent ?? "未命名文档"
    }

    var baseDirectoryPath: String {
        fileURL?.deletingLastPathComponent().path
            ?? workspaceURL?.path
            ?? ImageAssetManager.draftAssetsDirectory().path
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.25)) {
            toastMessage = message
        }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.toastMessage = nil
            }
        }
    }

    func registerTypingActivity() {
        if !isTypingMinimalMode {
            withAnimation(.easeOut(duration: 0.3)) {
                isTypingMinimalMode = true
            }
        }
        typingIdleTask?.cancel()
        typingIdleTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                self.isTypingMinimalMode = false
            }
        }
    }

    func handleEditorContentChanged(_ newMarkdown: String) {
        markdown = newMarkdown
        isDirty = true
        syncActiveTabSnapshot()

        if AppSettings.shared.autoSave, fileURL != nil {
            autoSaveTask?.cancel()
            autoSaveTask = Task {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                self.saveDocument(silent: true)
            }
        }
    }

    private func syncActiveTabSnapshot() {
        guard let idx = activeTabIndex else { return }
        tabs[idx].fileURL = fileURL
        tabs[idx].markdown = markdown
        tabs[idx].isDirty = isDirty
        tabs[idx].editorMode = editorMode
        tabs[idx].outline = outline
        tabs[idx].activeHeadingId = activeHeadingId
        tabs[idx].stats = stats
        if isDirty {
            tabs[idx].isWelcomePlaceholder = false
        }
    }

    private func flushActiveTabFromEditor() async {
        if let latest = await bridgeController?.fetchMarkdown() {
            markdown = latest
        }
        syncActiveTabSnapshot()
    }

    // MARK: - Tab Management

    func selectTab(_ tabID: UUID) {
        guard tabID != activeTabID,
              tabs.contains(where: { $0.id == tabID }) else { return }

        Task {
            autoSaveTask?.cancel()
            await flushActiveTabFromEditor()
            activateTab(tabID)
        }
    }

    func selectNextTab() {
        guard tabs.count > 1, let idx = activeTabIndex else { return }
        let next = tabs[(idx + 1) % tabs.count]
        selectTab(next.id)
    }

    func selectPreviousTab() {
        guard tabs.count > 1, let idx = activeTabIndex else { return }
        let prev = tabs[(idx - 1 + tabs.count) % tabs.count]
        selectTab(prev.id)
    }

    func closeTab(_ tabID: UUID) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }

        Task {
            if tabID == activeTabID {
                await flushActiveTabFromEditor()
            }
            guard let freshIdx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
            let target = tabs[freshIdx]

            if target.isDirty {
                let alert = NSAlert()
                alert.messageText = "是否保存对“\(target.title)”的更改？"
                alert.informativeText = "如果不保存，您所做的更改将会丢失。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "保存")
                alert.addButton(withTitle: "不保存")
                alert.addButton(withTitle: "取消")

                let response = alert.runModal()
                if response == .alertThirdButtonReturn {
                    return
                } else if response == .alertFirstButtonReturn {
                    let saved = await saveTabSynchronously(tabID: tabID)
                    if !saved { return }
                }
            }

            removeTabWithoutPrompt(tabID)
        }
    }

    func closeActiveTab() {
        closeTab(activeTabID)
    }

    private func removeTabWithoutPrompt(_ tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let wasActive = (tabID == activeTabID)
        tabs.remove(at: idx)

        if tabs.isEmpty {
            let fresh = makeNewUntitledTab()
            tabs = [fresh]
            activateTab(fresh.id)
        } else if wasActive {
            let nextIndex = min(idx, tabs.count - 1)
            activateTab(tabs[nextIndex].id)
        }
    }

    private func activateTab(_ tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        autoSaveTask?.cancel()
        watcher.stop()

        activeTabID = tab.id
        fileURL = tab.fileURL
        markdown = tab.markdown
        isDirty = tab.isDirty
        editorMode = tab.editorMode
        outline = tab.outline
        activeHeadingId = tab.activeHeadingId
        stats = tab.stats

        bridgeController?.loadDocument(markdown: tab.markdown, baseDirPath: baseDirectoryPath)
        bridgeController?.setMode(tab.editorMode)

        if let url = tab.fileURL {
            startWatching(url)
        }
    }

    private func makeNewUntitledTab() -> DocumentTab {
        let num = nextUntitledCounter
        nextUntitledCounter += 1
        return DocumentTab(
            id: UUID(),
            fileURL: nil,
            markdown: "",
            isDirty: false,
            editorMode: .wysiwyg,
            outline: [],
            activeHeadingId: "",
            stats: DocumentStats(),
            untitledNumber: num,
            isWelcomePlaceholder: false
        )
    }

    // MARK: - Document Lifecycle

    func createNewDocument() {
        Task {
            autoSaveTask?.cancel()
            await flushActiveTabFromEditor()
            let newTab = makeNewUntitledTab()
            withAnimation(.snappy(duration: 0.2)) {
                tabs.append(newTab)
            }
            activateTab(newTab.id)
        }
    }

    func openWelcomeShowcase() {
        Task {
            await flushActiveTabFromEditor()
            if let existing = tabs.first(where: { $0.isWelcomePlaceholder }) {
                activateTab(existing.id)
                return
            }
            let tab = DocumentTab(
                id: UUID(),
                fileURL: nil,
                markdown: Self.welcomeMarkdown,
                isDirty: false,
                editorMode: .wysiwyg,
                outline: [],
                activeHeadingId: "",
                stats: DocumentStats(),
                untitledNumber: 0,
                isWelcomePlaceholder: true
            )
            withAnimation(.snappy(duration: 0.2)) {
                tabs.append(tab)
            }
            activateTab(tab.id)
        }
    }

    /// Pre-warms a single reusable NSOpenPanel instance once after app launch so clicking
    /// the Open button responds in ~10ms instead of stalling on macOS's 1.5–6s cold panel init.
    func prewarmOpenPanelIfNeeded() {
        guard reusableOpenPanel == nil else { return }
        let panel = NSOpenPanel()
        panel.treatsFilePackagesAsDirectories = false
        reusableOpenPanel = panel
    }

    private func obtainOpenPanel() -> NSOpenPanel {
        if let existing = reusableOpenPanel {
            return existing
        }
        let panel = NSOpenPanel()
        panel.treatsFilePackagesAsDirectories = false
        reusableOpenPanel = panel
        return panel
    }

    func openFilePanel() {
        let panel = obtainOpenPanel()
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        panel.title = "打开文件或文件夹"
        panel.message = "可选择 Markdown 文件、文件夹，或按住 ⌘ 同时多选打开"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = MarkdownContentTypes.all

        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let urls = panel.urls
            for url in urls {
                self.openURL(url)
            }
        }
    }

    func openFolderPanel() {
        let panel = obtainOpenPanel()
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        panel.title = "打开工作区文件夹"
        panel.message = nil
        panel.prompt = "打开文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.openFolder(url)
        }
    }

    func openURL(_ url: URL) {
        let standardized = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDir) else {
            showToast("找不到路径：\(standardized.lastPathComponent)")
            return
        }
        if isDir.boolValue {
            openFolder(standardized)
        } else {
            openFile(standardized)
        }
    }

    func openFolder(_ url: URL) {
        workspaceURL = url
        withAnimation(.snappy(duration: 0.25)) {
            isSidebarVisible = true
        }
        refreshFileTree(autoOpenFirstIfWelcome: true)
    }

    func closeWorkspace() {
        fileTreeScanTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) {
            workspaceURL = nil
            fileTree = []
        }
    }

    func openFile(_ url: URL) {
        let targetURL = url.standardizedFileURL

        // If already open in a tab, switch straight to it!
        if let existing = tabs.first(where: { $0.fileURL?.standardizedFileURL == targetURL }) {
            selectTab(existing.id)
            return
        }

        Task {
            autoSaveTask?.cancel()

            // Read file content off the main thread so large documents never stall UI
            let readResult: Result<String, Error> = await Task.detached(priority: .userInitiated) {
                Result { try Self.readMarkdownStringOffMain(from: targetURL) }
            }.value

            let content: String
            switch readResult {
            case .success(let text):
                content = text
            case .failure(let error):
                showToast("无法读取 \(targetURL.lastPathComponent)：\(error.localizedDescription)")
                return
            }

            await flushActiveTabFromEditor()
            addRecentFile(targetURL)

            let newTab = DocumentTab(
                id: UUID(),
                fileURL: targetURL,
                markdown: content,
                isDirty: false,
                editorMode: .wysiwyg,
                outline: [],
                activeHeadingId: "",
                stats: DocumentStats(),
                untitledNumber: 0,
                isWelcomePlaceholder: false
            )

            if let currentIdx = activeTabIndex,
               !tabs[currentIdx].isDirty,
               tabs[currentIdx].fileURL == nil,
               (tabs[currentIdx].isWelcomePlaceholder || tabs[currentIdx].markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                tabs[currentIdx] = newTab
            } else {
                withAnimation(.snappy(duration: 0.2)) {
                    tabs.append(newTab)
                }
            }

            activateTab(newTab.id)
        }
    }

    nonisolated private static func readMarkdownStringOffMain(from url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8.hasPrefix("\u{FEFF}") ? String(utf8.dropFirst()) : utf8
        }
        var detectedEncoding: String.Encoding = .utf8
        if let detected = try? String(contentsOf: url, usedEncoding: &detectedEncoding) {
            return detected
        }
        let rawData = try Data(contentsOf: url)
        return String(decoding: rawData, as: UTF8.self)
    }

    func refreshFileTree(autoOpenFirstIfWelcome: Bool = false) {
        fileTreeScanTask?.cancel()
        guard let root = workspaceURL else {
            fileTree = []
            return
        }
        fileTreeScanTask = Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                FileTreeNode.scan(directory: root)
            }.value
            guard !Task.isCancelled else { return }
            self.fileTree = scanned

            if autoOpenFirstIfWelcome,
               self.tabs.count == 1,
               let only = self.tabs.first,
               only.isWelcomePlaceholder,
               !only.isDirty {
                let flat = FileTreeNode.flattenMarkdownFiles(from: scanned)
                if let readme = flat.first(where: { $0.name.lowercased() == "readme.md" }) ?? flat.first {
                    self.openFile(readme.url)
                }
            }
        }
    }

    func createNewMarkdownFileInWorkspace(named rawName: String) {
        guard let root = workspaceURL else {
            openFolderPanel()
            return
        }
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "新笔记" }
        if !name.lowercased().hasSuffix(".md") && !name.lowercased().hasSuffix(".markdown") {
            name += ".md"
        }
        let target = root.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: target.path) {
            let initial = "# \(target.deletingPathExtension().lastPathComponent)\n\n"
            try? initial.write(to: target, atomically: true, encoding: .utf8)
        }
        refreshFileTree()
        openFile(target)
    }

    func saveDocument(silent: Bool = false) {
        Task {
            _ = await saveTabSynchronously(tabID: activeTabID, silent: silent)
        }
    }

    @discardableResult
    private func saveTabSynchronously(tabID: UUID, silent: Bool = false) async -> Bool {
        if tabID == activeTabID {
            await flushActiveTabFromEditor()
        }
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return false }

        if let url = tabs[idx].fileURL {
            do {
                lastDiskSaveDate = Date()
                try tabs[idx].markdown.write(to: url, atomically: true, encoding: .utf8)
                tabs[idx].isDirty = false
                if tabID == activeTabID {
                    isDirty = false
                }
                if !silent {
                    showToast("已保存 \(url.lastPathComponent)")
                }
                return true
            } catch {
                showToast("保存失败：\(error.localizedDescription)")
                return false
            }
        } else {
            return await saveTabAsSynchronously(tabID: tabID)
        }
    }

    func saveDocumentAs() {
        Task {
            _ = await saveTabAsSynchronously(tabID: activeTabID)
        }
    }

    @discardableResult
    private func saveTabAsSynchronously(tabID: UUID) async -> Bool {
        if tabID == activeTabID {
            await flushActiveTabFromEditor()
        }
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return false }

        let panel = NSSavePanel()
        panel.title = "保存 Markdown 文档"
        let suggested = tabs[idx].fileURL?.lastPathComponent ?? "\(tabs[idx].title).md"
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let dest = panel.url else { return false }

        do {
            lastDiskSaveDate = Date()
            try tabs[idx].markdown.write(to: dest, atomically: true, encoding: .utf8)
            tabs[idx].fileURL = dest
            tabs[idx].isDirty = false
            tabs[idx].isWelcomePlaceholder = false
            if tabID == activeTabID {
                fileURL = dest
                isDirty = false
                startWatching(dest)
            }
            addRecentFile(dest)
            if workspaceURL != nil {
                refreshFileTree()
            }
            showToast("已保存到 \(dest.lastPathComponent)")
            return true
        } catch {
            showToast("保存失败：\(error.localizedDescription)")
            return false
        }
    }

    private func startWatching(_ url: URL) {
        watcher.watch(url: url) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if Date().timeIntervalSince(self.lastDiskSaveDate) < 1.5 { return }
                guard let currentURL = self.fileURL, currentURL == url, !self.isDirty else { return }
                if let fresh = try? Self.readMarkdownStringOffMain(from: url), fresh != self.markdown {
                    self.markdown = fresh
                    self.syncActiveTabSnapshot()
                    self.bridgeController?.loadDocument(markdown: fresh, baseDirPath: self.baseDirectoryPath)
                    self.showToast("检测到外部更新，已自动刷新")
                }
            }
        }
    }

    // MARK: - Mode & Editor Actions

    func toggleEditorMode() {
        let next: EditorMode = (editorMode == .wysiwyg) ? .source : .wysiwyg
        setEditorMode(next)
    }

    func setEditorMode(_ mode: EditorMode) {
        editorMode = mode
        syncActiveTabSnapshot()
        bridgeController?.setMode(mode)
    }

    func applySettings(_ settings: AppSettings) {
        bridgeController?.applyPreferences(settings.bridgePayload)
    }

    func execCommand(_ cmd: String, arg: String? = nil) {
        bridgeController?.execCommand(cmd, arg: arg)
    }

    func jumpToOutlineItem(_ item: OutlineItem) {
        activeHeadingId = item.id
        bridgeController?.scrollToPos(item.pos)
    }

    func openSearchMatch(tabID: UUID?, url: URL?, query: String, occurrenceIndex: Int = 0) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let jumpToMatch: @MainActor () -> Void = { [weak self] in
            guard let self, !trimmed.isEmpty else { return }
            self.findQuery = trimmed
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                var res = await self.bridgeController?.find(
                    query: trimmed,
                    caseSensitive: false,
                    direction: "current"
                )
                if occurrenceIndex > 0 {
                    for _ in 0..<occurrenceIndex {
                        res = await self.bridgeController?.find(
                            query: trimmed,
                            caseSensitive: false,
                            direction: "next"
                        )
                    }
                }
                self.findTotalCount = res?.count ?? 0
                self.findCurrentIndex = res?.current ?? 0
            }
        }

        if let tabID {
            if tabID == activeTabID {
                jumpToMatch()
            } else {
                selectTab(tabID)
                jumpToMatch()
            }
        } else if let url {
            openFile(url)
            jumpToMatch()
        }
    }

    // MARK: - Image Insertion

    func insertImagePanel() {
        let panel = obtainOpenPanel()
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        panel.title = "选择要插入的图片"
        panel.message = nil
        panel.prompt = "插入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]

        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.insertImageFile(url)
            }
        }
    }

    func insertImageFile(_ sourceURL: URL) {
        do {
            let relPath = try ImageAssetManager.importImageFile(
                from: sourceURL,
                documentURL: fileURL,
                workspaceURL: workspaceURL,
                strategy: AppSettings.shared.imageStrategy
            )
            let alt = sourceURL.deletingPathExtension().lastPathComponent
            bridgeController?.insertImage(relativePath: relPath, alt: alt)
            showToast("已插入图片：\(URL(fileURLWithPath: relPath).lastPathComponent)")
        } catch {
            showToast("图片插入失败：\(error.localizedDescription)")
        }
    }

    func insertPastedImageData(_ data: Data, mimeType: String, fileName: String?) {
        do {
            let relPath = try ImageAssetManager.saveImageData(
                data,
                mimeType: mimeType,
                suggestedName: fileName,
                documentURL: fileURL,
                workspaceURL: workspaceURL,
                strategy: AppSettings.shared.imageStrategy
            )
            bridgeController?.insertImage(relativePath: relPath, alt: "image")
            showToast("已粘贴并保存图片")
        } catch {
            showToast("粘贴图片失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Find & Replace

    func openFindBar() {
        withAnimation(.snappy(duration: 0.22)) {
            isFindBarVisible = true
        }
    }

    func closeFindBar() {
        withAnimation(.snappy(duration: 0.2)) {
            isFindBarVisible = false
        }
        findCurrentIndex = 0
        findTotalCount = 0
        bridgeController?.clearFind()
    }

    func performFind(direction: String = "current") {
        Task {
            let res = await bridgeController?.find(
                query: findQuery,
                caseSensitive: findCaseSensitive,
                direction: direction
            )
            findTotalCount = res?.count ?? 0
            findCurrentIndex = res?.current ?? 0
        }
    }

    func performReplaceCurrent() {
        Task {
            let res = await bridgeController?.replaceCurrent(query: findQuery, replacement: replaceQuery)
            findTotalCount = res?.count ?? 0
            findCurrentIndex = res?.current ?? 0
        }
    }

    func performReplaceAll() {
        Task {
            let res = await bridgeController?.replaceAll(query: findQuery, replacement: replaceQuery)
            findTotalCount = res?.count ?? 0
            findCurrentIndex = res?.current ?? 0
            showToast("已全部替换")
        }
    }

    // MARK: - Export

    func exportPDF() {
        Task { [weak self] in
            guard let self else { return }
            guard let data = await bridgeController?.fetchExportData() else {
                showToast("导出失败：编辑器尚未就绪")
                return
            }
            ExportService.exportPDF(
                title: displayTitle,
                bodyHTML: data.html,
                editorCSS: data.css,
                baseDirPath: baseDirectoryPath
            ) { [weak self] result in
                switch result {
                case .success(let url):
                    self?.showToast("已导出 PDF：\(url.lastPathComponent)")
                case .failure(let err):
                    if (err as NSError).code != NSUserCancelledError {
                        self?.showToast("导出 PDF 失败：\(err.localizedDescription)")
                    }
                }
            }
        }
    }

    func exportHTML() {
        Task { [weak self] in
            guard let self else { return }
            guard let data = await bridgeController?.fetchExportData() else {
                showToast("导出失败：编辑器尚未就绪")
                return
            }
            ExportService.exportStandaloneHTML(
                title: displayTitle,
                bodyHTML: data.html,
                editorCSS: data.css,
                baseDirPath: baseDirectoryPath
            ) { [weak self] result in
                switch result {
                case .success(let url):
                    self?.showToast("已导出 HTML：\(url.lastPathComponent)")
                case .failure(let err):
                    if (err as NSError).code != NSUserCancelledError {
                        self?.showToast("导出 HTML 失败：\(err.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Recent Files

    private func loadRecentFiles() {
        let paths = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        recentFiles = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func addRecentFile(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 12 {
            recentFiles = Array(recentFiles.prefix(12))
        }
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: recentFilesKey)
    }

    // MARK: - Rich Welcome Showcase Document

    static let welcomeMarkdown = """
    # 欢迎使用 Lepora

    **Lepora** 是专为 macOS 打造的极简原生 Markdown 编辑器，深度融合 **Liquid Glass** 液态玻璃交互、**Typora 级所见即所得 (WYSIWYG)** 排版，以及离线高速 **KaTeX + MathJax** 与 **Mermaid** 渲染引擎。

    > [!TIP]
    > 按下 `⌘/` 可在 **所见即所得** 与 **源代码模式** 间毫秒级无缝切换；按下 `⌘O` 打开任意 Markdown 文件或直接拖入窗口；按下 `⌘N` 新建标签页且自动保留已有文档；按下 `⌘P` 呼出快速跳转。

    ---

    ## 1. 全量 LaTeX 数学公式支持

    Lepora 支持所有主流 LaTeX 定界符与环境，点击任意公式即可像 Typora 一样原地编辑并实时预览：

    - **行内美元定界符**：质能方程 $E = mc^2$ 与欧拉恒等式 $e^{i\\pi} + 1 = 0$。
    - **标准 LaTeX 行内括号**：高斯分布密度 \\(f(x) = \\frac{1}{\\sigma\\sqrt{2\\pi}} e^{-\\frac{1}{2}\\left(\\frac{x-\\mu}{\\sigma}\\right)^2}\\)。
    - **化学方程式 (`mhchem`)**：光合作用 $\\ce{6CO2 + 6H2O ->[h\\nu] C6H12O6 + 6O2 ^}$。

    ### 块级公式（`$$...$$` 与 `\\[...\\]`）

    $$
    \\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}, \\qquad \\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}
    $$

    \\[
    \\mathbf{J}_f(x) = \\begin{pmatrix}
      \\frac{\\partial f_1}{\\partial x_1} & \\cdots & \\frac{\\partial f_1}{\\partial x_n} \\\\
      \\vdots & \\ddots & \\vdots \\\\
      \\frac{\\partial f_m}{\\partial x_1} & \\cdots & \\frac{\\partial f_m}{\\partial x_n}
    \\end{pmatrix}
    \\]

    ### 独立 AMS 环境（自动启用 KaTeX / MathJax 完整引擎）

    \\begin{align}
    \\nabla \\cdot \\mathbf{E} &= \\frac{\\rho}{\\varepsilon_0} \\\\
    \\nabla \\cdot \\mathbf{B} &= 0 \\\\
    \\nabla \\times \\mathbf{E} &= -\\frac{\\partial \\mathbf{B}}{\\partial t} \\\\
    \\nabla \\times \\mathbf{B} &= \\mu_0 \\mathbf{J} + \\mu_0 \\varepsilon_0 \\frac{\\partial \\mathbf{E}}{\\partial t}
    \\end{align}

    ---

    ## 2. Mermaid 流程图与时序图

    点击下方图表即可展开源码编辑，修改时实时刷新且绝不闪烁：

    ```mermaid
    flowchart LR
      A[Markdown 输入] --> B{Lepora 引擎}
      B -->|实时渲染| C[WYSIWYG 画布]
      B -->|⌘/ 切换| D[CodeMirror 源码]
      C --> E[KaTeX / MathJax 公式]
      C --> F[Mermaid 矢量图表]
      C --> G[导出 PDF / HTML]
    ```

    ---

    ## 3. 标准 Markdown、任务清单与交互式表格

    - [x] 原生 macOS 26/27 **Liquid Glass** 悬浮侧栏与状态胶囊
    - [x] 专注模式 (`⇧⌘F`) 与打字机居中模式 (`⇧⌘T`)
    - [x] 点击任意表格单元格即可浮现行列增删与对齐工具栏
    - [ ] 开始写下你的第一篇笔记吧！

    | 能力维度 | 语法示例 | 快捷键 / 交互 |
    | :--- | :---: | ---: |
    | 源代码切换 | `⌘/` | 实时双向同步 |
    | 插入图片 | `![alt](path)` | 拖拽 / `⌘V` / `⇧⌘I` |
    | 块级公式 | `$$` + 空格 | 点击原地展开编辑 |
    | 导出发布 | PDF / 独立 HTML | `⇧⌘E` / 菜单栏导出 |

    ```swift
    import SwiftUI

    struct LiquidGlassPill: View {
        var body: some View {
            Label("Lepora", systemImage: "sparkles")
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
    }
    ```
    """
}
