import Foundation
import Observation
@Observable final class PVSiteEditViewModel {
    private let pvSiteRepository: PVSiteRepository
    let siteID: UUID
    var solcastSiteID: String; var name: String; var colorHex: String
    var errorMessage: String?
    static let presetColors = ["#00C853","#2196F3","#FF9800","#E91E63","#9C27B0","#00BCD4"]
    init(site: PVSite?, pvSiteRepository: PVSiteRepository) {
        self.siteID = site?.id ?? UUID(); self.solcastSiteID = site?.solcastSiteID ?? ""
        self.name = site?.name ?? ""; self.colorHex = site?.colorHex ?? Self.presetColors[0]
        self.pvSiteRepository = pvSiteRepository
    }
    func save() async -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Name is required."; return false }
        guard !solcastSiteID.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Site ID is required."; return false }
        do {
            let existing = try await pvSiteRepository.fetch(id: siteID)
            let site = PVSite(id: siteID, solcastSiteID: solcastSiteID, name: name, colorHex: colorHex, apiKeyID: existing?.apiKeyID)
            try await pvSiteRepository.save(site); return true
        } catch {
            AppLogger.shared.error("PVSiteEditViewModel: failed to save site '\(name)': \(error)")
            errorMessage = "Couldn't save site."
            return false
        }
    }
}
