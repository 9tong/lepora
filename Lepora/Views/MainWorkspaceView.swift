import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Native macOS 26/27 translucent Liquid Glass canvas backdrop combining behind-window desktop vibrancy
/// with Apple's native `NSGlassEffectView` clear ↔ regular cross-fade driven smoothly by `intensity` (0...1).
private struct LiquidGlassCanvasBackdrop: NSViewRepresentable {
    let intensity: Double

    final class BackdropHostView: NSView {
        let behindWindow = NSVisualEffectView()
        let clearGlass = NSGlassEffectView()
        let regularGlass = NSGlassEffectView()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true

            // 1. Live behind-window translucent desktop blur (stays rich & luminous even when unfocused)
            behindWindow.translatesAutoresizingMaskIntoConstraints = false
            behindWindow.blendingMode = .behindWindow
            behindWindow.material = .hudWindow
            behindWindow.state = .active
            addSubview(behindWindow)

            // 2. Native macOS 26/27 Clear Liquid Glass optical refraction layer
            clearGlass.translatesAutoresizingMaskIntoConstraints = false
            clearGlass.style = .clear
            clearGlass.cornerRadius = 0
            addSubview(clearGlass)

            // 3. Native macOS 26/27 Regular Liquid Glass layer cross-faded in at higher frosting levels
            regularGlass.translatesAutoresizingMaskIntoConstraints = false
            regularGlass.style = .regular
            regularGlass.cornerRadius = 0
            addSubview(regularGlass)

            NSLayoutConstraint.activate([
                behindWindow.leadingAnchor.constraint(equalTo: leadingAnchor),
                behindWindow.trailingAnchor.constraint(equalTo: trailingAnchor),
                behindWindow.topAnchor.constraint(equalTo: topAnchor),
                behindWindow.bottomAnchor.constraint(equalTo: bottomAnchor),

                clearGlass.leadingAnchor.constraint(equalTo: leadingAnchor),
                clearGlass.trailingAnchor.constraint(equalTo: trailingAnchor),
                clearGlass.topAnchor.constraint(equalTo: topAnchor),
                clearGlass.bottomAnchor.constraint(equalTo: bottomAnchor),

                regularGlass.leadingAnchor.constraint(equalTo: leadingAnchor),
                regularGlass.trailingAnchor.constraint(equalTo: trailingAnchor),
                regularGlass.topAnchor.constraint(equalTo: topAnchor),
                regularGlass.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func apply(intensity raw: Double) {
            let t = CGFloat(min(1.0, max(0.0, raw)))
            // Continuous 120fps optical modulation: 0.0 = crystal clear water glass -> 1.0 = deep frosted glass
            behindWindow.alphaValue = 0.36 + t * 0.64
            clearGlass.alphaValue = max(0.20, 1.0 - t * 0.72)
            let regularBlend = max(0.0, min(1.0, (t - 0.14) / 0.72))
            regularGlass.alphaValue = regularBlend
        }
    }

    func makeNSView(context: Context) -> BackdropHostView {
        let host = BackdropHostView()
        host.apply(intensity: intensity)
        return host
    }

    func updateNSView(_ nsView: BackdropHostView, context: Context) {
        nsView.apply(intensity: intensity)
    }
}

/// Invisible macOS window drag area so the frameless top edge remains effortlessly draggable.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggableNSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

/// Observes the hosting NSWindow's fullscreen transitions and manages its unified toolbar cleanly
/// so fullscreen mode never drops an empty system toolbar over Lepora's floating controls.
private struct WindowFullscreenObserver: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> ObserverNSView {
        let view = ObserverNSView()
        view.onFullScreenChange = { full in
            DispatchQueue.main.async {
                if isFullScreen != full {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isFullScreen = full
                    }
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: ObserverNSView, context: Context) {}

    final class ObserverNSView: NSView {
        var onFullScreenChange: ((Bool) -> Void)?
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else { return }

            let currentlyFull = window.styleMask.contains(.fullScreen)
            syncWindowChrome(window: window, fullScreen: currentlyFull)
            onFullScreenChange?(currentlyFull)

            let nc = NotificationCenter.default
            observers.append(
                nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                    Task { @MainActor in
                        guard let window else { return }
                        self?.syncWindowChrome(window: window, fullScreen: true)
                        self?.onFullScreenChange?(true)
                    }
                }
            )
            observers.append(
                nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                    Task { @MainActor in
                        guard let window else { return }
                        self?.syncWindowChrome(window: window, fullScreen: false)
                        self?.onFullScreenChange?(false)
                    }
                }
            )
        }

