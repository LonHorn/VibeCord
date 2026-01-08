import Foundation

struct DiscordJS {
    static let payload = """
    (function() {
        console.log("[DiscordNative] ========================================");
        console.log("[DiscordNative] Scraper Starting...");
        console.log("[DiscordNative] URL: " + window.location.href);
        console.log("[DiscordNative] ========================================");

        let currentChannelId = null;

        // --- Helper: Post to Swift ---
        function postToSwift(data) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.discordNative) {
                window.webkit.messageHandlers.discordNative.postMessage(data);
            }
        }

        // --- Helper: Extract Channel ID from URL ---
        function getCurrentChannelId() {
            // URL format: https://discord.com/channels/@me/123456789
            const match = window.location.pathname.match(/\\/channels\\/@me\\/(\\d+)/);
            return match ? match[1] : null;
        }

        // --- Helper: Scrape Chat List ---
        function scrapeChatList() {
            console.log('[DiscordNative] 🔍 Starting chat list scrape...');
            const chats = [];

            // Discord now uses dynamic UID in prefix: private-channels-uid_X___
            // So we need to use a more flexible selector
            const chatElements = document.querySelectorAll('[data-list-item-id^="private-channels-uid_"]');
            console.log('[DiscordNative] 🔍 Found ' + chatElements.length + ' private channel elements');

            // Also try people-list which contains actual DM channels
            const peopleListElements = document.querySelectorAll('[data-list-item-id^="people-list___"]');
            console.log('[DiscordNative] 🔍 Found ' + peopleListElements.length + ' people-list elements');

            // Process people-list (actual DM channels with users)
            peopleListElements.forEach(el => {
                const dataId = el.getAttribute('data-list-item-id');
                const channelId = dataId.replace('people-list___', '');

                // Skip if not a valid channel ID (should be numeric)
                if (!/^\\d+$/.test(channelId)) {
                    console.log('[DiscordNative] ⏭️ Skipping non-channel: ' + dataId);
                    return;
                }

                // Find name (username)
                const nameEl = el.querySelector('[class*="name"]');
                const name = nameEl ? nameEl.innerText : 'Unknown';

                // Find avatar
                const avatarImg = el.querySelector('img[src*="avatars"], img[src*="embed/avatars"]');
                const avatarUrl = avatarImg ? avatarImg.src : '';

                // People list is always DM (1-on-1)
                const type = 'DM';

                // Last message preview (if available)
                const previewEl = el.querySelector('[class*="subtext"], [class*="activity"]');
                const lastMessage = previewEl ? previewEl.innerText : '';

                chats.push({
                    id: channelId,
                    name: name,
                    avatarUrl: avatarUrl,
                    type: type,
                    lastMessage: lastMessage
                });
                console.log('[DiscordNative] 📝 Scraped DM: ' + name + ' (ID: ' + channelId + ')');
            });

            // Process private-channels-uid (navigation items like Friends, Nitro, etc.)
            // These are NOT actual chats, skip them for now
            // We could add them later for navigation purposes

            if (chats.length > 0) {
                console.log('[DiscordNative] ✅ Scraped ' + chats.length + ' chats total');
                console.log('[DiscordNative] 📤 Sending to Swift...');
                postToSwift({
                    type: 'chatList',
                    chats: chats
                });
                console.log('[DiscordNative] ✅ Sent successfully!');
            } else {
                console.error('[DiscordNative] ❌ NO CHATS FOUND!');
                console.log('[DiscordNative] 💡 Make sure you have DM conversations');

                // DEBUG: Show what we found
                console.log('[DiscordNative] 📊 Debug info:');
                console.log('[DiscordNative]   - private-channels-uid elements: ' + chatElements.length);
                console.log('[DiscordNative]   - people-list elements: ' + peopleListElements.length);
            }
        }

        // --- Helper: Scrape a Single Message Element ---
        function scrapeMessage(element) {
            // 1. Content
            let contentEl = element.querySelector('[id^="message-content-"]');
            let content = contentEl ? contentEl.innerText : '';

            // 2. Author & Avatar
            let avatarImg = element.querySelector('img[src*="avatars"]');
            let avatarUrl = avatarImg ? avatarImg.src : '';

            let usernameEl = element.querySelector('[id^="message-username-"]');
            let author = usernameEl ? usernameEl.innerText : 'Unknown';

            // 3. ID
            let id = element.id || 'msg-' + Date.now() + Math.random();

            // 4. Channel ID (from URL)
            let channelId = getCurrentChannelId();

            if (content || avatarUrl) {
                return {
                    type: 'message',
                    id: id,
                    author: author,
                    avatarUrl: avatarUrl,
                    content: content,
                    channelId: channelId
                };
            }
            return null;
        }

        // --- Helper: Load Existing Messages ---
        function loadExistingMessages() {
            console.log('[DiscordNative] 💬 Loading messages...');
            const channelId = getCurrentChannelId();
            console.log('[DiscordNative] Channel ID: ' + channelId);
            if (!channelId) {
                console.warn('[DiscordNative] ⚠️ No channel ID in URL');
                return;
            }

            const messages = [];
            const messageElements = document.querySelectorAll('[id^="chat-messages-"]');
            console.log('[DiscordNative] Found ' + messageElements.length + ' message elements');

            messageElements.forEach(el => {
                if (el.querySelector('[id^="message-content-"]')) {
                    let data = scrapeMessage(el);
                    if (data) {
                        messages.push(data);
                    }
                }
            });

            if (messages.length > 0) {
                console.log('[DiscordNative] ✅ Parsed ' + messages.length + ' messages');
                console.log('[DiscordNative] 📤 Sending message history...');
                postToSwift({
                    type: 'messageHistory',
                    channelId: channelId,
                    messages: messages
                });
                console.log('[DiscordNative] ✅ Message history sent!');
            } else {
                console.warn('[DiscordNative] ⚠️ No messages found for channel ' + channelId);
            }
        }

        // --- Core: Mutation Observer ---
        const observer = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                for (const node of mutation.addedNodes) {
                    if (node.nodeType === 1) { // Element
                        // Check for new messages
                        if (node.querySelector('[id^="message-content-"]')) {
                             let data = scrapeMessage(node);
                             if (data) {
                                 // Only send if it's for the current channel
                                 const currentChannel = getCurrentChannelId();
                                 if (!currentChannel || data.channelId === currentChannel) {
                                     postToSwift(data);
                                 }
                             }
                        }

                        // Check if chat list appeared/updated
                        if (node.querySelector('[data-list-item-id^="private-channels___"]')) {
                            setTimeout(scrapeChatList, 100);
                        }
                    }
                }
            }
        });

        // Start observing
        observer.observe(document.body, { childList: true, subtree: true });
        console.log('[DiscordNative] Observer attached.');

        // --- Core: API for Swift ---
        window.discordNativeAPI = {
            sendMessage: function(text) {
                console.log('[DiscordNative] 📤 Attempting to send message: ' + text);

                // Strategy 1: Use Discord's internal API
                try {
                    // Discord uses webpack modules, we need to find the right one
                    // Try to find MessageQueue or similar module

                    // Get current channel ID
                    const channelId = getCurrentChannelId();
                    if (!channelId) {
                        console.error('[DiscordNative] ❌ No channel ID found');
                        return;
                    }

                    console.log('[DiscordNative] 📍 Sending to channel: ' + channelId);

                    // Try to access Discord's internal modules via webpack
                    // This is a common pattern used by Discord mods like BetterDiscord
                    if (window.webpackChunkdiscord_app) {
                        console.log('[DiscordNative] 🔍 Found webpack, searching for MessageQueue...');

                        // Push a dummy chunk to extract all modules
                        window.webpackChunkdiscord_app.push([[Math.random()], {}, (req) => {
                            // Find the MessageQueue or sendMessage module
                            const cache = req.c;
                            for (const id in cache) {
                                const module = cache[id];
                                if (module && module.exports) {
                                    const exp = module.exports;

                                    // Look for sendMessage function in exports
                                    if (exp.sendMessage && typeof exp.sendMessage === 'function') {
                                        try {
                                            console.log('[DiscordNative] ✅ Found sendMessage in module ' + id);
                                            exp.sendMessage(channelId, {
                                                content: text,
                                                tts: false,
                                                invalidEmojis: [],
                                                validNonShortcutEmojis: []
                                            });
                                            console.log('[DiscordNative] ✅ Message sent via Discord API!');
                                            return;
                                        } catch (e) {
                                            console.log('[DiscordNative] ⚠️ Module ' + id + ' failed: ' + e.message);
                                        }
                                    }
                                }
                            }
                        }]);
                    }

                    console.warn('[DiscordNative] ⚠️ Could not find Discord API, falling back to UI interaction...');
                } catch (e) {
                    console.error('[DiscordNative] ❌ Discord API error: ' + e.message);
                }

                // Strategy 2: UI-based sending (fallback)
                let textbox = document.querySelector('[role="textbox"][data-slate-editor="true"]');
                if (!textbox) {
                    textbox = document.querySelector('div[role="textbox"]');
                }
                if (!textbox) {
                    textbox = document.querySelector('[data-slate-editor="true"]');
                }

                if (!textbox) {
                    console.error('[DiscordNative] ❌ Textbox not found.');
                    return;
                }

                console.log('[DiscordNative] ✅ Found textbox, using UI fallback');
                textbox.focus();

                const paragraph = textbox.querySelector('p, div[data-slate-node="element"]');
                if (paragraph) {
                    paragraph.textContent = text;

                    const inputEvent = new InputEvent('input', {
                        bubbles: true,
                        cancelable: true,
                        inputType: 'insertText',
                        data: text
                    });
                    textbox.dispatchEvent(inputEvent);

                    console.log('[DiscordNative] ✅ Text inserted');

                    // Try to trigger actual send via Enter key with proper timing
                    setTimeout(() => {
                        // Simulate real user Enter key press
                        const events = ['keydown', 'keypress', 'keyup'];
                        events.forEach(eventType => {
                            const event = new KeyboardEvent(eventType, {
                                key: 'Enter',
                                code: 'Enter',
                                keyCode: 13,
                                which: 13,
                                charCode: eventType === 'keypress' ? 13 : 0,
                                bubbles: true,
                                cancelable: true,
                                composed: true,
                                view: window
                            });
                            textbox.dispatchEvent(event);
                        });
                        console.log('[DiscordNative] ✅ Enter key sequence dispatched');
                    }, 200);
                } else {
                    console.error('[DiscordNative] ❌ Could not find paragraph in textbox');
                }
            },

            selectChat: function(channelId) {
                console.log('[DiscordNative] 🔄 Attempting to select chat: ' + channelId);

                // Find and click the chat element in people-list
                const chatEl = document.querySelector('[data-list-item-id="people-list___' + channelId + '"]');
                if (chatEl) {
                    console.log('[DiscordNative] ✅ Found chat element, clicking...');
                    chatEl.click();
                    console.log('[DiscordNative] ✅ Chat clicked: ' + channelId);

                    // Load messages after a short delay
                    setTimeout(() => {
                        currentChannelId = channelId;
                        loadExistingMessages();
                    }, 500);
                } else {
                    console.error('[DiscordNative] ❌ Chat not found: ' + channelId);
                    console.log('[DiscordNative] 🔍 Tried selector: [data-list-item-id="people-list___' + channelId + '"]');

                    // DEBUG: Show what elements we have
                    const allPeopleList = document.querySelectorAll('[data-list-item-id^="people-list___"]');
                    console.log('[DiscordNative] 📊 Available people-list elements: ' + allPeopleList.length);
                }
            },

            loadChatList: function() {
                scrapeChatList();
            },

            loadMessages: function() {
                loadExistingMessages();
            }
        };

        // Auto-load chat list and messages after page loads
        setTimeout(() => {
            scrapeChatList();
            currentChannelId = getCurrentChannelId();
            if (currentChannelId) {
                loadExistingMessages();
            }
        }, 5000); // Increased to 5 seconds to allow Discord to fully load
    })();
    """
}
