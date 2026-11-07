import CoreBluetooth
import Foundation

@MainActor final class ScaleBluetooth: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    struct Device: Identifiable {
        let id: UUID
        let name: String
        let peripheral: CBPeripheral
        var broadcast: Bool
    }
    @Published var devices: [Device] = []
    @Published var connectionDetails = ""
    var onLiveWeight: ((Double) -> Void)?
    private var characteristicIDs: Set<String> = []
    private var notificationCount = 0
    private var connectionTimer: Timer?
    private var stream = RenphoFrameStream()
    private func record(_ message: String) {
        let lines = (connectionDetails.components(separatedBy: "\n") + [message]).filter { !$0.isEmpty }
        connectionDetails = lines.suffix(30).joined(separator: "\n")
    }
    var onStatus: ((String) -> Void)?
    var onWeight: ((Double) -> Void)?
    var onError: ((String) -> Void)?
    private var central: CBCentralManager!
    private var active = false
    private var selected: CBPeripheral?
    private var selectedBroadcast = false
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var awaitingServices = 0
    private var hasAE = false
    private var legacyRepeated = false
    private var handshakeSent = false
    private var writeQueue: [Data] = []
    private var timer: Timer?
    private var session = RenphoSession()
    private var advertisements: [UUID: ScaleAdvertisement] = [:]
    private var seen: Set<UUID> = []
    private var scanID = UUID()
    var height = 170.0
    var age = 30
    var male = true

    override init() { super.init() }
    func start() {
        stop()
        devices = []
        advertisements = [:]; seen = []
        connectionDetails = "Scanning"; notificationCount = 0
        active = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { centralManagerDidUpdateState(central) }
        timer = Timer.scheduledTimer(withTimeInterval: 150, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let message = self.selected == nil
                    ? "No scale selected. Detected \(self.seen.count) Bluetooth devices and \(self.devices.count) possible scales. Keep the scale awake and close Renpho and Scale on your Mac, then retry."
                    : "No stable weight received. Wake the scale, move closer and close Renpho and Scale on your Mac."
                self.fail(message)
            }
        }
    }
    func stop() {
        active = false
        scanID = UUID()
        timer?.invalidate(); timer = nil
        connectionTimer?.invalidate(); connectionTimer = nil
        characteristicIDs = []; stream = RenphoFrameStream()
        central?.stopScan()
        if let selected { central?.cancelPeripheralConnection(selected) }
        selected = nil
        writeCharacteristic = nil; notifyCharacteristic = nil
        awaitingServices = 0; hasAE = false; handshakeSent = false; legacyRepeated = false
        writeQueue = []
        session = RenphoSession()
    }
    private func fail(_ message: String) { guard active else { return }; record(message); stop(); onError?(message) }
    private func finish(_ weight: Double) { guard active else { return }; stop(); onWeight?(weight) }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard active else { return }
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            onStatus?("Wake your Renpho, then select it below.")
        case .poweredOff: fail("Turn on Bluetooth in Settings, then try again.")
        case .unauthorized: fail("Allow Bluetooth access for Scale in iPhone Settings.")
        case .unsupported: fail("Bluetooth is unavailable. Use a real iPhone for a weigh-in.")
        default: break
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard active else { return }
        seen.insert(peripheral.identifier)
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []) +
            (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        var advert = advertisements[peripheral.identifier] ?? ScaleAdvertisement()
        advert.merge(name: name, services: services.map(\.uuidString), manufacturer: data)
        advertisements[peripheral.identifier] = advert
        guard advert.isCandidate else { return }
        if selected == nil {
            let device = Device(id: peripheral.identifier, name: advert.displayName,
                                peripheral: peripheral, broadcast: advert.isBroadcast)
            if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
            else { devices.append(device) }
        }
        // Decode only the current advertisement, never cached stable data from
        // before the user selected the device.
        if selected?.identifier == peripheral.identifier, advert.isBroadcast {
            selectedBroadcast = true
            if let data, let weight = ScaleProtocol.broadcast(data) { finish(weight) }
        }
    }

    func select(_ device: Device) {
        guard active, selected == nil else { return }
        selected = device.peripheral
        selectedBroadcast = device.broadcast
        devices = []
        record(device.broadcast ? "Selected broadcast scale" : "Selected scale; preparing connection")
        onStatus?(device.broadcast ? "Step on the scale and stand still. Keep Scale open." : "Connecting to the scale. Keep it awake and wait before stepping on.")
        if !device.broadcast {
            device.peripheral.delegate = self
            let token = scanID
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.active, self.scanID == token, self.selected === device.peripheral,
                      !self.selectedBroadcast else { return }
                self.central.stopScan()
                self.record("Connecting")
                self.central.connect(device.peripheral)
                self.connectionTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.scanID == token else { return }
                        self.fail("The scale did not connect. Close Renpho and Scale on your Mac, wake the scale and retry.")
                    }
                }
            }
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active, peripheral == selected else { return }
        connectionTimer?.invalidate(); connectionTimer = nil
        record("Connected; discovering services")
        onStatus?("Scale connected. Preparing the weight reader…")
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == selected else { return }
        fail("Could not connect. Close Renpho and Scale on your Mac, then retry.")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == selected else { return }
        fail("The scale disconnected before a stable reading arrived. Please retry.")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard active, peripheral == selected else { return }
        guard error == nil, let services = peripheral.services, !services.isEmpty else { fail("Could not read the scale's Bluetooth services."); return }
        record("Services: " + services.map { $0.uuid.uuidString }.joined(separator: ", "))
        awaitingServices = services.count
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard active, peripheral == selected else { return }
        guard error == nil else { fail("Could not read the scale's Bluetooth characteristics."); return }
        record("Characteristics: " + (service.characteristics ?? []).map { $0.uuid.uuidString }.joined(separator: ", "))
        for characteristic in service.characteristics ?? [] {
            characteristicIDs.insert(ScaleAdvertisement.shortUUID(characteristic.uuid.uuidString))
            if characteristic.uuid == CBUUID(string: "2A10") { notifyCharacteristic = characteristic }
            if characteristic.uuid == CBUUID(string: "2A11") { writeCharacteristic = characteristic }
        }
        awaitingServices -= 1
        guard awaitingServices == 0 else { return }
        hasAE = characteristicIDs.contains("ae01") && characteristicIDs.contains("ae02")
        guard let notifyCharacteristic, let writeCharacteristic,
              (notifyCharacteristic.properties.contains(.notify) || notifyCharacteristic.properties.contains(.indicate)),
              writeCharacteristic.properties.contains(.write) || writeCharacteristic.properties.contains(.writeWithoutResponse) else {
            fail("This Renpho revision is not supported yet. Supported: AABB broadcast and 1A10 ES-CS20M."); return
        }
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard active, peripheral == selected else { return }
        guard error == nil, characteristic.isNotifying else { fail("Could not subscribe to the scale."); return }
        record(hasAE ? "Subscribed; waiting for guest handshake" : "Subscribed; starting legacy reader")
        onStatus?("Scale connected. Step on the scale and stand still. Keep Scale open.")
        if !hasAE { enqueue([ScaleProtocol.frame(0x90, [1, 0, 0, 0])]) }
    }
    private func enqueue(_ frames: [Data]) {
        let idle = writeQueue.isEmpty
        writeQueue += frames
        if idle { sendNext() }
    }
    private func sendNext() {
        guard active, let selected, let characteristic = writeCharacteristic, let frame = writeQueue.first else { return }
        // The legacy ES-CS20M uses write-without-response even if both
        // properties are advertised. AE01/AE02 revisions use acknowledged writes.
        if ScaleProtocol.useWriteResponse(hasAE: hasAE,
            supportsResponse: characteristic.properties.contains(.write),
            supportsWithoutResponse: characteristic.properties.contains(.writeWithoutResponse)) {
            selected.writeValue(frame, for: characteristic, type: .withResponse)
        } else if selected.canSendWriteWithoutResponse {
            selected.writeValue(frame, for: characteristic, type: .withoutResponse)
            writeQueue.removeFirst(); sendNext()
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { if peripheral == selected { sendNext() } }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active, peripheral == selected else { return }
        guard error == nil else { fail("The scale refused a Bluetooth command. Please retry."); return }
        if !writeQueue.isEmpty { writeQueue.removeFirst() }
        sendNext()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active, peripheral == selected else { return }
        guard error == nil, let data = characteristic.value else { fail("Could not read the scale."); return }
        notificationCount += 1
        if notificationCount <= 5 {
            record("Notification \(notificationCount): \(data.count) bytes, header " + data.prefix(3).map { String(format: "%02X", $0) }.joined(separator: " "))
        }
        for frame in stream.append(data) { consume(frame) }
    }
    private func consume(_ data: Data) {
        guard active else { return }
        let b = Array(data)
        if b[2] == 0x11, b.count >= 8, b[5] == 1 {
            if hasAE, !handshakeSent {
                handshakeSent = true
                enqueue(guestHandshake(unit: (1...4).contains(b[6]) ? b[6] : 1))
            } else if !hasAE, !legacyRepeated {
                legacyRepeated = true
                enqueue([ScaleProtocol.frame(0x90, [1, 0, 0, 0])])
            }
        }
        if b[2] == 0x14, b.count >= 11,
           let weight = ScaleProtocol.valid(Double(Int(b[8]) << 8 | Int(b[9])) / 100) {
            onLiveWeight?(weight)
            onStatus?("Receiving weight. Stand still until the reading is stable.")
        }
        if let weight = session.receive(data) { finish(weight) }
    }
    private func guestHandshake(unit: UInt8) -> [Data] {
        let now = Date()
        let seconds = UInt64(now.timeIntervalSince1970)
        let time = (0..<6).reversed().map { UInt8(truncatingIfNeeded: seconds >> ($0 * 8)) }
        let offset = TimeZone.current.secondsFromGMT(for: now) / 3600
        let year = Calendar.current.component(.year, from: now) - age
        let h = Int(height * 10)
        // Guest slot 9 only; preserve registered users and measuring mode.
        let profile: [UInt8] = [male ? 0x19 : 0x29, UInt8(year >> 8), UInt8(year & 255), 1, 1,
                               UInt8(h >> 8), UInt8(h & 255), 0, 0, 0x1b, 0x58, 0xaa, 0xff, 0x05]
        return [ScaleProtocol.frame(0x91, [1]),
                ScaleProtocol.frame(0x97, [1] + time + [offset < 0 ? 1 : 0, UInt8(abs(offset))]),
                ScaleProtocol.frame(0x96, profile), ScaleProtocol.frame(0x90, [unit, 0, 0, 0])]
    }
}
