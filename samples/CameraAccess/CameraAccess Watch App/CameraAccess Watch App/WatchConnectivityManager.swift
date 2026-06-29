import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    @Published var isLiveModeEnabled: Bool = false
    @Published var lastAIResponse: String = ""

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
    // nonisolated: WCSessionDelegate requirements are nonisolated; a @MainActor class
    // can't satisfy them otherwise under Swift 6. Bodies that touch main-actor state
    // hop via Task { @MainActor in }.

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let text = message["ai_response"] as? String {
                lastAIResponse = text
            }
        }
    }
}
