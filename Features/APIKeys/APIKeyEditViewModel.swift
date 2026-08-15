import Foundation
import Observation
@Observable final class APIKeyEditViewModel {
    private let apiKeyRepository: APIKeyRepository
    private let pvSiteRepository: PVSiteRepository
    var name: String; var keyValue: String; var isEnabled: Bool
    var dailyQuotaLimit: Int; let keyID: UUID
    var availableSites: [PVSite] = []
    var assignedSiteIDs: Set<UUID>
    var errorMessage: String?
    init(key: APIKey?, apiKeyRepository: APIKeyRepository, pvSiteRepository: PVSiteRepository) {
        self.keyID = key?.id ?? UUID(); self.name = key?.name ?? ""
        self.keyValue = key?.keyValue ?? ""; self.isEnabled = key?.isEnabled ?? true
        self.dailyQuotaLimit = key?.dailyQuotaLimit ?? APIKey.defaultDailyQuotaLimit
        self.assignedSiteIDs = Set(key?.assignedSiteIDs ?? [])
        self.apiKeyRepository = apiKeyRepository; self.pvSiteRepository = pvSiteRepository
    }
    func loadAvailableSites() async {
        do {
            let all = try await pvSiteRepository.fetchAll()
            availableSites = all.filter { $0.apiKeyID == nil || $0.apiKeyID == keyID }
        } catch {
            AppLogger.shared.error("APIKeyEditViewModel: failed to load available sites: \(error)")
            errorMessage = "Couldn't load sites."
        }
    }
    func toggleSite(_ id: UUID) {
        if assignedSiteIDs.contains(id) { assignedSiteIDs.remove(id) } else { assignedSiteIDs.insert(id) }
    }
    func save() async -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Name is required."; return false }
        guard !keyValue.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Key value is required."; return false }
        let key = APIKey(id: keyID, name: name, keyValue: keyValue, isEnabled: isEnabled,
                         dailyQuotaLimit: dailyQuotaLimit, reservedQuota: 0, assignedSiteIDs: Array(assignedSiteIDs))
        do {
            try await apiKeyRepository.save(key)
            for site in availableSites {
                var updated = site; let shouldOwn = assignedSiteIDs.contains(site.id)
                if shouldOwn != (site.apiKeyID == keyID) {
                    updated.apiKeyID = shouldOwn ? keyID : nil
                    try await pvSiteRepository.save(updated)
                }
            }
            return true
        } catch {
            AppLogger.shared.error("APIKeyEditViewModel: failed to save key '\(name)': \(error)")
            errorMessage = "Couldn't save API key."
            return false
        }
    }
}
