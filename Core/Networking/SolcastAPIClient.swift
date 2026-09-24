import Foundation
final class SolcastAPIClient: SolcastAPIClientProtocol {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func fetchForecast(endpoint: SolcastEndpoint) async throws -> [ForecastPointDTO] {
        AppLogger.shared.info("SolcastAPIClient: fetching forecast for site \(endpoint.solcastSiteID)")
        guard let url = endpoint.url else {
            AppLogger.shared.error("SolcastAPIClient: invalid URL for site \(endpoint.solcastSiteID)")
            throw NetworkError.invalidURL
        }
        var req = URLRequest(url: url)
        // apiKeyValue is deliberately never logged, matching this project's
        // existing credential-exclusion convention (verified elsewhere in
        // this session: no API key value appears in any log line).
        req.setValue("Bearer \(endpoint.apiKeyValue)", forHTTPHeaderField: "Authorization")
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch {
            AppLogger.shared.error("SolcastAPIClient: no connectivity for site \(endpoint.solcastSiteID): \(error.localizedDescription)")
            throw NetworkError.noConnectivity
        }
        guard let http = response as? HTTPURLResponse else {
            AppLogger.shared.error("SolcastAPIClient: non-HTTP response for site \(endpoint.solcastSiteID)")
            throw NetworkError.unknown("Non-HTTP")
        }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403:
            AppLogger.shared.error("SolcastAPIClient: unauthorized (HTTP \(http.statusCode)) for site \(endpoint.solcastSiteID)")
            throw NetworkError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            AppLogger.shared.error("SolcastAPIClient: rate limited (HTTP 429) for site \(endpoint.solcastSiteID), retryAfter=\(retryAfter?.description ?? "unspecified")")
            throw NetworkError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            AppLogger.shared.error("SolcastAPIClient: server error (HTTP \(http.statusCode)) for site \(endpoint.solcastSiteID)")
            throw NetworkError.serverError(statusCode: http.statusCode)
        default:
            AppLogger.shared.error("SolcastAPIClient: unexpected HTTP \(http.statusCode) for site \(endpoint.solcastSiteID)")
            throw NetworkError.unknown("HTTP \(http.statusCode)")
        }
        do {
            let forecasts = try JSONDecoder().decode(SolcastResponseDTO.self, from: data).forecasts
            AppLogger.shared.info("SolcastAPIClient: received \(forecasts.count) forecast points for site \(endpoint.solcastSiteID)")
            return forecasts
        }
        catch {
            AppLogger.shared.error("SolcastAPIClient: decode failed for site \(endpoint.solcastSiteID): \(error.localizedDescription)")
            throw NetworkError.decodingFailed(error.localizedDescription)
        }
    }
}
