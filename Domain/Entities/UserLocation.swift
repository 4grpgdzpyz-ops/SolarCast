import Foundation
struct UserLocation: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
    }
}
