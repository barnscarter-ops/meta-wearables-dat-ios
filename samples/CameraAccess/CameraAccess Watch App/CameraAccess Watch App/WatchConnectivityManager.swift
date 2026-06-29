import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    @Published var isLiveModeEnabled: Bool = false

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func toggleLiveMode() {
        isLiveModeEnabled.toggle()
        sendAction("toggle_live_mode")
    }

    func triggerVoiceQuery() {
        sendAction("voice_query")
    }

    private func sendAction(_ action: String) {
        guard WCSession.default.isReachable else {
            print("⚠️ WatchConnectivityManager: iOS app not reachable")
            return
        }
        WCSession.default.sendMessage(["action": action], replyHandler: nil) { error in
            print("⚠️ WatchConnectivityManager: failed to send \(action): \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Handle activation completion
    }
}
