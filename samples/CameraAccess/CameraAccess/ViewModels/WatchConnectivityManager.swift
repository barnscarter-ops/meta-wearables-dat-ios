import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    var onLiveModeToggled: (() -> Void)?
    var onVoiceQueryTriggered: (() -> Void)?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func sendAIResponse(_ text: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["ai_response": text],
            replyHandler: nil,
            errorHandler: { error in
                print("⚠️ WatchConnectivityManager: failed to send AI response: \(error.localizedDescription)")
            }
        )
    }

    // Tells the Watch the glasses are now listening (so it can buzz + show "Listening…").
    func sendListeningState() { sendState("listening") }

    // Tells the Watch the question was captured and the AI is now working.
    func sendThinkingState() { sendState("thinking") }

    private func sendState(_ state: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["state": state],
            replyHandler: nil,
            errorHandler: { error in
                print("⚠️ WatchConnectivityManager: failed to send state \(state): \(error.localizedDescription)")
            }
        )
    }

    // Sends live mode state back to the Watch. Call after toggling isLiveModeEnabled.
    func sendLiveModeStatus(isEnabled: Bool) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["liveModeEnabled": isEnabled],
            replyHandler: nil,
            errorHandler: { error in
                print("⚠️ WatchConnectivityManager: failed to send live mode status: \(error.localizedDescription)")
            }
        )
    }

    // MARK: - WCSessionDelegate
    // nonisolated: WCSessionDelegate requirements are nonisolated; a @MainActor class
    // can't satisfy them otherwise under Swift 6. Bodies that touch main-actor state
    // hop via Task { @MainActor in }.

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        Task { @MainActor in
            switch action {
            case "toggle_live_mode": onLiveModeToggled?()
            case "voice_query":     onVoiceQueryTriggered?()
            default: break
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {}
    #endif
}
