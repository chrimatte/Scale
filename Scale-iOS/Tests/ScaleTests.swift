import XCTest
@testable import Scale

final class ScaleTests: XCTestCase {
    func testBroadcastRequiresStableAndValidManufacturer() {
        var bytes: [UInt8] = [0xff, 0xff, 0xaa, 0xbb] + Array(repeating: 0, count: 17)
        bytes[19] = 0x10; bytes[20] = 0x1d // 74.40 kg
        XCTAssertNil(ScaleProtocol.broadcast(Data(bytes)))
        bytes[17] = 0x20
        XCTAssertEqual(ScaleProtocol.broadcast(Data(bytes)), 74.4)
        bytes[0] = 0
        XCTAssertNil(ScaleProtocol.broadcast(Data(bytes)))
        XCTAssertNil(ScaleProtocol.broadcast(Data(bytes.prefix(20))))
    }
    func testSettlingStoredAndCorruptFramesNeverUpload() {
        XCTAssertNil(ScaleProtocol.stableWeight(ScaleProtocol.frame(0x14, [0x10, 0, 0, 0x1d, 0x10])))
        XCTAssertEqual(ScaleProtocol.stableWeight(ScaleProtocol.frame(0x14, [0x11, 0, 0, 0x1d, 0x10])), 74.4)
        XCTAssertNil(ScaleProtocol.stableWeight(ScaleProtocol.frame(0x15, [1, 0, 0, 0x1d, 0x10])))
        var corrupt = ScaleProtocol.frame(0x14, [1, 0, 0, 0x1d, 0x10]); corrupt[corrupt.count - 1] ^= 1
        XCTAssertNil(ScaleProtocol.stableWeight(corrupt))
    }
    func testPowerOffRequiresLiveSessionWeight() {
        var session = RenphoSession()
        let off = ScaleProtocol.frame(0x11, [0])
        XCTAssertNil(session.receive(off))
        XCTAssertNil(session.receive(ScaleProtocol.frame(0x15, [1, 0, 0, 0x1d, 0x10])))
        XCTAssertNil(session.receive(off))
        XCTAssertNil(session.receive(ScaleProtocol.frame(0x14, [0, 0, 0, 0x1d, 0x10])))
        XCTAssertEqual(session.receive(off), 74.4)
        XCTAssertNil(session.receive(off))
    }
    func testESCS20MDiscoveryAliasesAndServices() {
        for name in ["QN-Scale", "ES-CS20M", "ESCS20M-B", "RENPHO", "113360_abc", "ES-32MD"] {
            var advert = ScaleAdvertisement()
            advert.merge(name: name, services: [], manufacturer: nil)
            XCTAssertTrue(advert.isCandidate, name)
        }
        var unnamed = ScaleAdvertisement()
        unnamed.merge(name: nil, services: ["0000FFF0-0000-1000-8000-00805F9B34FB"], manufacturer: nil)
        XCTAssertTrue(unnamed.isCandidate)
        XCTAssertEqual(unnamed.displayName, "Unnamed scale")
        XCTAssertFalse(ScaleAdvertisement().isCandidate)
        var headphones = ScaleAdvertisement()
        headphones.merge(name: "Headphones", services: ["FFF0"], manufacturer: nil)
        XCTAssertFalse(headphones.isCandidate)
    }
    func testDiscoveryUpdatesNameOnlyAdvertisementToBroadcast() {
        var advert = ScaleAdvertisement()
        advert.merge(name: "QN-Scale", services: [], manufacturer: nil)
        XCTAssertFalse(advert.isBroadcast)
        advert.merge(name: nil, services: [], manufacturer: Data([0xff, 0xff, 0xaa, 0xbb]))
        XCTAssertTrue(advert.isBroadcast)
        XCTAssertEqual(advert.displayName, "QN-Scale")
        advert.merge(name: nil, services: [], manufacturer: nil)
        XCTAssertTrue(advert.isBroadcast)
        XCTAssertNil(ScaleProtocol.broadcast(advert.manufacturer))
    }
    func testLegacyWriteModeMatchesDesktop() {
        XCTAssertFalse(ScaleProtocol.useWriteResponse(hasAE: false, supportsResponse: true, supportsWithoutResponse: true))
        XCTAssertTrue(ScaleProtocol.useWriteResponse(hasAE: true, supportsResponse: true, supportsWithoutResponse: true))
        XCTAssertTrue(ScaleProtocol.useWriteResponse(hasAE: false, supportsResponse: true, supportsWithoutResponse: false))
    }
    func testNotificationReassemblyAndChecksumRejection() {
        let frame = ScaleProtocol.frame(0x14, [1, 0, 0, 0x1d, 0x10])
        var stream = RenphoFrameStream()
        XCTAssertTrue(stream.append(Data(frame.prefix(4))).isEmpty)
        XCTAssertEqual(stream.append(Data(frame.dropFirst(4))), [frame])
        XCTAssertEqual(stream.append(frame + frame), [frame, frame])
        var bad = frame; bad[bad.count - 1] ^= 1
        XCTAssertEqual(stream.append(bad + frame), [frame])
        XCTAssertTrue(stream.append(Data([0x55, 0xaa, 0x14, 0xff, 0xff])).isEmpty)
        XCTAssertEqual(stream.append(frame), [frame])
    }
    @MainActor func testWeighInAndRelaunchNeverUploadWithoutConfirmation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var uploads = 0
        let model = ScaleModel(storageDirectory: directory, uploader: { _ in uploads += 1 })
        model.bluetooth.onWeight?(74.4)
        XCTAssertEqual(model.pending?.weight, 74.4)
        XCTAssertTrue(model.shareConfirmationPresented)
        XCTAssertFalse(model.busy)
        model.shareConfirmationPresented = false // Non ora
        await Task.yield()
        XCTAssertEqual(uploads, 0)
        let restored = ScaleModel(storageDirectory: directory, uploader: { _ in uploads += 1 })
        XCTAssertEqual(restored.pending?.weight, 74.4)
        XCTAssertFalse(restored.shareConfirmationPresented)
        await Task.yield()
        XCTAssertEqual(uploads, 0)
    }
    @MainActor func testExplicitSharingUploadsOnceAndClearsSavedReading() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sent = expectation(description: "Explicit upload")
        var uploads = 0
        let model = ScaleModel(storageDirectory: directory, uploader: { reading in
            XCTAssertEqual(reading.weight, 74.4)
            uploads += 1; sent.fulfill()
        })
        model.bluetooth.onWeight?(74.4)
        model.requestShare()
        XCTAssertEqual(uploads, 0)
        model.shareConfirmed()
        model.shareConfirmed() // A second tap must not duplicate the request.
        await fulfillment(of: [sent], timeout: 2)
        XCTAssertEqual(uploads, 1)
        XCTAssertTrue(model.verified)
        XCTAssertNil(model.pending)
    }
    @MainActor func testFailedSharingKeepsReadingWithoutAutomaticRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let attempted = expectation(description: "One failed attempt")
        var uploads = 0
        let model = ScaleModel(storageDirectory: directory, uploader: { _ in
            uploads += 1; attempted.fulfill()
            throw ScaleFailure(message: "Offline")
        })
        model.bluetooth.onWeight?(74.4)
        model.shareConfirmed()
        await fulfillment(of: [attempted], timeout: 2)
        XCTAssertEqual(uploads, 1)
        XCTAssertFalse(model.verified)
        XCTAssertEqual(model.pending?.weight, 74.4)
        XCTAssertFalse(model.busy)
    }
    func testWeightBounds() {
        for value in [Double.nan, Double.infinity, 0, -1, 301] { XCTAssertNil(ScaleProtocol.valid(value)) }
    }
    func testAthleteTimeZoneAtMidnight() throws {
        let instant = ISO8601DateFormatter().date(from: "2026-11-07T23:30:00Z")!
        XCTAssertEqual(try IntervalsClient.day(instant, zone: "Europe/Rome"), "2026-11-08")
        XCTAssertEqual(try IntervalsClient.day(instant, zone: "America/New_York"), "2026-11-07")
        XCTAssertThrowsError(try IntervalsClient.day(instant, zone: "invalid"))
    }
    func testWeightOnlyUploadAndIndependentReadback() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTP.self]
        MockHTTP.mismatch = false
        MockHTTP.methods = []
        let client = IntervalsClient(athleteID: "i123", key: "synthetic-test-key", session: URLSession(configuration: config))
        try await client.upload(PendingReading(weight: 74.4, measuredAt: Date(), athleteID: "i123"))
        XCTAssertEqual(MockHTTP.methods, ["GET", "PUT", "GET"])
    }
    func testReadbackMismatchIsFailure() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTP.self]
        MockHTTP.mismatch = true
        let client = IntervalsClient(athleteID: "i123", key: "synthetic-test-key", session: URLSession(configuration: config))
        do {
            try await client.upload(PendingReading(weight: 74.4, measuredAt: Date(), athleteID: "i123"))
            XCTFail("Mismatched readback must not be reported as success")
        } catch { XCTAssertTrue(error.localizedDescription.contains("verification")) }
    }
}

final class MockHTTP: URLProtocol, @unchecked Sendable {
    static var mismatch = false
    static var methods: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.methods.append(request.httpMethod!)
        var body = "{}"
        if request.httpMethod == "PUT" {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = try! JSONSerialization.jsonObject(with: data) as! [String: Double]
            XCTAssertEqual(json, ["weight": 74.4]) // No bodyFat key, not even null.
        } else if request.url!.path.contains("wellness") {
            body = Self.mismatch ? "{\"weight\":70}" : "{\"weight\":74.4}"
        } else { body = "{\"timezone\":\"Europe/Rome\"}" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
