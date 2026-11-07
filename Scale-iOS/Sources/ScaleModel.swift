import SwiftUI

@MainActor final class ScaleModel: ObservableObject {
    @Published var athleteID = UserDefaults.standard.string(forKey: "athleteID") ?? ""
    @Published var weight: Double?
    @Published var bodyFat: Double?
    @Published var title = "Ready to weigh in"
    @Published var message = "Wake your scale and start a weigh-in. Sharing is optional."
    @Published var busy = false
    @Published var scanning = false
    @Published var verified = false
    @Published var pending: PendingReading?
    @Published var settingsPresented = false
    @Published var shareConfirmationPresented = false
    private let uploader: ((PendingReading) async throws -> Void)?
    let bluetooth = ScaleBluetooth()
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let pendingURL: URL

    init(storageDirectory: URL? = nil, uploader: ((PendingReading) async throws -> Void)? = nil) {
        self.uploader = uploader
        let directory = storageDirectory ?? URL.applicationSupportDirectory.appendingPathComponent("Scale", isDirectory: true)
        pendingURL = directory.appendingPathComponent("pending.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: pendingURL.path) {
                pending = try JSONDecoder().decode(PendingReading.self, from: Data(contentsOf: pendingURL))
                weight = pending?.weight
                bodyFat = pending?.bodyFat
                title = "Weight saved on iPhone"
                message = "Not shared in this session. You can choose to share this saved weigh-in."
            }
        } catch { title = "Could not restore weigh-in"; message = error.localizedDescription }
        bluetooth.onStatus = { [weak self] text in
            self?.message = text
            self?.title = text.hasPrefix("Wake") ? "Looking for your Renpho" : "Weigh-in in progress"
        }
        bluetooth.onLiveWeight = { [weak self] value in self?.weight = value }
        bluetooth.onError = { [weak self] text in self?.fail(text) }
        bluetooth.onWeight = { [weak self] value in self?.received(value) }
    }
    var client: IntervalsClient { get throws { IntervalsClient(athleteID: athleteID, key: try KeychainStore.read()) } }
    func start() {
        guard !busy, pending == nil else { return }
        verified = false; weight = nil; bodyFat = nil; busy = true; scanning = true
        title = "Looking for your Renpho"
        bluetooth.height = UserDefaults.standard.double(forKey: "height") == 0 ? 170 : UserDefaults.standard.double(forKey: "height")
        bluetooth.age = UserDefaults.standard.object(forKey: "age") == nil ? 30 : UserDefaults.standard.integer(forKey: "age")
        bluetooth.male = UserDefaults.standard.string(forKey: "sex") != "female"
        UIApplication.shared.isIdleTimerDisabled = true
        bluetooth.start()
    }
    private func received(_ value: Double) {
        scanning = false
        UIApplication.shared.isIdleTimerDisabled = false
        weight = value
        bodyFat = UserDefaults.standard.bool(forKey: "estimateBodyFat")
            ? ScaleProtocol.estimatedBodyFat(weight: value, height: bluetooth.height, age: bluetooth.age, male: bluetooth.male)
            : nil
        let reading = PendingReading(weight: value, measuredAt: Date(), athleteID: athleteID, bodyFat: bodyFat)
        pending = reading
        do {
            try persist(reading)
            busy = false
            verified = false
            title = "Weigh-in complete"
            message = "Saved on your iPhone. Not shared with Intervals.icu."
            shareConfirmationPresented = true
        } catch { fail("Weight received, but it could not be saved locally. Keep Scale open and try sharing again.") }
    }
    private func persist(_ reading: PendingReading) throws {
        try JSONEncoder().encode(reading).write(to: pendingURL, options: [.atomic, .completeFileProtection])
        var url = pendingURL
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    func newWeighIn() {
        guard !busy else { return }
        do {
            if FileManager.default.fileExists(atPath: pendingURL.path) { try FileManager.default.removeItem(at: pendingURL) }
            pending = nil
            shareConfirmationPresented = false
            start()
        } catch { fail("Could not replace the saved weigh-in. Please retry.") }
    }
    func requestShare() {
        guard !busy, pending != nil else { return }
        shareConfirmationPresented = true
    }
    func shareConfirmed() {
        guard !busy, let pending else { return }
        shareConfirmationPresented = false
        // A locally captured reading may predate account setup. Bind it only
        // when the user explicitly shares, then preserve that account on retries.
        let reading: PendingReading
        if pending.athleteID.isEmpty {
            reading = PendingReading(weight: pending.weight, measuredAt: pending.measuredAt, athleteID: athleteID, bodyFat: pending.bodyFat)
        } else { reading = pending }
        if uploader == nil {
            do {
                guard !athleteID.isEmpty, !(try KeychainStore.read()).isEmpty else {
                    message = "Set up Intervals.icu in Settings, then tap Share with Intervals.icu. Your weight is saved."
                    settingsPresented = true
                    return
                }
            } catch { fail(error.localizedDescription); return }
        }
        self.pending = reading
        do { try persist(reading) } catch { fail("Could not save the weigh-in locally. Free some storage and retry."); return }
        busy = true; title = "Syncing your weight"; message = "Uploading and verifying the saved weight on Intervals.icu…"
        generation = UUID(); let token = generation
        task = Task {
            do {
                if let uploader { try await uploader(reading) }
                else { try await client.upload(reading) }
                try Task.checkCancellation()
                guard token == generation else { return }
                try FileManager.default.removeItem(at: pendingURL)
                self.pending = nil; busy = false; verified = true
                title = "Weight shared"; message = "Verified on Intervals.icu."
            } catch {
                guard token == generation else { return }
                fail("\(error.localizedDescription) Your weigh-in is kept for retry. An upload may already have reached Intervals.icu.")
            }
        }
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        bluetooth.stop(); busy = false; scanning = false
        UIApplication.shared.isIdleTimerDisabled = false
        title = "Weigh-in stopped"
        message = pending == nil ? "Start again when you are ready." : "Your weight is kept for retry. An upload may already have completed."
    }
    func enteredBackground() {
        if busy { stop() }
    }
    private func fail(_ text: String) {
        bluetooth.stop(); busy = false; scanning = false; verified = false
        UIApplication.shared.isIdleTimerDisabled = false
        title = "Needs attention"; message = text
    }
    func saveSettings(id: String, key: String) async throws {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pending == nil || pending?.athleteID.isEmpty == true || pending?.athleteID == id else {
            throw ScaleFailure(message: "Share the saved weigh-in or start a new weigh-in before changing athlete.")
        }
        let effectiveKey = key.isEmpty ? try KeychainStore.read() : key.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = try await IntervalsClient(athleteID: id, key: effectiveKey).profile()
        _ = try IntervalsClient.day(Date(), zone: profile.timezone)
        try Task.checkCancellation()
        try KeychainStore.save(effectiveKey)
        UserDefaults.standard.set(id, forKey: "athleteID")
        athleteID = id
        if pending == nil { title = "Ready to weigh in"; message = "Wake your scale and start a weigh-in." }
    }
}