        @MainActor
        private func syncWindowChrome(window: NSWindow, fullScreen: Bool) {
            if fullScreen {
                window.toolbar = nil
            } else {
                if window.toolbar == nil {
                    window.toolbar = NSToolbar(identifier: "LeporaUnifiedToolbar")
                }
                window.toolbarStyle = .unified
                window.titlebarSeparatorStyle = .none
            }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .clear
            window.isOpaque = false
        }

        nonisolated private func removeObservers() {
            for obs in observers {
                NotificationCenter.default.removeObserver(obs)
            }
            observers.removeAll()
        }

        deinit {
            removeObservers()
        }
    }
}

struct MainWorkspaceView: View {
    @Bindable var session: DocumentSession
    @Bindable var settings: AppSettings

    @Environment(\.colorScheme) private var systemColorScheme
    @State private var isTitleHovered: Bool = false
    @State private var isSidebarToggleHovered: Bool = false
    @State private var isFullScreen: Bool = false

    var body: some View {
        ZStack {
            // 0. Fullscreen window state observer
            WindowFullscreenObserver(isFullScreen: $isFullScreen)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            // 1. Canvas background (pure Typora paper / obsidian / native NSGlassEffectView)
            canvasBackground
                .ignoresSafeArea()

            // 2. Full-bleed edge-to-edge native WKWebView WYSIWYG + Source Editor
            EditorWebView(session: session, settings: settings)
                .padding(.leading, session.isSidebarVisible ? 264 : 0)
                .padding(.trailing, session.isOutlineVisible ? 226 : 0)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: session.isSidebarVisible)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: session.isOutlineVisible)
                .ignoresSafeArea()

