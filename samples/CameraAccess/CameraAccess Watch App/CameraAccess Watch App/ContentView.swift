import SwiftUI

struct ContentView: View {
    @State private var isLiveModeEnabled = false
    @ObservedObject private var connectivity = WatchConnectivityManager.shared

    // The listening/thinking window is controlled by the phone (auto-stops on
    // silence), so the Watch reflects the phone's reported state instead of a
    // local toggle that would drift out of sync.
    private var isListening: Bool { connectivity.glassesState == .listening }
    private var isThinking: Bool { connectivity.glassesState == .thinking }
    private var isBusy: Bool { isListening || isThinking }

    private var statusIcon: String {
        if isListening { return "mic.fill" }
        if isThinking { return "ellipsis.circle.fill" }
        return "eye.fill"
    }
    private var statusColor: Color {
        if isListening { return .red }
        if isThinking { return .yellow }
        return isLiveModeEnabled ? .green : .white
    }
    private var statusText: String {
        if isListening { return "Listening…" }
        if isThinking { return "Thinking…" }
        return isLiveModeEnabled ? "Live ON" : "Ready"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Status icon + label — driven by the phone's reported state
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .symbolEffect(.pulse, isActive: isBusy)

                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(statusColor)
                }

                // Primary: voice query trigger. Disabled while a query is in
                // flight so a stray tap can't cancel mid-listen.
                Button(action: {
                    WatchConnectivityManager.shared.triggerVoiceQuery()
                }) {
                    Label("Ask AI", systemImage: "mic.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isBusy)

                // Secondary: live auto-analysis toggle
                Button(action: {
                    isLiveModeEnabled.toggle()
                    WatchConnectivityManager.shared.toggleLiveMode()
                }) {
                    Text(isLiveModeEnabled ? "Live: Stop" : "Live: Start")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .tint(isLiveModeEnabled ? .orange : .gray)

                // AI response — shown after each query
                if !connectivity.lastAIResponse.isEmpty {
                    Divider()

                    Text(connectivity.lastAIResponse)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
