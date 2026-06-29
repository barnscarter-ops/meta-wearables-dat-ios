import SwiftUI

struct ContentView: View {
    @State private var isLiveModeEnabled = false
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isRecording ? "mic.fill" : "eye.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundColor(isRecording ? .red : (isLiveModeEnabled ? .green : .gray))
                .symbolEffect(.pulse, isActive: isRecording)

            Text(isRecording ? "Listening..." : (isLiveModeEnabled ? "Live ON" : "Ready"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(isRecording ? .red : (isLiveModeEnabled ? .green : .white))

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
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
