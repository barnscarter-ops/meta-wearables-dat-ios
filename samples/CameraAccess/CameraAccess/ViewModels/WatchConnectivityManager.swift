import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    var onLiveModeToggled: (() -> Void)?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let action = message["action"] as? String, action == "toggle_live_mode" {
            Task { @MainActor in
                onLiveModeToggled?()
            }
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
    #endif
}
