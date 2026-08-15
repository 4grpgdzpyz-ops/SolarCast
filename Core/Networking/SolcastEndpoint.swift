import Foundation
struct SolcastEndpoint {
    let solcastSiteID: String
    let apiKeyValue: String
    var hours: Int = 168
    var period: String = "PT30M"
    var url: URL? {
        var c = URLComponents(string: "https://api.solcast.com.au/rooftop_sites/\(solcastSiteID)/forecasts")
        c?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "hours", value: String(hours)),
            URLQueryItem(name: "period", value: period)
        ]
        return c?.url
    }
}
