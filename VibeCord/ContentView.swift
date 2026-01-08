import SwiftUI
import WebKit

// Helper to display the Engine's WebView
struct EngineWebView: NSViewRepresentable {
    let internalWebView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        return internalWebView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct ContentView: View {
    @StateObject var engine = DiscordEngine()
    @State private var messageText = ""

    var body: some View {
        ZStack {
            // Layer 1: Engine WebView (hidden after login)
            EngineWebView(internalWebView: engine.webView)
                .opacity(engine.isLoggedIn ? 0 : 1)

            // Layer 2: Native UI
            if engine.isLoggedIn {
                HStack(spacing: 0) {
                    // Left: Chat List Sidebar
                    ChatListSidebar(
                        chats: engine.chats,
                        selectedId: engine.selectedChatId,
                        onSelect: { chatId in
                            engine.selectChat(chatId)
                        }
                    )
                    .frame(width: 240)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Right: Message Area
                    if engine.selectedChatId != nil {
                        MessageArea(
                            messages: engine.messages,
                            messageText: $messageText,
                            onSend: sendMessage
                        )
                    } else {
                        // No chat selected state
                        VStack {
                            Spacer()
                            Text("Select a chat to start messaging")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                    }
                }
                .transition(.opacity)
            } else {
                // Login Hint
                VStack {
                    Spacer()
                    Text("Please Log In via the Discord Web Interface")
                        .font(.headline)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding()
                }
                .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .overlay(
            // Debug Status Overlay
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🔍 DEBUG INFO")
                            .font(.caption2)
                            .fontWeight(.bold)
                        Text("Logged In: \(engine.isLoggedIn ? "✅" : "❌")")
                            .font(.caption2)
                        Text("Chats: \(engine.chats.count)")
                            .font(.caption2)
                        Text("Selected: \(engine.selectedChatId ?? "none")")
                            .font(.caption2)
                        Text("Messages: \(engine.messages.count)")
                            .font(.caption2)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        )
    }

    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        engine.sendMessage(messageText)
        messageText = ""
    }
}


// MARK: - Chat List Sidebar

struct ChatListSidebar: View {
    let chats: [Chat]
    let selectedId: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Direct Messages")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Chat List
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(chats) { chat in
                        ChatRow(
                            chat: chat,
                            isSelected: chat.id == selectedId,
                            onSelect: { onSelect(chat.id) }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct ChatRow: View {
    let chat: Chat
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Avatar
                if let url = chat.avatarURL {
                    AsyncImage(url: url) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    Circle().fill(Color.gray)
                        .frame(width: 32, height: 32)
                }

                // Name and Preview
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.name)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let preview = chat.lastMessage, !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
    }
}

// MARK: - Message Area

struct MessageArea: View {
    let messages: [Message]
    @Binding var messageText: String
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Message List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            MessageRow(message: msg)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages) { _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input Area
            HStack {
                TextField("Message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit(onSend)

                Button("Send") {
                    onSend()
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            if let url = message.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Circle().fill(Color.gray)
                    .frame(width: 40, height: 40)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.authorName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(message.content)
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 4)
        .id(message.id)
    }
}
