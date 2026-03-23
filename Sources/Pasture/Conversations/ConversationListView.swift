import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ConversationListView: View {
    @EnvironmentObject var connection: ConnectionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ConversationRecord.updatedAt, order: .reverse) private var conversations: [ConversationRecord]

    @AppStorage("pasture.chat.themeOverride") private var themeOverrideRaw: String = ""

    @State private var selectedConversation: ConversationRecord?
    @State private var listEnvironment = ModelEnvironment.chat(for: nil)
    @State private var isShowingSettings = false
    @State private var renamingConversation: ConversationRecord?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                EnvironmentBackground(environment: listEnvironment)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar

                    if conversations.isEmpty {
                        emptyState
                    } else {
                        conversationList
                    }
                }

                newChatButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 28)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedConversation) { conversation in
                ChatView(conversation: conversation, modelContext: modelContext)
            }
        }
        .onAppear { updateEnvironment() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            updateEnvironment()
        }
        .onChange(of: conversations.first?.modelName) { _, _ in updateEnvironment() }
        .onChange(of: connection.installedModels) { _, _ in updateEnvironment() }
        .onChange(of: themeOverrideRaw) { _, _ in updateEnvironment() }
        .sheet(isPresented: $isShowingSettings) {
            ChatSettingsView()
                .environmentObject(connection)
        }
        .alert("Rename Conversation", isPresented: Binding(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renamingConversation = nil }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Pasture")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)

                connectionStatus
            }

            Spacer()

            settingsButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 5, height: 5)

            Text(connectionStatusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))
        }
    }

    private var connectionStatusColor: Color {
        switch connection.state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .discovering: return .yellow
        case .failed: return .red
        }
    }

    private var connectionStatusText: String {
        switch connection.state {
        case .connected(let name): return name
        case .connecting(let name): return "Connecting to \(name)…"
        case .reconnecting(let name, _): return "Reconnecting to \(name ?? "your Mac")…"
        case .discovering: return "Looking for your Mac…"
        case .failed: return "Disconnected"
        }
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 34, height: 34)
                .modifier(TopBarCircleSurface(palette: listEnvironment.palette, reduceTransparency: reduceTransparency))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conversation list

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(conversations) { conversation in
                    Button {
                        selectedConversation = conversation
                    } label: {
                        ConversationRow(
                            conversation: conversation,
                            palette: listEnvironment.palette,
                            reduceTransparency: reduceTransparency
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(conversation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            renamingConversation = conversation
                            renameText = conversation.displayTitle
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            delete(conversation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.and.pencil")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.white.opacity(0.25))
                .shadow(color: .black.opacity(0.20), radius: 6, y: 2)

            VStack(spacing: 6) {
                Text("No conversations yet")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))

                Text("Tap + to start your first one.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - New chat FAB

    private var newChatButton: some View {
        Button {
            createAndOpenNewConversation()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .modifier(NewChatFABSurface(palette: listEnvironment.palette))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func createAndOpenNewConversation() {
        let conversation = ConversationRecord()
        modelContext.insert(conversation)
        do {
            try modelContext.save()
        } catch {
            print("[ConversationListView] Failed to save new conversation: \(error)")
        }
        selectedConversation = conversation
#if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
    }

    private func delete(_ conversation: ConversationRecord) {
        modelContext.delete(conversation)
        do {
            try modelContext.save()
        } catch {
            print("[ConversationListView] Failed to save after deleting conversation: \(error)")
        }
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let conversation = renamingConversation else {
            renamingConversation = nil
            return
        }
        conversation.title = trimmed
        do {
            try modelContext.save()
        } catch {
            print("[ConversationListView] Failed to save renamed conversation: \(error)")
        }
        renamingConversation = nil
    }

    private func updateEnvironment() {
        let modelName = conversations.first?.modelName
        let environment: ModelEnvironment
        if let override = TimeOfDay(rawValue: themeOverrideRaw) {
            environment = ModelEnvironment(
                timeOfDay: override,
                complexity: ModelComplexity.from(modelName: modelName),
                isLateNight: (0..<5).contains(Calendar.current.component(.hour, from: Date()))
            )
        } else {
            environment = ModelEnvironment.chat(for: modelName)
        }
        withAnimation(.easeInOut(duration: 0.6)) {
            listEnvironment = environment
        }
    }
}

// MARK: - Conversation row

private struct ConversationRow: View {
    let conversation: ConversationRecord
    let palette: EnvironmentPalette
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(conversation.displayTitle)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(relativeTime(conversation.updatedAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }

                if let preview = conversation.previewText {
                    Text(preview)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }

                if let modelName = conversation.modelName {
                    Text(modelName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule())
                        .padding(.top, 1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .modifier(ConversationRowSurface())
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 60 { return "Now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        let days = Int(seconds / 86400)
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        return Self.dateFormatter.string(from: date)
    }
}

// MARK: - Surface modifiers

private struct ConversationRowSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
    }
}

private struct NewChatFABSurface: ViewModifier {
    let palette: EnvironmentPalette

    func body(content: Content) -> some View {
        content
            .background(palette.userBubble, in: Circle())
            .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
    }
}

private struct TopBarCircleSurface: ViewModifier {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(Color.black.opacity(0.12)).interactive(), in: Circle())
        } else {
            content.background(.black.opacity(0.22), in: Circle())
        }
    }
}

