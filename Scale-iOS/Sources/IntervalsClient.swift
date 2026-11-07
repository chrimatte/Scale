import Foundation

struct IntervalsClient {
    let athleteID: String
    let key: String
    var session: URLSession = .shared
    struct Profile: Decodable { let timezone: String? }
    struct Wellness: Decodable { let weight: Double?; let bodyFat: Double? }

    func request(_ suffix: String = "", method: String = "GET", body: Data? = nil) async throws -> Data {
        guard athleteID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil, !key.isEmpty else {
            throw ScaleFailure(message: "Enter your athlete ID and API key in Settings.")
        }
        let url = URL(string: "https://intervals.icu/api/v1/athlete/\(athleteID)\(suffix)")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Basic " + Data("API_KEY:\(key)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScaleFailure(message: "No response from Intervals.icu.") }
        guard (200...299).contains(http.statusCode) else {
            throw ScaleFailure(message: [401, 403].contains(http.statusCode)
                ? "Check your Intervals.icu athlete ID and API key."
                : "Intervals.icu returned HTTP \(http.statusCode). Try again.")
        }
        return data
    }
    func profile() async throws -> Profile { try JSONDecoder().decode(Profile.self, from: await request()) }
    static func day(_ date: Date, zone: String?) throws -> String {
        guard let zone, let timeZone = TimeZone(identifier: zone) else {
            throw ScaleFailure(message: "Set a valid time zone in your Intervals.icu profile, then retry.")
        }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }
    func upload(_ reading: PendingReading) async throws {
        guard reading.athleteID == athleteID else { throw ScaleFailure(message: "This weigh-in belongs to another athlete. Restore the original athlete ID to retry.") }
        let profile = try await profile()
        let date = try Self.day(reading.measuredAt, zone: profile.timezone)
        let suffix = "/wellness/\(date)"
        var values = ["weight": reading.weight]
        if let bodyFat = reading.bodyFat {
            guard bodyFat.isFinite, (0...100).contains(bodyFat) else {
                throw ScaleFailure(message: "The saved body fat percentage is invalid.")
            }
            values["bodyFat"] = bodyFat
        }
        let body = try JSONSerialization.data(withJSONObject: values)
        _ = try await request(suffix, method: "PUT", body: body)
        let saved = try JSONDecoder().decode(Wellness.self, from: await request(suffix))
        let fatMatches = reading.bodyFat.map { expected in
            saved.bodyFat.map { abs($0 - expected) <= 0.011 } ?? false
        } ?? true
        guard let weight = saved.weight, abs(weight - reading.weight) <= 0.011, fatMatches else {
            throw ScaleFailure(message: "Upload completed, but verification did not match. Check Intervals.icu before retrying.")
        }
    }
}
