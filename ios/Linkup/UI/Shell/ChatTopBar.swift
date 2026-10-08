import SwiftUI
import UIKit

/// The chat's top bar: sidebar button, title/model, new chat and the menu; the connection pill and update banner
/// stack underneath so they push the content down instead of covering it. Lives in the chat's `.safeAreaBar`.
struct ChatTopBar: View {
    let sessionId: String?
    var sidebarLabel = "Open sidebar"
    var onSidebar: () -> Void = {}

    @Environment(SessionStore.self) private var store
    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui
    @Environment(UpdateChecker.self) private var updates

    @State private var isRenaming = false
    @State private var renameTitle = ""
    @State private var isConfirmingDelete = false

    private var session: SessionInfo? { sessionId.flatMap { store.session($0) } }

    private var showsConnectionPill: Bool {
        switch client.state {
        case .connecting, .offline: true
        case .connected, .notConfigured: false
        }
    }

    private var connectionDotColor: Color {
        switch client.state {
        case .connecting: Theme.accent
        case .offline: Theme.danger
        default: Theme.secondaryText
        }
    }

    private func agentName(_ id: String) -> String {
        store.agent(id)?.name ?? AgentKind(rawValue: id)?.title ?? id.capitalized
    }

    private var titleText: String { session?.displayTitle ?? "New chat" }

    private var subtitleText: String {
        let agentId = session?.agent ?? ui.draftAgent
        var parts = [agentName(agentId)]
        let project = session?.projectName ?? ui.draftProject.map { URL(fileURLWithPath: $0).lastPathComponent }
        if let project, !project.isEmpty { parts.append(project) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(spacing: 8) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    sidebarButton
                    titleButton
                    newChatButton
                    moreMenu
                }
            }

            if showsConnectionPill {
                connectionPill
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if updates.showsBanner, let release = updates.available {
                UpdateBanner(release: release)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: showsConnectionPill)
        .animation(.smooth(duration: 0.3), value: updates.showsBanner)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .alert("Rename", isPresented: $isRenaming) {
            TextField("Title", text: $renameTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = sessionId, !trimmed.isEmpty { store.update(id, title: trimmed) }
            }
        }
        .confirmationDialog("Delete session?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = sessionId {
                    store.delete(id)
                    ui.newChat()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this session? This action cannot be undone.")
        }
    }

    // MARK: Controls

    private var sidebarButton: some View {
        Button(action: onSidebar) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(sidebarLabel)
    }

    private var titleButton: some View {
        Button {
            ui.isShowingModelPicker = true
        } label: {
            VStack(spacing: 1) {
                Text(titleText)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .environment(\.layoutDirection, titleText.dominantLayoutDirection)
                Text(subtitleText)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(titleText), \(subtitleText). Choose model")
    }

    private var newChatButton: some View {
        Button {
            ui.newChat()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("New chat")
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Button {
                    ui.isShowingUsage = true
                } label: {
                    Label("Usage", systemImage: "chart.bar")
                }
                Button {
                    ui.isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            if let session {
                Section(session.displayTitle) {
                    Button {
                        renameTitle = session.title ?? session.displayTitle
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button {
                        store.update(session.id, pinned: !session.pinned)
                    } label: {
                        Label(session.pinned ? "Unpin" : "Pin", systemImage: session.pinned ? "pin.slash" : "pin")
                    }

                    Button {
                        Task {
                            do {
                                let forked = try await store.fork(session.id)
                                ui.openSession(forked.id)
                            } catch {
                                ui.toast = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("Branch into new session", systemImage: "arrow.triangle.branch")
                    }

                    Button {
                        ui.handoffSessionId = session.id
                    } label: {
                        Label("Hand off to another agent", systemImage: "arrow.left.arrow.right")
                    }

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("More")
    }

    private var connectionPill: some View {
        Button {
            client.reconnectIfNeeded()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionDotColor)
                    .frame(width: 7, height: 7)
                Text(client.state.label)
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Connection: \(client.state.label). Tap to reconnect.")
    }
}
