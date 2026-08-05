import Foundation
enum Scenario: String, CaseIterable, Codable, Identifiable {
    case pessimistic, normal, optimistic
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .pessimistic: return "Pessimistic"
        case .normal:      return "Normal"
        case .optimistic:  return "Optimistic"
        }
    }
}
