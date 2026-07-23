import Foundation
protocol SolcastAPIClientProtocol: Sendable {
    func fetchForecast(endpoint: SolcastEndpoint) async throws -> [ForecastPointDTO]
}
