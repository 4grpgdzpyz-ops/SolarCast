import Foundation
struct ForecastPointDTO: Codable, Sendable {
    let pvEstimate: Double
    let pvEstimate10: Double
    let pvEstimate90: Double
    let periodEnd: String
    let period: String
    enum CodingKeys: String, CodingKey {
        case pvEstimate = "pv_estimate"
        case pvEstimate10 = "pv_estimate10"
        case pvEstimate90 = "pv_estimate90"
        case periodEnd = "period_end"
        case period
    }
    init(pvEstimate: Double, pvEstimate10: Double, pvEstimate90: Double,
         periodEnd: String, period: String) {
        self.pvEstimate = pvEstimate
        self.pvEstimate10 = pvEstimate10
        self.pvEstimate90 = pvEstimate90
        self.periodEnd = periodEnd
        self.period = period
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pvEstimate = try c.decode(Double.self, forKey: .pvEstimate)
        // Default P10/P90 to ±30% of estimate if not provided
        pvEstimate10 = (try? c.decode(Double.self, forKey: .pvEstimate10)) ?? (pvEstimate * 0.7)
        pvEstimate90 = (try? c.decode(Double.self, forKey: .pvEstimate90)) ?? (pvEstimate * 1.3)
        periodEnd = try c.decode(String.self, forKey: .periodEnd)
        period = try c.decode(String.self, forKey: .period)
    }
}
