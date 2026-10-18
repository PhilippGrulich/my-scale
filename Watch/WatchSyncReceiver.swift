import Foundation
import WatchConnectivity

/// Watch side of the phone→watch sync: receives the latest `WatchSyncPayload`
/// (goal, name, Mochi switch) and keeps it for the next launch.
final class WatchSyncReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchSyncReceiver()

    /// Called on the main queue whenever a new payload arrives.
    var onChange: ((WatchSyncPayload) -> Void)?

    private static let storeKey = "myopenscale.watch.sync.v1"

    /// The last payload the phone sent (nil before the first sync).
    static var stored: WatchSyncPayload? {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return nil }
        return try? JSONDecoder().decode(WatchSyncPayload.self, from: data)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func apply(_ context: [String: Any]) {
        guard let payload = WatchSyncPayload(dictionary: context) else { return }
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
        DispatchQueue.main.async { self.onChange?(payload) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}
