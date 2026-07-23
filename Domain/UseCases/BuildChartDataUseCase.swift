import Foundation
actor BuildChartDataUseCase {
    private let forecastRepository: ForecastRepository
    private let pvSiteRepository: PVSiteRepository
    private let apiKeyRepository: APIKeyRepository
    private let locationRepository: LocationRepository
    private let sunWindowCalculator: SunWindowCalculator
    init(forecastRepository: ForecastRepository, pvSiteRepository: PVSiteRepository,
         apiKeyRepository: APIKeyRepository, locationRepository: LocationRepository,
         sunWindowCalculator: SunWindowCalculator) {
        self.forecastRepository = forecastRepository; self.pvSiteRepository = pvSiteRepository
        self.apiKeyRepository = apiKeyRepository
        self.locationRepository = locationRepository; self.sunWindowCalculator = sunWindowCalculator
    }
    func execute(date: Date, scenario: Scenario) async throws -> [ChartSeries] {
        guard let loc = try await locationRepository.fetchCurrent() else { return [] }
        guard let sw = await sunWindowCalculator.resolve(date: date, location: loc) else { return [] }
        // Previously passed EVERY site into ChartDataAssembler.assemble,
        // which sums whatever it's given into the "total" series — so the
        // chart's Total line (and the breakdown built from the same
        // chartSeries) always summed every site's production regardless of
        // which API key was active. DashboardViewModel.loadChart() DID
        // filter afterward, but only removed individual per-site lines
        // from display, explicitly exempting "total" from that filter —
        // by which point the total had already been summed from the wrong
        // set. Filtering here, before assemble() ever runs, fixes it at
        // the actual source.
        let allSites = try await pvSiteRepository.fetchAll()
        let apiKeys = try await apiKeyRepository.fetchAll()
        let sites = ActiveSitePolicy.activeSites(sites: allSites, apiKeys: apiKeys)
        let pts = try await forecastRepository.fetchPoints(pvSiteIDs: sites.map(\.id),
            from: sw.sunrise.addingTimeInterval(-1800), to: sw.sunset.addingTimeInterval(1800))
        return ChartDataAssembler.assemble(points: pts, sites: sites, scenario: scenario, sunWindow: sw)
    }
}
