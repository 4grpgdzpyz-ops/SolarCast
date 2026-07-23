import Foundation

/// Single source of truth for "which PV sites should be included in
/// computed data (stats, chart, breakdown)" — a site is active when it's
/// assigned to an API key that is currently enabled.
///
/// This logic previously existed ONLY inside DashboardViewModel.activeSites,
/// and was applied too late and too narrowly: ComputeStatsUseCase and
/// BuildChartDataUseCase both fetched EVERY site unconditionally
/// (pvSiteRepository.fetchAll() with no filtering at all), so switching
/// which API key was active/enabled had no effect on Average/Peak/Total or
/// on the chart's own Total series — only DashboardViewModel.loadChart()
/// applied any filtering, and even that filter explicitly exempted the
/// "total" series from being filtered, meaning the Total line (and
/// anything built from it, like the breakdown) always summed every site
/// regardless of which key was active. Filtering now happens at the
/// actual data source, in both use cases, so nothing downstream can see
/// (or accidentally sum) an inactive site's data in the first place.
struct ActiveSitePolicy: Sendable {
    static func activeSites(sites: [PVSite], apiKeys: [APIKey]) -> [PVSite] {
        let enabledKeyIDs = Set(apiKeys.filter(\.isEnabled).map(\.id))
        return sites.filter { site in
            guard let keyID = site.apiKeyID else { return false }
            return enabledKeyIDs.contains(keyID)
        }
    }
}
