import Foundation
struct FetchJob: Sendable { let pvSite: PVSite; let apiKey: APIKey }
enum FetchResult: Sendable {
    case success(pvSiteID: UUID, points: [ForecastPointDTO])
    case failure(pvSiteID: UUID, error: NetworkError)
}
struct ParallelFetchCoordinator: Sendable {
    let apiClient: SolcastAPIClientProtocol
    func execute(jobs: [FetchJob]) async -> [FetchResult] {
        await withTaskGroup(of: FetchResult.self) { group in
            for job in jobs {
                group.addTask {
                    let ep = SolcastEndpoint(solcastSiteID: job.pvSite.solcastSiteID, apiKeyValue: job.apiKey.keyValue)
                    do { return .success(pvSiteID: job.pvSite.id, points: try await apiClient.fetchForecast(endpoint: ep)) }
                    catch let e as NetworkError { return .failure(pvSiteID: job.pvSite.id, error: e) }
                    catch { return .failure(pvSiteID: job.pvSite.id, error: .unknown(error.localizedDescription)) }
                }
            }
            var results: [FetchResult] = []
            for await r in group { results.append(r) }
            return results
        }
    }
}
