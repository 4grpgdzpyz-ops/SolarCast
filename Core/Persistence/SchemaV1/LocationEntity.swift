import Foundation
import SwiftData
@Model final class LocationEntity {
    @Attribute(.unique) var id: UUID
    var name: String; var latitude: Double; var longitude: Double
    init(id: UUID, name: String, latitude: Double, longitude: Double) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
    }
}
