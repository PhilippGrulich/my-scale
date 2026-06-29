import Foundation
import MiScaleCore

/// Optional, non-blocking Home Assistant mirror. Runs entirely off the
/// HealthKit path; failures never affect HealthKit and are retried later.
final class HASink {

    struct Payload: Codable {
        var user: String
        var capturedAt: Date
        var weightKg: Double
        var bodyFatPercent: Double?
        var leanMassKg: Double?
        var bmi: Double
        var impedanceOhms: Int
    }

    private let session: URLSession
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    /// POST with bounded exponential backoff. Returns true on a 2xx response.
    func post(_ payload: Payload, config: HAConfig, maxAttempts: Int = 4) async -> Bool {
        guard config.enabled, let url = URL(string: config.endpoint) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.token.isEmpty {
            request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? encoder.encode(payload)

        var delay: UInt64 = 2_000_000_000 // 2s
        for attempt in 1...maxAttempts {
            do {
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return true
                }
            } catch {
                // fall through to retry
            }
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }
        return false
    }
}
