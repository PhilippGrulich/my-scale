import Foundation
import CoreBluetooth
import MyOpenScaleCore

/// A single observed advertisement frame, surfaced to the UI for live debugging.
struct ObservedFrame: Identifiable {
    let id = UUID()
    let peripheralID: UUID
    let rssi: Int
    let receivedAt: Date
    let parsed: ParsedAdvertisement
    let rawHex: String
}

/// High-level Bluetooth availability for the UI.
enum BLEStatus: Equatable {
    case unknown
    case unsupported
    case unauthorized
    case poweredOff
    case scanning
    case idle

    var label: String {
        switch self {
        case .unknown: return "Starting…"
        case .unsupported: return "Bluetooth LE not supported on this device"
        case .unauthorized: return "Bluetooth permission denied — enable in Settings"
        case .poweredOff: return "Bluetooth is off"
        case .scanning: return "Scanning for scale…"
        case .idle: return "Idle"
        }
    }
}

/// CoreBluetooth foreground scanner (plan §3 / M3b).
///
/// Scans for the Body Composition service (0x181B) with duplicates allowed,
/// parses each frame's service data, and drives a per-peripheral
/// `MeasurementFinalizer`. Finalized weigh-ins are delivered via `onReading`.
///
/// Delegate callbacks run on the main queue (`queue: nil`) so publishing to the
/// `@MainActor` `AppModel` needs no extra hops. Foreground-only by design —
/// background BLE / state restoration is the v2 hook point (plan §3).
final class BLEScanner: NSObject {

    /// Body Composition service. iOS strips the UUID prefix from the service-data
    /// value, so the parser sees the bare 13-byte payload (plan §1).
    static let bodyCompositionService = CBUUID(string: "181B")

    /// Stable identifier so iOS can preserve/restore our central manager (and its
    /// scan) across app termination — enabling best-effort background relaunch.
    private static let restoreIdentifier = "com.philippgrulich.myopenscale.central"

    private var central: CBCentralManager!
    private var finalizers: [UUID: MeasurementFinalizer] = [:]
    private var tickTimer: Timer?
    private let finalizerConfig: FinalizerConfig

    // Callbacks (set by AppModel; invoked on the main queue).
    var onStatusChange: ((BLEStatus) -> Void)?
    var onFrame: ((ObservedFrame) -> Void)?
    var onReading: ((FinalizedReading, UUID) -> Void)?

    private(set) var status: BLEStatus = .unknown {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    init(finalizerConfig: FinalizerConfig = FinalizerConfig()) {
        self.finalizerConfig = finalizerConfig
        super.init()
        // queue: nil → delegate callbacks arrive on the main queue.
        // Restore identifier opts into state preservation/restoration so the
        // system can relaunch us in the background to keep scanning (best-effort;
        // requires the bluetooth-central background mode).
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
        )
    }

    func start() {
        guard central.state == .poweredOn else { return }
        // On a restoration relaunch the system may already be scanning; only
        // (re)issue the scan if it isn't, but always (re)arm the tick timer so
        // the finalizers' settle/stale/cooldown still advance. startTickTimer()
        // is idempotent (it stops any existing timer first).
        if !central.isScanning {
            central.scanForPeripherals(
                withServices: [Self.bodyCompositionService],
                // Required: otherwise iOS coalesces adverts and we miss the
                // stabilized frame (plan §3).
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
        status = .scanning
        startTickTimer()
    }

    func stop() {
        if central.state == .poweredOn { central.stopScan() }
        stopTickTimer()
        status = .idle
    }

    // MARK: - Tick

    /// Drive the finalizers' settle/stale/cooldown windows when adverts pause.
    private func startTickTimer() {
        stopTickTimer()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.tickAll()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tickAll() {
        let now = Date()
        for (peripheralID, finalizer) in finalizers {
            if let reading = finalizer.tick(at: now) {
                onReading?(reading, peripheralID)
            }
        }
    }

    private func finalizer(for id: UUID) -> MeasurementFinalizer {
        if let existing = finalizers[id] { return existing }
        let made = MeasurementFinalizer(config: finalizerConfig)
        finalizers[id] = made
        return made
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEScanner: CBCentralManagerDelegate {

    /// Called when iOS relaunches the app (e.g. in the background) and restores
    /// our central manager. We hold no connections — scanning resumes via
    /// `centralManagerDidUpdateState` → `start()` once state is `.poweredOn`.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // No-op: ad-only scanner, nothing to reattach. Restoration's value is the
        // background relaunch itself.
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            start()
        case .poweredOff:
            status = .poweredOff
            stopTickTimer()
        case .unauthorized:
            status = .unauthorized
        case .unsupported:
            status = .unsupported
        default:
            status = .unknown
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard
            let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
            let payload = serviceData[Self.bodyCompositionService],
            let parsed = AdvertisementParser.parse(payload)
        else { return }

        let id = peripheral.identifier
        let now = Date()
        let frame = ObservedFrame(
            peripheralID: id,
            rssi: RSSI.intValue,
            receivedAt: now,
            parsed: parsed,
            rawHex: payload.map { String(format: "%02x", $0) }.joined()
        )
        onFrame?(frame)

        if let reading = finalizer(for: id).ingest(parsed, at: now) {
            onReading?(reading, id)
        }
    }
}
