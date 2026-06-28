import SwiftUI

struct ContentView: View {
    @State private var isLiveModeEnabled = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "eye.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(isLiveModeEnabled ? .green : .gray)
                .opacity(isLiveModeEnabled ? 1 : 0.5)

            Text(isLiveModeEnabled ? "GPT LIVE" : "GPT IDLE")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(isLiveModeEnabled ? .green : .white)

            Button(action: {
                isLiveModeEnabled.toggle()
                WatchConnectivityManager.shared.toggleLiveMode()
            }) {
                Text(isLiveModeEnabled ? "Stop Analysis" : "Start Live Chat")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(isLiveModeEnabled ? .red : .blue)
            .cornerRadius(12)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
