import Foundation
@testable import SolarCast

actor MockLocationRepository: LocationRepository {
    var location: UserLocation? = UserLocation(
        name: "Limassol, Cyprus", latitude: 34.7071, longitude: 33.0226)
    func fetchCurrent() async throws -> UserLocation? { location }
    func save(_ location: UserLocation) async throws { self.location = location }
    func removeLocation() { location = nil }
}
