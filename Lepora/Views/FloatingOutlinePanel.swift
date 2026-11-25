import SwiftUI

struct FloatingOutlinePanel: View {
    @Bindable var session: DocumentSession
    @State private var filterText: String = ""
    @State private var isHovered: Bool = false
    @State private var hoveredItemID: String?

    private var filteredOutline: [OutlineItem] {
        guard !filterText.isEmpty else { return session.outline }
        return session.outline.filter { $0.text.localizedCaseInsensitiveContains(filterText) }
    }

    private var restingOpacity: Double {
        if isHovered || !filterText.isEmpty {
            return 1.0
        }
        return session.isTypingMinimalMode ? 0.36 : 0.78
    }

    var body: some View {
        VStack(spacing: 0) {
            // Featherlight minimalist header
            HStack(spacing: 5) {
                Text("大纲")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)

                if !session.outline.isEmpty {
                    Text("\(session.outline.count)")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.quaternary)
                        .monospacedDigit()
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        session.isOutlineVisible = false
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(isHovered ? 0.05 : 0), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("收起大纲 (⌥⌘O)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 7)

            // Subtle filter field when document has many headings
            if session.outline.count >= 6 {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    TextField("筛选…", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            Divider()
                .opacity(0.16)
                .padding(.horizontal, 10)

            if filteredOutline.isEmpty {
                VStack(spacing: 5) {
                    Text(session.outline.isEmpty ? "暂无大纲" : "无匹配标题")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .padding(.horizontal, 12)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1.5) {
                        ForEach(filteredOutline) { item in
                            let isActive = session.activeHeadingId == item.id
                            let isRowHover = hoveredItemID == item.id

                            Button {
                                session.jumpToOutlineItem(item)
                            } label: {
                                HStack(spacing: 6) {
                                    Capsule()
                                        .fill(isActive ? Color.accentColor.opacity(0.75) : Color.clear)
                                        .frame(width: 2, height: 11)

                                    Text(item.text)
                                        .font(.system(
                                            size: item.level == 1 ? 12 : 11.5,
                                            weight: isActive ? .medium : .regular
                                        ))
                                        .foregroundStyle(
                                            isActive
                                                ? Color.primary.opacity(0.88)
                                                : (item.level <= 2 ? Color.secondary.opacity(0.88) : Color.secondary.opacity(0.65))
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer(minLength: 0)
                                }
                                .padding(.leading, CGFloat(max(0, item.level - 1)) * 9)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background {
                                    if isActive {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.primary.opacity(0.045))
                                    } else if isRowHover {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.primary.opacity(0.03))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
                            }
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 7)
                }
                .frame(maxHeight: 460)
            }
        }
        .frame(width: 204)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 3)
        .opacity(restingOpacity)
        .animation(.easeInOut(duration: 0.22), value: restingOpacity)
        .onHover { isHovered = $0 }
    }
}
