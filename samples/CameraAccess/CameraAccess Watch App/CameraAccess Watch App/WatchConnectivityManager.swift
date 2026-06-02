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

        if WCSession.default.isReachable {
            // Send the specific action the iOS app is listening for
            WCSession.default.sendMessage(["action": "toggle_live_mode"], replyHandler: { response in
                print("iOS app acknowledged live mode toggle: \(response)")
            }, errorHandler: { error in
                print("Error sending live mode toggle: \(error.localizedDescription)")
            })
        } else {
            print("iOS app not reachable")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Handle activation completion
    }
}
