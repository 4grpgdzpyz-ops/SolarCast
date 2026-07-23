import Foundation
enum NetworkError: Error, Equatable, Sendable {
    case invalidURL, invalidAPIKey, unauthorized, noConnectivity
    case quotaExceeded(keyID: UUID)
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case decodingFailed(String)
    case unknown(String)
}
