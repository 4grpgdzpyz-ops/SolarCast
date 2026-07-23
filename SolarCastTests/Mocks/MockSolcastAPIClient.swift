import Foundation
@testable import SolarCast

final class MockSolcastAPIClient: SolcastAPIClientProtocol, @unchecked Sendable {
    var stubbedResult: Result<[ForecastPointDTO], NetworkError> = .success([])
    var callCount = 0
    var lastEndpoint: SolcastEndpoint?
    func fetchForecast(endpoint: SolcastEndpoint) async throws -> [ForecastPointDTO] {
        callCount += 1; lastEndpoint = endpoint
        switch stubbedResult {
        case .success(let dtos): return dtos
        case .failure(let error): throw error
        }
    }
}
