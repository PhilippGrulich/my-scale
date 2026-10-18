import Foundation
import CoreBluetooth
import MyOpenScaleCore

/// High-level Bluetooth availability for the watch UI.
enum WatchBLEStatus: Equatable {
    case unknown
    case unsupported
    case unauthorized
    case poweredOff
    case scanning
    case idle

    var label: String {
        switch self {
        case .unknown: return String(localized: "Starting…")
        case .unsupported: return String(localized: "Bluetooth LE not supported on this Watch")
        case .unauthorized: return String(localized: "Bluetooth permission denied — enable in Settings")
        case .poweredOff: return String(localized: "Bluetooth is off")
        case .scanning: return String(localized: "Searching for scale…")
        case .idle: return String(localized: "Idle")
        }
    }
}

/// CoreBluetooth foreground scanner for watchOS.
///
/// watchOS does **not** honor `CBCentralManagerScanOptionAllowDuplicatesKey`
/// (adverts are coalesced to ~one `didDiscover` per peripheral) and has no
/// `bluetooth-central` background mode or state restoration. So instead of a
/// single always-on duplicate-allowing scan (the iOS `BLEScanner` approach),
/// this **duty-cycles** the scan: it periodically stops and restarts, which
/// clears CoreBluetooth's discovered-set so the next `didDiscover` delivers the
/// scale's *current* service data — effectively polling the changing broadcast.
///
/// Each observed frame feeds the shared, hardware-free `MeasurementFinalizer`,
/// whose settle/stale windows are advanced by a tick timer (so a stabilized
/// frame finalizes even between polls). Foreground-only by design.
final class WatchBLEScanner: NSObject {

    /// Body Composition service. watchOS strips the UUID prefix from the
    /// service-data value, so the parser sees the bare 13-byte payload.
    static let bodyCompositionService = CBUUID(string: "181B")

    private var central: CBCentralManager!
    private var finalizers: [UUID: MeasurementFinalizer] = [:]
    private let finalizerConfig: FinalizerConfig
    private var tickTimer: Timer?
    private var cycleTimer: Timer?
    /// True between `start()` and `stop()` — so scanning auto-resumes once
    /// Bluetooth transitions to `.poweredOn`.
    private var running = false

    // Callbacks (invoked on the main queue — delegate uses queue: nil).
    var onStatusChange: ((WatchBLEStatus) -> Void)?
    var onFrame: ((ParsedAdvertisement, UUID) -> Void)?
    var onReading: ((FinalizedReading, UUID) -> Void)?

    private(set) var status: WatchBLEStatus = .unknown {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    /// Watch-tuned finalizer config: the ~1.2s poll cadence is slower than iOS's
    /// duplicate stream, so allow a slightly longer settle and stale window.
    init(finalizerConfig: FinalizerConfig = FinalizerConfig(settle: 0.8,
                                                            cooldown: 10,
                                                            staleTimeout: 6,
                                                            weightToleranceKg: 0.1)) {
        self.finalizerConfig = finalizerConfig
        super.init()
        // No restore identifier: watchOS has no BLE state restoration.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Begin a fresh weigh-in scan. Idempotent; safe to call before Bluetooth is
    /// powered on (scanning starts once state becomes `.poweredOn`).
    func start() {
        running = true
        finalizers.removeAll()   // each weigh-in starts from a clean state machine
        if central.state == .poweredOn { beginCycling() }
    }

    func stop() {
        running = false
        if central.state == .poweredOn { central.stopScan() }
        stopCycleTimer()
        stopTickTimer()
        status = .idle
    }

    // MARK: - Scan duty cycle

    private func beginCycling() {
        status = .scanning
        restartScan()
        startTickTimer()
        startCycleTimer()
    }

    /// Stop then immediately restart the scan, forcing CoreBluetooth to re-deliver
    /// the scale's (updated) advertisement.
    private func restartScan() {
        guard central.state == .poweredOn, running else { return }
        central.stopScan()
        central.scanForPeripherals(withServices: [Self.bodyCompositionService], options: nil)
    }

    private func startCycleTimer() {
        stopCycleTimer()
        let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.restartScan()
        }
        RunLoop.main.add(timer, forMode: .common)
        cycleTimer = timer
    }

    private func stopCycleTimer() {
        cycleTimer?.invalidate()
        cycleTimer = nil
    }

    // MARK: - Tick

    /// Advance the finalizers' settle/stale windows when adverts pause between
    /// poll cycles.
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

extension WatchBLEScanner: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if running { beginCycling() }
        case .poweredOff:
            status = .poweredOff
            stopCycleTimer()
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
        onFrame?(parsed, id)

        if let reading = finalizer(for: id).ingest(parsed, at: now) {
            onReading?(reading, id)
        }
    }
}
