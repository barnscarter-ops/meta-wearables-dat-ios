import SwiftUI

struct ContentView: View {
    @State private var isLiveModeEnabled = false
    @State private var isRecording = false
    @ObservedObject private var connectivity = WatchConnectivityManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Status icon + label
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "mic.fill" : "eye.fill")
                        .foregroundColor(isRecording ? .red : (isLiveModeEnabled ? .green : .gray))
                        .symbolEffect(.pulse, isActive: isRecording)

                    Text(isRecording ? "Listening..." : (isLiveModeEnabled ? "Live ON" : "Ready"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(isRecording ? .red : (isLiveModeEnabled ? .green : .white))
                }

                // Primary: voice query trigger
                Button(action: {
                    isRecording.toggle()
                    WatchConnectivityManager.shared.triggerVoiceQuery()
                }) {
                    Label(isRecording ? "Stop" : "Ask AI", systemImage: isRecording ? "stop.fill" : "mic.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? .red : .blue)

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
