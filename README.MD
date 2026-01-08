# Research Post-Mortem: Why a Native macOS Discord Client is a Dead End
This document serves as a record of our attempt to build "Vibecord" — a lightweight, native macOS client for Discord. We explored three distinct architectural approaches. Below are the results, technical bottlenecks, and reasons why we decided to archive the project.

TL;DR: Discord's architecture is hostile to third-party clients. Electron, despite its memory hunger, remains the most viable stable solution due to the heavy optimization of Discord's React codebase for the V8 engine (Chromium).

## Method 1: The WebKit Wrapper (WKWebView)
**Concept**: Wrap the official discord.com/app web client in a native macOS WKWebView. Apply aggressive optimizations via WKContentRuleList (blocking telemetry, tracking) and CSS injections to reduce visual load.

The Hypothesis: Since WebKit (Safari's engine) is native to macOS, it should be more memory-efficient and battery-friendly than Electron (which bundles a full Chromium instance + Node.js).

The Reality: * Result: ❌ FAILURE

- **Memory Usage**: ~1.5x higher than the official Electron app (1000MB+ vs 500MB).

- **Performance**: Noticeably worse than Chrome/Electron.

Technical Root Cause: Discord is a massive Single Page Application (SPA) built with React. Their codebase has been optimized for years specifically for V8 (Google's JS Engine), particularly its Garbage Collection strategies and JIT compilation. WebKit uses JavaScriptCore (JSC). React's heavy object allocation patterns interact poorly with JSC in this specific context, causing massive memory retention and slower execution. Essentially, we removed the "heavy" Electron shell but forced the "heavy" React app to run on an engine it wasn't tuned for.

## Method 2: The Hybrid "Headless" Bridge
**Concept**: Run WKWebView in the background (hidden/headless) to handle authentication, WebSocket connections, and data fetching. Inject JavaScript to intercept data and bridge it to Swift. Render the UI entirely natively using SwiftUI.

**The Hypothesis**: By disabling the rendering of the web page (display: none, content-visibility: hidden), we save GPU/CPU resources. We get the safety of a browser session but the speed of a native UI.

**The Reality**: * Result: ❌ TECHNICAL DEAD END

**Bottleneck 1**: The "React Wall". It is nearly impossible to reliably interact with the web app programmatically. Discord uses React's Virtual DOM. Simply running document.querySelector('input').value = 'text' does not update React's state. You have to hack internal React fiber nodes or simulate native trusted events, which is brittle.

**Bottleneck 2**: Obfuscation. To send messages programmatically without using the DOM, one must inject into Discord's Webpack modules (like Vencord/BetterDiscord do). However, Discord obfuscates this code. Maintaining a Swift-to-JS bridge that breaks every time Discord pushes an update is unsustainable.

**Bottleneck 3**: UI Duplication. Recreating the entire complex UI of Discord (channels, settings, permissions, roles, embeds) in SwiftUI is a monumental task with zero ROI if the data bridge is unstable.

## Method 3: The Full Native API Client
**Concept**: Reverse-engineer the Discord API (HTTP/WebSocket) and write a client from scratch (Swift or Rust), bypassing the browser entirely.

The Hypothesis: This would offer the ultimate performance: ~50MB RAM usage, native scrolling, and zero web bloat.

**The Reality**: * Result: ⛔ HIGH BAN RISK / UNSUSTAINABLE

**The Ban Hammer**: This falls under "Self-botting," which is strictly against Discord ToS. Discord employs sophisticated fingerprinting (TLS/JA3 signatures, behavior analysis). A Swift URLSession request looks nothing like a Chrome request. Mimicking a browser fingerprint perfectly is extremely difficult in Swift (easier in Rust/Tauri, but still an arms race).

**Feature Parity**: Implementing Voice and Video (WebRTC/UDP encryption) from scratch without documentation is a massive engineering challenge.

**Maintenance**: Any change in the API gateway could instantly brick the client or ban user accounts.

## Conclusion
We attempted to fix Electron's bloat, but we learned that the bloat comes from the application logic (React), not just the container.

WebKit chokes on Discord's React code.

Native implementation risks user bans.

Hybrid approaches combine the worst of both worlds (browser overhead + development complexity).

**Recommendation for users**: Use the iPad version of Discord on macOS (via PlayCover/Sideloadly). It runs on React Native, uses ~200MB RAM, and is an official client (zero ban risk).
