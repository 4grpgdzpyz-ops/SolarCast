import Foundation
struct SolcastResponseDTO: Codable, Sendable {
    let forecasts: [ForecastPointDTO]
}
