import SwiftUI

struct FindReplaceBar: View {
    @Bindable var session: DocumentSession
    @State private var showReplace: Bool = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        showReplace.toggle()
                    }
                } label: {
                    Image(systemName: showReplace ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                TextField("查找内容…", text: $session.findQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($isSearchFocused)
                    .onChange(of: session.findQuery) {
                        session.performFind(direction: "current")
                    }
                    .onSubmit {
                        session.performFind(direction: "next")
                    }

                if !session.findQuery.isEmpty {
                    Text(session.findTotalCount > 0 ? "\(session.findCurrentIndex)/\(session.findTotalCount)" : "0/0")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(session.findTotalCount > 0 ? Color.secondary : Color.red.opacity(0.8))
                        .monospacedDigit()
                }

                Button {
                    session.findCaseSensitive.toggle()
                    session.performFind(direction: "current")
                } label: {
                    Text("Aa")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(session.findCaseSensitive ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(session.findCaseSensitive ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("区分大小写")

                Button {
                    session.performFind(direction: "prev")
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Button {
                    session.performFind(direction: "next")
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Button {
                    session.closeFindBar()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }

            if showReplace {
                HStack(spacing: 6) {
                    Spacer().frame(width: 18)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("替换为…", text: $session.replaceQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .onSubmit {
                            session.performReplaceCurrent()
                        }

                    Button("替换") {
                        session.performReplaceCurrent()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.mini)

                    Button("全部") {
                        session.performReplaceAll()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.mini)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 340)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand {
            session.closeFindBar()
        }
    }
}
