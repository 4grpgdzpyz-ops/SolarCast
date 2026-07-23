import Foundation
import SwiftData
import CryptoKit

/// Single source of truth for exporting and importing backups — replaces
/// the old SettingsExporter / DataExporter pair, which built raw
/// [String: Any] dictionaries by hand with no version field, no Codable
/// safety net, and (for settings) an extra UserDefaults cache layer that
/// went stale independently of the data it was caching.
///
/// This actor reads directly from UserDefaults / ModelContainer at export
/// time — nothing cached in between — and every field is a real Codable
/// struct property, so an incomplete DTO construction fails to compile
/// instead of silently dropping a field (which is what happened to
/// createdAt and isMock in the old dictionary-based importers).
actor BackupService {
    private let modelContainer: ModelContainer

    private static let encryptionKey: SymmetricKey = {
        let seed = "com.ioanmihaila.solarcast.backup.v1"
        return SymmetricKey(data: SHA256.hash(data: Data(seed.utf8)))
    }()

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Encrypt / Decrypt
    //
    // nonisolated: these are pure functions over Strings with no actor
    // state involved, and need to be callable from the @MainActor fetch*
    // methods below without hopping back onto the BackupService actor for
    // every single string.

    nonisolated private func encrypt(_ plaintext: String) -> String {
        guard !plaintext.isEmpty, let data = plaintext.data(using: .utf8),
              let sealed = try? AES.GCM.seal(data, using: Self.encryptionKey) else { return "" }
        return sealed.combined?.base64EncodedString() ?? ""
    }

    nonisolated private func decrypt(_ ciphertext: String) -> String {
        guard !ciphertext.isEmpty, let data = Data(base64Encoded: ciphertext),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: Self.encryptionKey) else { return "" }
        return String(data: opened, encoding: .utf8) ?? ""
    }

    // MARK: - Export: Settings

    /// Reads preferences fresh from UserDefaults / FetchTriggerConfigurationStore
    /// at call time — no cache, so this always reflects whatever is currently
    /// set, including a change made moments earlier.
    func exportSettings() -> SettingsDTO {
        let d = UserDefaults.standard
        let theme = d.string(forKey: "solarcast.appTheme") ?? "system"
        let useMock = d.bool(forKey: "solarcast.useMockData")
        let loggingEnabled = d.object(forKey: "solarcast.loggingEnabled") != nil
            ? d.bool(forKey: "solarcast.loggingEnabled") : false
        let showBGTasks = d.object(forKey: "solarcast.showBGTasks") != nil
            ? d.bool(forKey: "solarcast.showBGTasks") : false
        let config = FetchTriggerConfigurationStore.load()
        return SettingsDTO(
            theme: theme, useMockData: useMock, loggingEnabled: loggingEnabled, showBGTasks: showBGTasks,
            autoFetchEnabled: config.autoFetchEnabled, autoRefreshEnabled: config.autoRefreshEnabled,
            autoFetchTiming: .from(config.autoFetchTiming))
    }

    // MARK: - Export: SwiftData (API keys, sites, location — used by both settings and data backups)

    @MainActor
    private func fetchAPIKeyDTOs() -> [APIKeyDTO] {
        let ctx = ModelContext(modelContainer)
        let keys = (try? ctx.fetch(FetchDescriptor<APIKeyEntity>())) ?? []
        return keys.map { k in
            APIKeyDTO(id: k.id, name: k.name, keyValueEncrypted: encrypt(k.keyValue),
                      isEnabled: k.isEnabled, dailyQuotaLimit: k.dailyQuotaLimit,
                      reservedQuota: k.reservedQuota, createdAt: k.createdAt)
        }
    }

    @MainActor
    private func fetchPVSiteDTOs() -> [PVSiteDTO] {
        let ctx = ModelContext(modelContainer)
        let sites = (try? ctx.fetch(FetchDescriptor<PVSiteEntity>())) ?? []
        return sites.map { s in
            PVSiteDTO(id: s.id, name: s.name, solcastSiteIDEncrypted: encrypt(s.solcastSiteID),
                      colorHex: s.colorHex, apiKeyID: s.apiKey?.id, createdAt: s.createdAt)
        }
    }

    @MainActor
    private func fetchLocationDTO() -> LocationDTO? {
        let ctx = ModelContext(modelContainer)
        guard let loc = (try? ctx.fetch(FetchDescriptor<LocationEntity>()))?.first else { return nil }
        return LocationDTO(id: loc.id, name: loc.name, latitude: loc.latitude, longitude: loc.longitude)
    }

    @MainActor
    private func fetchForecastPointDTOs() -> [ForecastPointDTO_Backup] {
        let ctx = ModelContext(modelContainer)
        let points = (try? ctx.fetch(FetchDescriptor<ForecastPointEntity>())) ?? []
        return points.compactMap { p in
            guard let siteID = p.pvSite?.id else { return nil }
            return ForecastPointDTO_Backup(
                pointID: p.pointID, pvSiteID: siteID, periodStart: p.periodStart, periodEnd: p.periodEnd,
                period: p.period, pvEstimate: p.pvEstimate, pvEstimate10: p.pvEstimate10,
                pvEstimate90: p.pvEstimate90, isMock: p.isMock)
        }
    }

    func exportSwiftData() async -> (apiKeys: [APIKeyDTO], pvSites: [PVSiteDTO], location: LocationDTO?, forecastPoints: [ForecastPointDTO_Backup]) {
        let keys = await fetchAPIKeyDTOs()
        let sites = await fetchPVSiteDTOs()
        let loc = await fetchLocationDTO()
        let points = await fetchForecastPointDTOs()
        return (keys, sites, loc, points)
    }

    // MARK: - createBackup

    /// Builds a settings-only backup: preferences plus the API keys / sites
    /// / location they reference (so a settings restore on a fresh install
    /// also brings back what those settings actually point at).
    func createSettingsBackup() async -> AppBackup {
        let settings = exportSettings()
        let (keys, sites, loc, _) = await exportSwiftData()
        AppLogger.shared.info("BackupService: created settings backup (\(keys.count) keys, \(sites.count) sites)")
        return AppBackup(kind: .settings, settings: settings, apiKeys: keys, pvSites: sites, location: loc)
    }

    /// Builds a full data backup: everything a settings backup has, plus
    /// every stored forecast point.
    func createDataBackup() async -> AppBackup {
        let (keys, sites, loc, points) = await exportSwiftData()
        AppLogger.shared.info("BackupService: created data backup (\(points.count) forecast points)")
        return AppBackup(kind: .data, apiKeys: keys, pvSites: sites, location: loc, forecastPoints: points)
    }

    // MARK: - importBackup

    func importBackup(_ backup: AppBackup, expecting expectedKind: BackupKind) async throws {
        try migrate(version: backup.version)
        guard backup.kind == expectedKind else {
            AppLogger.shared.error("BackupService: import kind mismatch — expected \(expectedKind.rawValue), file contains \(backup.kind.rawValue)")
            throw BackupError.wrongKind(expected: expectedKind, found: backup.kind)
        }

        switch expectedKind {
        case .settings:
            guard let settings = backup.settings else {
                AppLogger.shared.error("BackupService: settings backup has no settings payload")
                throw BackupError.missingSettings
            }
            applySettings(settings)
            try await importSwiftData(apiKeys: backup.apiKeys ?? [], pvSites: backup.pvSites ?? [],
                                   location: backup.location, forecastPoints: nil)
        case .data:
            try await importSwiftData(apiKeys: backup.apiKeys ?? [], pvSites: backup.pvSites ?? [],
                                   location: backup.location, forecastPoints: backup.forecastPoints ?? [])
        }
        AppLogger.shared.info("BackupService: imported \(expectedKind.rawValue) backup (format v\(backup.version), exported \(backup.exportedAt))")
    }

    private func applySettings(_ s: SettingsDTO) {
        let d = UserDefaults.standard
        d.set(s.theme, forKey: "solarcast.appTheme")
        d.set(s.useMockData, forKey: "solarcast.useMockData")
        d.set(s.loggingEnabled, forKey: "solarcast.loggingEnabled")
        d.set(s.showBGTasks, forKey: "solarcast.showBGTasks")
        FetchTriggerConfigurationStore.save(FetchTriggerConfiguration(
            autoFetchEnabled: s.autoFetchEnabled,
            autoFetchTiming: s.autoFetchTiming.toDomain(),
            autoRefreshEnabled: s.autoRefreshEnabled))
    }

    @MainActor
    private func importSwiftData(apiKeys: [APIKeyDTO], pvSites: [PVSiteDTO], location: LocationDTO?,
                                  forecastPoints: [ForecastPointDTO_Backup]?) async throws {
        let ctx = ModelContext(modelContainer)

        var keyEntityMap: [UUID: APIKeyEntity] = [:]
        for k in apiKeys {
            let kid = k.id
            let keyValue = decrypt(k.keyValueEncrypted)
            let desc = FetchDescriptor<APIKeyEntity>(predicate: #Predicate { $0.id == kid })
            if let existing = try? ctx.fetch(desc).first {
                existing.name = k.name; existing.keyValue = keyValue; existing.isEnabled = k.isEnabled
                existing.dailyQuotaLimit = k.dailyQuotaLimit; existing.reservedQuota = k.reservedQuota
                keyEntityMap[k.id] = existing
            } else {
                let entity = APIKeyEntity(id: k.id, name: k.name, keyValue: keyValue, isEnabled: k.isEnabled,
                                          dailyQuotaLimit: k.dailyQuotaLimit, reservedQuota: k.reservedQuota,
                                          createdAt: k.createdAt)
                ctx.insert(entity)
                keyEntityMap[k.id] = entity
            }
        }

        var siteEntityMap: [UUID: PVSiteEntity] = [:]
        for s in pvSites {
            let sid = s.id
            let solcastID = decrypt(s.solcastSiteIDEncrypted)
            let desc = FetchDescriptor<PVSiteEntity>(predicate: #Predicate { $0.id == sid })
            if let existing = try? ctx.fetch(desc).first {
                existing.name = s.name; existing.solcastSiteID = solcastID
                existing.colorHex = s.colorHex; existing.apiKey = s.apiKeyID.flatMap { keyEntityMap[$0] }
                siteEntityMap[s.id] = existing
            } else {
                let entity = PVSiteEntity(id: s.id, solcastSiteID: solcastID, name: s.name,
                                          colorHex: s.colorHex, apiKey: s.apiKeyID.flatMap { keyEntityMap[$0] },
                                          createdAt: s.createdAt)
                ctx.insert(entity)
                siteEntityMap[s.id] = entity
            }
        }

        if let loc = location {
            for e in (try? ctx.fetch(FetchDescriptor<LocationEntity>())) ?? [] { ctx.delete(e) }
            ctx.insert(LocationEntity(id: loc.id, name: loc.name, latitude: loc.latitude, longitude: loc.longitude))
        }

        if let points = forecastPoints {
            for p in points {
                let pid = p.pointID
                let siteEntity = siteEntityMap[p.pvSiteID]
                let desc = FetchDescriptor<ForecastPointEntity>(predicate: #Predicate { $0.pointID == pid })
                if let existing = try? ctx.fetch(desc).first {
                    existing.pvEstimate = p.pvEstimate; existing.pvEstimate10 = p.pvEstimate10
                    existing.pvEstimate90 = p.pvEstimate90; existing.isMock = p.isMock
                } else {
                    ctx.insert(ForecastPointEntity(
                        pointID: p.pointID, pvSite: siteEntity, periodStart: p.periodStart, periodEnd: p.periodEnd,
                        period: p.period, pvEstimate: p.pvEstimate, pvEstimate10: p.pvEstimate10,
                        pvEstimate90: p.pvEstimate90, isMock: p.isMock))
                }
            }

            // Record a synthetic "pull" for every key that received
            // imported data, so StalenessEvaluator.lastSuccessfulPull sees
            // a genuinely current timestamp instead of finding nothing and
            // falling back to "never pulled — stale." Import IS the
            // freshness signal here; no separate fallback logic needed
            // once this is recorded at the source. One event per DISTINCT
            // key (not per point) — staleness cares whether the key was
            // recently refreshed, not how many points arrived for it.
            // isMock reflects what was actually imported for that key: if
            // any of its imported points are mock, the event is marked
            // mock too, since a real export/import never mixes modes
            // within one file (exportSwiftData reads under one mode at a
            // time).
            let siteToKeyID: [UUID: UUID] = Dictionary(uniqueKeysWithValues:
                pvSites.compactMap { site in site.apiKeyID.map { (site.id, $0) } })
            var isMockByKeyID: [UUID: Bool] = [:]
            for p in points {
                guard let keyID = siteToKeyID[p.pvSiteID] else { continue }
                isMockByKeyID[keyID, default: false] = isMockByKeyID[keyID, default: false] || p.isMock
            }
            let importTimestamp = Date()
            for (keyID, isMockForKey) in isMockByKeyID {
                ctx.insert(QuotaUsageEntity(
                    id: UUID(), apiKey: keyEntityMap[keyID], timestamp: importTimestamp,
                    wasSuccessful: true, purposeRawValue: FetchPurpose.imported.rawValue, isMock: isMockForKey))
            }
            if !isMockByKeyID.isEmpty {
                AppLogger.shared.info("BackupService: recorded import-as-pull for \(isMockByKeyID.count) key(s) at \(importTimestamp)")
            }
        }

        do {
            try ctx.save()
        } catch {
            AppLogger.shared.error("BackupService: import save failed: \(error)")
            throw BackupError.persistenceFailed(underlying: error.localizedDescription)
        }
    }

    // MARK: - migrate

    /// Validates (and, in the future, transforms) a backup's version before
    /// any of its content is trusted. Currently there is only version 1, so
    /// this only rejects anything newer than what this build understands —
    /// but the switch shape is what lets a future version 2 add a
    /// migrateV1ToV2(...) case here without touching import/export logic
    /// elsewhere.
    private func migrate(version: Int) throws {
        switch version {
        case 1:
            return // current version, nothing to migrate
        default:
            AppLogger.shared.error("BackupService: unsupported backup format version \(version) (current app supports v\(AppBackup.currentVersion))")
            throw BackupError.unsupportedVersion(version)
        }
    }
}
