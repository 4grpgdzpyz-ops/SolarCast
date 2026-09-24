import Foundation
actor ComputeStatsUseCase {
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
    func execute(date: Date, scenario: Scenario) async throws -> StatsResult? {
        guard let loc = try await locationRepository.fetchCurrent() else { return nil }
        guard let sw = await sunWindowCalculator.resolve(date: date, location: loc) else { return nil }
        // Previously fetched EVERY site unconditionally — Average/Peak/Total
        // never actually reflected which API key was enabled/active. Now
        // scoped to active sites only, via the same rule DashboardViewModel
        // already used correctly for its own activeSites property.
        let allSites = try await pvSiteRepository.fetchAll()
        let apiKeys = try await apiKeyRepository.fetchAll()
        let ids = ActiveSitePolicy.activeSites(sites: allSites, apiKeys: apiKeys).map(\.id)
        // Matches BuildChartDataUseCase's own fetch window exactly
        // (sunrise-30min to sunset+30min) — previously this used a much
        // narrower margin (sunrise-5min to sunset+5min), meaning
        // Average/Peak/Total was computed from a genuinely different,
        // smaller dataset than what the chart and breakdown actually
        // display. All three now draw from the same real data.
        let pts = try await forecastRepository.fetchPoints(pvSiteIDs: ids,
            from: sw.sunrise.addingTimeInterval(-1800), to: sw.sunset.addingTimeInterval(1800))
        return StatsEngine.compute(points: pts, scenario: scenario, date: date, sunWindow: sw)
    }
}
