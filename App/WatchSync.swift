import Foundation
import WatchConnectivity

/// Phone side of the watch sync: pushes the latest `WatchSyncPayload` as the
/// WatchConnectivity application context (the system delivers only the newest
/// one, even if the watch app isn't running).
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    private var pending: WatchSyncPayload?
    private var lastSent: WatchSyncPayload?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send if it changed; queued until the session is activated.
    func push(_ payload: WatchSyncPayload) {
        guard WCSession.isSupported(), payload != lastSent else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { pending = payload; return }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(payload.dictionary)
            lastSent = payload
        } catch {
            pending = payload
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated, let pending else { return }
        self.pending = nil
        DispatchQueue.main.async { self.push(pending) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another watch: re-activate so the new one gets the context.
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        // Watch app just got installed: send the current state.
        if let lastSent { self.lastSent = nil; DispatchQueue.main.async { self.push(lastSent) } }
    }
}
