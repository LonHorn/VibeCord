import SwiftUI

struct ContentView: View {
    var body: some View {
        WebView(url: URL(string: "https://discord.com/app")!)
            // Ensure the window has a reasonable minimum size for desktop usage
            .frame(minWidth: 800, minHeight: 600)
            // Use full window content, ignoring safe areas often found in iOS or default macOS templates
            .edgesIgnoringSafeArea(.all)
    }
}
