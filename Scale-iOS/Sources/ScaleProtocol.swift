import Foundation

// Adapted from ble-scale-sync (GPL-3.0), qn-scale/broadcast.ts and es-cs20m.ts.
// Manufacturer data includes the two-byte Bluetooth company identifier on iOS.
enum ScaleProtocol {
    static func useWriteResponse(hasAE: Bool, supportsResponse: Bool, supportsWithoutResponse: Bool) -> Bool {
        supportsResponse && (hasAE || !supportsWithoutResponse)
    }
    static func broadcast(_ data: Data) -> Double? {
        let b = Array(data)
        guard b.count >= 21, b[0] == 0xff, b[1] == 0xff,
              b[2] == 0xaa, b[3] == 0xbb, b[17] & 0x20 != 0 else { return nil }
        return valid(Double(Int(b[19]) | Int(b[20]) << 8) / 100)
    }
    static func valid(_ weight: Double) -> Double? {
        weight.isFinite && (0.5...300).contains(weight) ? weight : nil
    }
    static func frame(_ command: UInt8, _ payload: [UInt8]) -> Data {
        let bytes: [UInt8] = [0x55, 0xaa, command, UInt8(payload.count >> 8), UInt8(payload.count & 255)] + payload
        return Data(bytes + [bytes.reduce(0, &+)])
    }
    static func isFrame(_ data: Data) -> Bool {
        let b = Array(data)
        return b.count >= 6 && b[0] == 0x55 && b[1] == 0xaa &&
            b.count == (Int(b[3]) << 8 | Int(b[4])) + 6 && b.dropLast().reduce(0, &+) == b.last!
    }
    static func stableWeight(_ data: Data) -> Double? {
        let b = Array(data)
        guard isFrame(data), b.count >= 11, b[2] == 0x14, b[5] & 0x0f == 1 else { return nil }
        return valid(Double(Int(b[8]) << 8 | Int(b[9])) / 100)
    }
}

struct ScaleFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct PendingReading: Codable {
    let weight: Double
    let measuredAt: Date
    let athleteID: String
}

// Session state prevents an offline record or a power-off without live data
// from being mistaken for a new weigh-in.
struct RenphoSession {
    private var lastLiveWeight: Double?
    mutating func receive(_ data: Data) -> Double? {
        guard ScaleProtocol.isFrame(data) else { return nil }
        let b = Array(data)
        if b[2] == 0x11, b.count >= 7 {
            if b[5] == 1 { lastLiveWeight = nil }
            if b[5] == 0 { defer { lastLiveWeight = nil }; return lastLiveWeight }
        }
        if b[2] == 0x14, b.count >= 11 {
            lastLiveWeight = ScaleProtocol.valid(Double(Int(b[8]) << 8 | Int(b[9])) / 100)
            return ScaleProtocol.stableWeight(data)
        }
        return nil
    }
}

// Discovery is deliberately separate from packet decoding: a scale can first
// announce its name/services and publish manufacturer data only after waking.
struct ScaleAdvertisement {
    var name: String?
    var services: Set<String> = []
    var manufacturer = Data()

    mutating func merge(name: String?, services: [String], manufacturer: Data?) {
        if let name, !name.isEmpty { self.name = name }
        self.services.formUnion(services.map(Self.shortUUID))
        if let manufacturer, !manufacturer.isEmpty { self.manufacturer = manufacturer }
    }
    static func shortUUID(_ uuid: String) -> String {
        let value = uuid.lowercased().replacingOccurrences(of: "-", with: "")
        if value.count == 32, value.hasPrefix("0000"), value.hasSuffix("00001000800000805f9b34fb") {
            return String(value.dropFirst(4).prefix(4))
        }
        return value
    }
    var isBroadcast: Bool {
        manufacturer.count >= 4 && manufacturer.prefix(4).elementsEqual([0xff, 0xff, 0xaa, 0xbb])
    }
    var isCandidate: Bool {
        if isBroadcast { return true }
        let compact = (name ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        if compact.contains("renpho") || compact.contains("escs20m") || compact.contains("es32md") ||
            compact.contains("qnscale") || compact.hasPrefix("113360") { return true }
        // Shared vendor services are candidates only when the device has no name;
        // do not mislabel a named non-scale accessory as a Renpho.
        if services.contains("1a10") { return true }
        if compact.isEmpty && !services.isDisjoint(with: ["ffe0", "fff0", "ae00"]) { return true }
        return manufacturer.count == 14 && manufacturer.prefix(6).elementsEqual([0x10, 0x1a, 0, 4, 0, 0x31])
    }
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return "Unnamed scale"
    }
}

// Notifications can split a frame or contain multiple frames. Only deliver
// complete, checksum-validated frames; bound buffering on malformed input.
struct RenphoFrameStream {
    private var bytes: [UInt8] = []
    mutating func append(_ data: Data) -> [Data] {
        bytes += data
        if bytes.count > 4096 { bytes = Array(bytes.suffix(512)) }
        var frames: [Data] = []
        while bytes.count >= 2 {
            guard bytes[0] == 0x55, bytes[1] == 0xaa else { bytes.removeFirst(); continue }
            guard bytes.count >= 5 else { break }
            let length = (Int(bytes[3]) << 8 | Int(bytes[4])) + 6
            guard length <= 512 else { bytes.removeFirst(); continue }
            guard bytes.count >= length else { break }
            let frame = Data(bytes.prefix(length))
            if ScaleProtocol.isFrame(frame) { frames.append(frame); bytes.removeFirst(length) }
            else { bytes.removeFirst() }
        }
        return frames
    }
}
