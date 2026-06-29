import Foundation
import CoreBluetooth
import MiScaleCore

/// Foreground-only CoreBluetooth wrapper. Filters on the Body Composition
/// service (0x181B), parses each advertisement, and drives a per-peripheral
/// `MeasurementFinalizer`. Pure decision logic lives in MiScaleCore; this class
/// only bridges CoreBluetooth callbacks and a tick timer into it.
final class BLEScanner: NSObject, ObservableObject {

    static let serviceUUID = CBUUID(string: "181B")

    @Published private(set) var statusText: String = "Starting…"
    @Published private(set) var isScanning: Bool = false

    /// Called on the main queue when a weigh-in finalizes. Carries the finalized
    /// reading and the raw service-data bytes of the finalizing frame.
    var onReading: ((FinalizedReading, Data) -> Void)?

    private var central: CBCentralManager!
    private var finalizers: [UUID: MeasurementFinalizer] = [:]
    private var lastData: [UUID: Data] = [:]
    private var tickTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        guard central.state == .poweredOn, !isScanning else { return }
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        statusText = "Scanning for scale…"
        scheduleTick()
    }

    func stop() {
        central.stopScan()
        isScanning = false
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollTick()
        }
    }

    private func pollTick() {
        let now = Date()
        for (id, finalizer) in finalizers {
            if let reading = finalizer.tick(at: now), let data = lastData[id] {
                onReading?(reading, data)
            }
        }
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusText = "Bluetooth ready"
            start()
        case .poweredOff:
            statusText = "Bluetooth is off"
            isScanning = false
        case .unauthorized:
            statusText = "Bluetooth permission denied"
        case .unsupported:
            statusText = "Bluetooth unavailable on this device"
        default:
            statusText = "Bluetooth unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let data = serviceData[Self.serviceUUID],
              let adv = AdvertisementParser.parse(data) else { return }

        let id = peripheral.identifier
        lastData[id] = data
        let finalizer = finalizers[id] ?? {
            let new = MeasurementFinalizer()
            finalizers[id] = new
            return new
        }()

        if let reading = finalizer.ingest(adv, at: Date()) {
            onReading?(reading, data)
        }
    }
}