            // 3. Top frameless drag region + floating Liquid Glass title / tab strip
            VStack(spacing: 0) {
                ZStack {
                    WindowDragHandle()
                        .frame(height: 52)

                    if session.tabs.count <= 1 {
                        // Ultra-minimal single document title pill
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                session.isQuickOpenVisible = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if session.isDirty {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 6, height: 6)
                                }
                                Text(session.displayTitle)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular, in: .capsule)
                        .opacity((isTitleHovered || !session.isTypingMinimalMode) ? 1.0 : 0.22)
                        .animation(.easeInOut(duration: 0.25), value: session.isTypingMinimalMode)
                        .onHover { isTitleHovered = $0 }
                        .help("点击或按 ⌘P 快速跳转文档与大纲")
                    } else {
                        // Sleek Liquid Glass multi-document tab bar (true-centered over writing canvas)
                        DocumentTabBarView(session: session)
                            .padding(.leading, session.isSidebarVisible ? 16 : (isFullScreen ? 56 : 126))
                            .padding(.trailing, session.isOutlineVisible ? 16 : 246)
                            .opacity((isTitleHovered || !session.isTypingMinimalMode) ? 1.0 : 0.35)
                            .animation(.easeInOut(duration: 0.25), value: session.isTypingMinimalMode)
                            .onHover { isTitleHovered = $0 }
                    }
                }

                Spacer()
            }
            .padding(.leading, session.isSidebarVisible ? 264 : 0)
            .padding(.trailing, session.isOutlineVisible ? 226 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: session.isSidebarVisible)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: session.isOutlineVisible)
            .ignoresSafeArea(.container, edges: .top)

            // 4. Floating Liquid Glass Sidebar (left — Files & Open Documents, vertically centered)
            if session.isSidebarVisible {
                HStack(spacing: 0) {
                    LiquidGlassSidebar(session: session, isFullScreen: isFullScreen)
                        .padding(.vertical, 10)
                        .padding(.leading, 10)
                    Spacer()
                }
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // 4b. Top-left Sidebar expand/collapse button (adapts cleanly between windowed & fullscreen)
            VStack {
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            session.isSidebarVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSidebarToggleHovered ? Color.primary : Color.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(isSidebarToggleHovered ? 0.08 : 0))
                                    .frame(width: 24, height: 24)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 30, height: 30)
                    .background {
                        if !session.isSidebarVisible {
                            Color.clear
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                    .onHover { isSidebarToggleHovered = $0 }
                    .help(session.isSidebarVisible ? "收起左侧边栏 (⇧⌘L)" : "展开左侧边栏 (⇧⌘L)")
                    .padding(.leading, session.isSidebarVisible ? 216 : (isFullScreen ? 14 : 86))
                    .padding(.top, 11)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: session.isSidebarVisible)
                    .animation(.easeInOut(duration: 0.22), value: isFullScreen)

                    Spacer()
                }
                Spacer()
            }
            .ignoresSafeArea(.container, edges: .top)

            // 5. Floating Liquid Glass Top-Trailing Minimalist Controls, Find Bar & Right Outline Panel
            VStack(alignment: .trailing, spacing: 10) {
                FloatingToolbar(session: session, settings: settings)
                    .padding(.top, 11)
                    .padding(.trailing, 14)

                if session.isFindBarVisible {
                    FindReplaceBar(session: session)
                        .padding(.trailing, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if session.isOutlineVisible {
                    FloatingOutlinePanel(session: session)
                        .padding(.trailing, 14)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .ignoresSafeArea(.container, edges: .top)

            // 6. Floating Bottom-Trailing Animated Feather & Transient Toast
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    StatusCapsuleView(session: session, settings: settings)
                        .padding(.trailing, 18)
                        .padding(.bottom, 10)
                }
            }

            // 7. Spotlight-style Liquid Glass Quick Switcher (⌘P / ⌘K)
            if session.isQuickOpenVisible {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.18)) {
                            session.isQuickOpenVisible = false
                        }
                    }
                    .transition(.opacity)

                VStack {
                    QuickOpenSheet(session: session, settings: settings)
                        .padding(.top, 88)
                    Spacer()
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .onChange(of: settings.theme) {
            LeporaApp.syncAppearance(for: settings.theme)
            session.applySettings(settings)
            LeporaApp.syncDockIcon(for: settings.theme)
        }
        .onChange(of: settings.fontSize) { session.applySettings(settings) }
        .onChange(of: settings.lineHeight) { session.applySettings(settings) }
        .onChange(of: settings.maxWidth) { session.applySettings(settings) }
        .onChange(of: settings.mathEngine) { session.applySettings(settings) }
        .onChange(of: settings.focusMode) { session.applySettings(settings) }
        .onChange(of: settings.typewriterMode) { session.applySettings(settings) }
        .onOpenURL { url in
            session.openURL(url)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDroppedFileProviders(providers)
        }
    }

    private func handleDroppedFileProviders(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else {
                    url = nil
                }
                guard let resolved = url else { return }
                Task { @MainActor in
                    if ImageAssetManager.supportedImageExtensions.contains(resolved.pathExtension.lowercased()) {
                        session.insertImageFile(resolved)
                    } else {
                        session.openURL(resolved)
                    }
                }
            }
        }
        return handled
    }

    @ViewBuilder
    private var canvasBackground: some View {
        switch settings.theme {
        case .translucent:
            ZStack {
                LiquidGlassCanvasBackdrop(intensity: settings.glassIntensity)
                // Smooth luminance frost veil scaling from 0% (ultra-clear) to ~65% (velvety frosted glass)
                let t = min(1.0, max(0.0, settings.glassIntensity))
                let veilOpacity = t * t * 0.56 + t * 0.09
                (systemColorScheme == .dark
                    ? Color(red: 0.075, green: 0.082, blue: 0.105)
                    : Color.white
                )
                .opacity(veilOpacity)
            }
        case .paper:
            Color(red: 0.973, green: 0.961, blue: 0.933)
        case .light:
            Color.white
        case .dark:
            Color(red: 0.078, green: 0.086, blue: 0.102)
        case .system:
            if systemColorScheme == .dark {
                Color(red: 0.078, green: 0.086, blue: 0.102)
            } else {
                Color.white
            }
        }
    }
}
