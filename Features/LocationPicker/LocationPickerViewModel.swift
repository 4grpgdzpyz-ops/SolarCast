import Foundation
import MapKit
import Observation
@Observable final class LocationPickerViewModel {
    private let locationRepository: LocationRepository
    var searchText: String = ""; var searchResults: [MKMapItem] = []
    var pinCoordinate: CLLocationCoordinate2D?; var locationName: String = ""
    var errorMessage: String?
    /// Incremented each time the pin moves. Used by the View's onChange instead
    /// of observing pinCoordinate directly, since CLLocationCoordinate2D (a C
    /// struct) does not conform to Equatable and cannot be used with onChange.
    var pinDropCount: Int = 0
    init(locationRepository: LocationRepository) { self.locationRepository = locationRepository }
    func loadCurrent() async {
        do {
            if let loc = try await locationRepository.fetchCurrent() {
                pinCoordinate = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                locationName = loc.name
            }
        } catch {
            AppLogger.shared.error("LocationPickerViewModel: failed to load current location: \(error)")
        }
    }
    func search() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let req = MKLocalSearch.Request(); req.naturalLanguageQuery = searchText
        do { searchResults = try await MKLocalSearch(request: req).start().mapItems }
        catch {
            AppLogger.shared.error("LocationPickerViewModel: search failed for query '\(searchText)': \(error)")
            errorMessage = "Search failed."
        }
    }
    func selectResult(_ item: MKMapItem) {
        pinCoordinate = item.placemark.coordinate
        locationName = item.name ?? "Selected Location"
        searchResults = []; searchText = ""
        pinDropCount += 1
    }
    func dropPin(at coord: CLLocationCoordinate2D) {
        pinCoordinate = coord
        if locationName.isEmpty { locationName = "Custom Location" }
        pinDropCount += 1
    }
    func save() async -> Bool {
        guard let coord = pinCoordinate else { errorMessage = "Select a location first."; return false }
        let name = locationName.trimmingCharacters(in: .whitespaces).isEmpty ? "My Location" : locationName
        do {
            try await locationRepository.save(UserLocation(name: name, latitude: coord.latitude, longitude: coord.longitude))
            return true
        } catch {
            AppLogger.shared.error("LocationPickerViewModel: failed to save location '\(name)': \(error)")
            errorMessage = "Couldn't save location."
            return false
        }
    }
}
