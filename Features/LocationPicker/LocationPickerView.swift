import SwiftUI
import MapKit
import CoreLocation

struct LocationPickerView: View {
    @State var viewModel: LocationPickerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapStyle: MapStyleOption = .hybrid
    @StateObject private var locationManager = CurrentLocationManager()

    enum MapStyleOption: String, CaseIterable {
        case standard  = "Standard"
        case satellite = "Satellite"
        case hybrid    = "Hybrid"
        var mapStyle: MapStyle {
            switch self {
            case .standard:  return .standard
            case .satellite: return .imagery
            case .hybrid:    return .hybrid
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.scMuted)
                    TextField("Search address", text: $viewModel.searchText)
                        .onSubmit { Task { await viewModel.search() } }
                }
                .padding(10)
                .background(Color.scSurfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal).padding(.top, 8)

                // Search results — sized to content, no large gap
                if !viewModel.searchResults.isEmpty {
                    List(viewModel.searchResults, id: \.self) { item in
                        Button {
                            viewModel.selectResult(item)
                            cameraPosition = .region(MKCoordinateRegion(
                                center: item.placemark.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown").foregroundStyle(Color.scText)
                                if let addr = item.placemark.title {
                                    Text(addr).font(.caption).foregroundStyle(Color.scMuted)
                                }
                            }
                        }
                        .listRowBackground(Color.scCard)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: CGFloat(min(viewModel.searchResults.count, 4)) * 56)
                }

                // Map style picker
                Picker("Map Style", selection: $mapStyle) {
                    ForEach(MapStyleOption.allCases, id: \.self) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 6)

                ZStack(alignment: .bottomTrailing) {
                    MapReader { proxy in
                        Map(position: $cameraPosition, interactionModes: .all) {
                            if let coord = viewModel.pinCoordinate {
                                Marker(viewModel.locationName.isEmpty ? "Selected" : viewModel.locationName,
                                       coordinate: coord)
                            }
                        }
                        .mapStyle(mapStyle.mapStyle)
                        .onTapGesture { point in
                            if let coord = proxy.convert(point, from: .local) {
                                viewModel.dropPin(at: coord)
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: coord,
                                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }

                    // Current location button
                    Button {
                        guard !locationManager.isLocating else { return }
                        locationManager.requestLocation { coord in
                            guard let coord = coord else { return }
                            viewModel.dropPin(at: coord)
                            viewModel.locationName = "Current Location"
                            cameraPosition = .region(MKCoordinateRegion(
                                center: coord,
                                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                        }
                    } label: {
                        Group {
                            if locationManager.isLocating {
                                ProgressView()
                                    .tint(Color.scAccent)
                            } else {
                                Image(systemName: "location.fill")
                            }
                        }
                        .font(.system(size: 16))
                        .foregroundStyle(Color.scAccent)
                        .frame(width: 44, height: 44)
                        .background(Color.scCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                    .padding(16)
                }

                TextField("Location name", text: $viewModel.locationName)
                    .textFieldStyle(.roundedBorder)
                    .padding()
            }
            .navigationTitle("Set Location")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { Task { if await viewModel.save() { dismiss() } } }
                }
            }
            .task { await viewModel.loadCurrent() }
            .onChange(of: viewModel.pinDropCount) { _, _ in
                guard let c = viewModel.pinCoordinate else { return }
                cameraPosition = .region(MKCoordinateRegion(
                    center: c, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }
}

/// CLLocationManager wrapper — uses startUpdatingLocation for faster GPS fix
/// instead of requestLocation which waits for full accuracy.
final class CurrentLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D?) -> Void)?
    @Published var isLocating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters // faster initial fix
    }

    func requestLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completion = completion
        isLocating = true
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation() // faster than requestLocation()
        } else {
            isLocating = false
            completion(nil)
            self.completion = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation() // stop after first fix
        isLocating = false
        completion?(locations.first?.coordinate)
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as NSError).code == CLError.locationUnknown.rawValue { return } // keep trying
        manager.stopUpdatingLocation()
        isLocating = false
        completion?(nil)
        completion = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if (status == .authorizedWhenInUse || status == .authorizedAlways),
           completion != nil {
            manager.startUpdatingLocation()
        } else if status == .denied || status == .restricted {
            isLocating = false
            completion?(nil)
            completion = nil
        }
    }
}
