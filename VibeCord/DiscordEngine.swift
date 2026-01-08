import SwiftUI
import WebKit
import Combine

class DiscordEngine: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published var isLoggedIn: Bool = false
    @Published var messages: [Message] = []
    @Published var chats: [Chat] = []
    @Published var selectedChatId: String? = nil

    var webView: WKWebView!

    override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // 1. Setup Bridge
        // Register "discordNative" to receive postMessage calls
        config.userContentController.add(self, name: "discordNative")

        // CRITICAL: Add console message handler to see JavaScript logs!
        let consoleScript = WKUserScript(source: """
            (function() {
                const originalLog = console.log;
                const originalWarn = console.warn;
                const originalError = console.error;

                console.log = function(...args) {
                    window.webkit.messageHandlers.consoleLog.postMessage(args.join(' '));
                    originalLog.apply(console, args);
                };
                console.warn = function(...args) {
                    window.webkit.messageHandlers.consoleWarn.postMessage(args.join(' '));
                    originalWarn.apply(console, args);
                };
                console.error = function(...args) {
                    window.webkit.messageHandlers.consoleError.postMessage(args.join(' '));
                    originalError.apply(console, args);
                };
            })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(consoleScript)

        // Register console handlers
        config.userContentController.add(self, name: "consoleLog")
        config.userContentController.add(self, name: "consoleWarn")
        config.userContentController.add(self, name: "consoleError")

        // 2. Inject Scraper Payload
        let script = WKUserScript(source: DiscordJS.payload, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)

        // 3. Resource Blocking - DISABLED for now to allow Discord to load fully
        // TODO: Re-enable with more targeted blocking after confirming Discord works
        /*
        let blockerCSS = """
            img, video, canvas { display: none !important; }
            * { background-image: none !important; }
        """
        let cssScript = WKUserScript(source: "var s=document.createElement('style');s.innerHTML=`\(blockerCSS)`;document.head.appendChild(s);", injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(cssScript)
        */

        config.websiteDataStore = WKWebsiteDataStore.default()

        // 4. Persistence
        // Already handled by default store

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self

        // Spoof User Agent
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        // Content blocking - DISABLED to allow Discord to load
        // applyContentBlocking(to: config.userContentController)

        load()
    }

    func load() {
        // Load DM page directly to ensure chat list is available
        let url = URL(string: "https://discord.com/channels/@me")!
        webView.load(URLRequest(url: url))
    }

    // MARK: - API

    func sendMessage(_ text: String) {
        let safeText = text.replacingOccurrences(of: "\"", with: "\\\"")
        let js = "window.discordNativeAPI.sendMessage(\"\(safeText)\");"
        webView.evaluateJavaScript(js)
    }

    func selectChat(_ chatId: String) {
        print("[DiscordEngine] 🔄 Selecting chat: \(chatId)")

        // Update selectedChatId FIRST on main thread
        DispatchQueue.main.async {
            self.selectedChatId = chatId
            self.messages = [] // Clear messages when switching chats
            print("[DiscordEngine] ✅ selectedChatId updated to: \(chatId)")
            print("[DiscordEngine] 🗑️ Cleared messages for chat switch")
        }

        let js = "window.discordNativeAPI.selectChat('\(chatId)');"
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("[DiscordEngine] ❌ Error selecting chat: \(error)")
            } else {
                print("[DiscordEngine] ✅ Chat selection JS executed")
            }
        }
    }

    func loadChatList() {
        let js = "window.discordNativeAPI.loadChatList();"
        webView.evaluateJavaScript(js)
    }

    func loadMessages() {
        let js = "window.discordNativeAPI.loadMessages();"
        webView.evaluateJavaScript(js)
    }

    // MARK: - Delegate (Bridge)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Handle console messages first
        if message.name == "consoleLog" {
            if let msg = message.body as? String {
                print("🟢 [JS Console] \(msg)")
            }
            return
        }
        if message.name == "consoleWarn" {
            if let msg = message.body as? String {
                print("🟡 [JS Warning] \(msg)")
            }
            return
        }
        if message.name == "consoleError" {
            if let msg = message.body as? String {
                print("🔴 [JS Error] \(msg)")
            }
            return
        }

        // Handle bridge messages
        guard message.name == "discordNative",
              let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else {
            print("[DiscordEngine] ⚠️ Invalid message received")
            return
        }

        print("[DiscordEngine] 📨 Received message type: \(type)")

        switch type {
        case "chatList":
            handleChatList(dict)
        case "messageHistory":
            handleMessageHistory(dict)
        case "message":
            handleNewMessage(dict)
        default:
            print("[DiscordEngine] ⚠️ Unknown message type: \(type)")
            break
        }
    }

    private func handleChatList(_ dict: [String: Any]) {
        guard let chatsData = dict["chats"] as? [[String: Any]] else { return }

        var parsedChats: [Chat] = []
        for chatDict in chatsData {
            guard let id = chatDict["id"] as? String,
                  let name = chatDict["name"] as? String else { continue }

            let avatarUrlString = chatDict["avatarUrl"] as? String
            let avatarUrl = (avatarUrlString != nil && !avatarUrlString!.isEmpty) ? URL(string: avatarUrlString!) : nil

            let typeString = chatDict["type"] as? String ?? "DM"
            let chatType = ChatType(rawValue: typeString) ?? .dm

            let lastMessage = chatDict["lastMessage"] as? String

            let chat = Chat(id: id, name: name, avatarURL: avatarUrl, type: chatType, lastMessage: lastMessage)
            parsedChats.append(chat)
        }

        DispatchQueue.main.async {
            self.chats = parsedChats
            print("[DiscordEngine] Loaded \(parsedChats.count) chats")
        }
    }

    private func handleMessageHistory(_ dict: [String: Any]) {
        print("[DiscordEngine] 💬 Processing message history...")
        guard let channelId = dict["channelId"] as? String,
              let messagesData = dict["messages"] as? [[String: Any]] else {
            print("[DiscordEngine] ❌ Failed to parse message history data")
            return
        }

        print("[DiscordEngine] 📨 Message history for channel: \(channelId)")
        print("[DiscordEngine] 📨 Raw message count: \(messagesData.count)")
        print("[DiscordEngine] 🔍 Current selectedChatId: \(selectedChatId ?? "none")")

        // IMPORTANT: Update selectedChatId to match the loaded channel
        // This ensures the UI updates correctly
        if selectedChatId != channelId {
            print("[DiscordEngine] 🔄 Updating selectedChatId from \(selectedChatId ?? "none") to \(channelId)")
            selectedChatId = channelId
        }

        var parsedMessages: [Message] = []
        for msgDict in messagesData {
            if let msg = parseMessage(msgDict) {
                parsedMessages.append(msg)
            }
        }

        print("[DiscordEngine] ✅ Parsed \(parsedMessages.count) messages")
        DispatchQueue.main.async {
            // Clear existing messages and load history
            self.messages = parsedMessages
            print("[DiscordEngine] ✅ UI updated with \(parsedMessages.count) messages")
        }
    }

    private func handleNewMessage(_ dict: [String: Any]) {
        guard let msg = parseMessage(dict) else { return }

        // Filter by channel if we have a selection
        if let channelId = dict["channelId"] as? String,
           let selectedId = selectedChatId,
           channelId != selectedId {
            return // Ignore messages from other channels
        }

        DispatchQueue.main.async {
            if !self.messages.contains(msg) {
                self.messages.append(msg)
            }
        }
    }

    private func parseMessage(_ dict: [String: Any]) -> Message? {
        guard let id = dict["id"] as? String,
              let content = dict["content"] as? String,
              let author = dict["author"] as? String else { return nil }

        let avatarUrlString = dict["avatarUrl"] as? String
        let avatarUrl = (avatarUrlString != nil && !avatarUrlString!.isEmpty) ? URL(string: avatarUrlString!) : nil

        return Message(id: id, authorName: author, avatarURL: avatarUrl, content: content)
    }

    // MARK: - Navigation Delegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkLoginState()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        checkLoginState()
        decisionHandler(.allow)
    }

    private func checkLoginState() {
        if let url = webView.url?.absoluteString {
            // Discord app always redirects to /channels/... upon login
            if url.contains("/channels/") || url.contains("/app") {
                // If we are at the app screen, we assume logged in.
                // Note: "discord.com/app" redirects to login if not logged in, or channels if logged in.
                // A better check is if we are NOT on login page.
                if !url.contains("login") && !url.contains("register") {
                    if !isLoggedIn {
                        print("[DiscordEngine] ✅ Login detected! URL: \(url)")
                        DispatchQueue.main.async {
                            self.isLoggedIn = true
                            print("[DiscordEngine] 🎉 isLoggedIn set to TRUE")
                        }
                    } else {
                        print("[DiscordEngine] ℹ️ Already logged in, URL: \(url)")
                    }
                }
            }
        }
    }

    private func applyContentBlocking(to ucc: WKUserContentController) {
        let jsonRules = """
        [
            {
                "trigger": { "url-filter": ".*", "resource-type": ["image", "style-sheet", "font", "media"] },
                "action": { "type": "block" }
            }
        ]
        """

        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "HeadlessBlocker", encodedContentRuleList: jsonRules) { list, error in
            if let list = list {
                DispatchQueue.main.async {
                    ucc.add(list)
                    print("[DiscordEngine] Network Blocking Enabled.")
                }
            } else if let error = error {
                print("[DiscordEngine] Blocking Error: \(error)")
            }
        }
    }
}
