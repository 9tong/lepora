import SwiftUI
import AppKit

struct DocumentTabBarView: View {
    @Bindable var session: DocumentSession
    @State private var hoveredTabID: UUID?

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(session.tabs) { tab in
                        tabPill(for: tab)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: 640)

            Button {
                session.createNewDocument()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("新建标签页 (⌘N)")
        }
        .padding(.horizontal, 4)
        .frame(height: 30)
        .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder
    private func tabPill(for tab: DocumentTab) -> some View {
        let isActive = (tab.id == session.activeTabID)
        let isHovering = (hoveredTabID == tab.id)

        HStack(spacing: 5) {
            if tab.isDirty {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5.5, height: 5.5)
            }

            Text(tab.title)
                .font(.system(size: 11.8, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: 130)

            Button {
                session.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(Color.primary.opacity(isHovering ? 0.08 : 0), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity((isHovering || isActive) ? 0.85 : 0)
            .help("关闭标签页 (⌘W)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 24)
        .background {
            if isActive {
                Capsule()
                    .fill(Color.primary.opacity(0.11))
            } else if isHovering {
                Capsule()
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            session.selectTab(tab.id)
        }
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
        }
        .contextMenu {
            Button("关闭当前标签页") {
                session.closeTab(tab.id)
            }
            if let url = tab.fileURL {
                Divider()
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
}
