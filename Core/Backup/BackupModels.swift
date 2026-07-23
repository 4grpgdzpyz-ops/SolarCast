import Foundation

// MARK: - Top-level versioned backup container

/// The root object written to and read from every backup file — settings
/// and data combined, or either alone, depending on which export was run.
/// `version` is checked on import BEFORE anything else is decoded, so a
/// future schema change can add a new case to the version switch without
/// breaking the ability to at least detect and reject (or migrate) an old
/// file, rather than the old dictionary-based code's failure mode: a
/// missing field just silently defaults to zero/empty with no way to tell
/// afterward that anything was lost.
struct AppBackup: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var kind: BackupKind

    var settings: SettingsDTO?
    var apiKeys: [APIKeyDTO]?
    var pvSites: [PVSiteDTO]?
    var location: LocationDTO?
    var forecastPoints: [ForecastPointDTO_Backup]?

    init(kind: BackupKind, settings: SettingsDTO? = nil, apiKeys: [APIKeyDTO]? = nil,
         pvSites: [PVSiteDTO]? = nil, location: LocationDTO? = nil,
         forecastPoints: [ForecastPointDTO_Backup]? = nil) {
        self.version = Self.currentVersion
        self.exportedAt = Date()
        self.kind = kind
        self.settings = settings
        self.apiKeys = apiKeys
        self.pvSites = pvSites
        self.location = location
        self.forecastPoints = forecastPoints
    }
}

/// What a given backup file actually contains — lets the importer reject a
/// data-only file when the user tapped "Import Settings" and vice versa,
/// instead of silently doing nothing or partially importing.
enum BackupKind: String, Codable, Sendable {
    case settings
    case data
}

// MARK: - Settings

struct SettingsDTO: Codable, Sendable, Equatable {
    var theme: String
    var useMockData: Bool
    var loggingEnabled: Bool
    var showBGTasks: Bool
    var autoFetchEnabled: Bool
    var autoRefreshEnabled: Bool
    var autoFetchTiming: AutoFetchTimingDTO

    init(theme: String, useMockData: Bool, loggingEnabled: Bool, showBGTasks: Bool,
         autoFetchEnabled: Bool, autoRefreshEnabled: Bool, autoFetchTiming: AutoFetchTimingDTO) {
        self.theme = theme; self.useMockData = useMockData; self.loggingEnabled = loggingEnabled
        self.showBGTasks = showBGTasks
        self.autoFetchEnabled = autoFetchEnabled; self.autoRefreshEnabled = autoRefreshEnabled
        self.autoFetchTiming = autoFetchTiming
    }

    // showBGTasks decoded with decodeIfPresent, defaulting to false — a
    // backup exported BEFORE this field existed (same top-level version
    // number, since this is a field addition, not a version bump) has no
    // such key in its JSON at all. A plain synthesized Codable would
    // throw on that missing key, making every pre-existing backup file
    // suddenly unimportable. This keeps old backups importing cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decode(String.self, forKey: .theme)
        useMockData = try c.decode(Bool.self, forKey: .useMockData)
        loggingEnabled = try c.decode(Bool.self, forKey: .loggingEnabled)
        showBGTasks = try c.decodeIfPresent(Bool.self, forKey: .showBGTasks) ?? false
        autoFetchEnabled = try c.decode(Bool.self, forKey: .autoFetchEnabled)
        autoRefreshEnabled = try c.decode(Bool.self, forKey: .autoRefreshEnabled)
        autoFetchTiming = try c.decode(AutoFetchTimingDTO.self, forKey: .autoFetchTiming)
    }
}

/// Codable mirror of FetchTriggerConfiguration.AutoFetchTiming. Swift can't
/// synthesize Codable for an enum with associated values without a manual
/// CodingKeys/case split, so this is an explicit struct-shaped DTO instead
/// — simpler to keep stable across schema versions than a raw enum.
struct AutoFetchTimingDTO: Codable, Sendable, Equatable {
    var type: String // "sunriseRelative" | "fixedTime"
    var offsetMinutes: Int?
    var hour: Int?
    var minute: Int?

    static func from(_ timing: FetchTriggerConfiguration.AutoFetchTiming) -> AutoFetchTimingDTO {
        switch timing {
        case .sunriseRelative(let offset):
            return AutoFetchTimingDTO(type: "sunriseRelative", offsetMinutes: offset, hour: nil, minute: nil)
        case .fixedTime(let hour, let minute):
            return AutoFetchTimingDTO(type: "fixedTime", offsetMinutes: nil, hour: hour, minute: minute)
        }
    }

    func toDomain() -> FetchTriggerConfiguration.AutoFetchTiming {
        if type == "fixedTime", let hour, let minute {
            return .fixedTime(hour: hour, minute: minute)
        }
        return .sunriseRelative(offsetMinutes: offsetMinutes ?? -30)
    }
}

// MARK: - API Key

struct APIKeyDTO: Codable, Sendable, Equatable {
    var id: UUID
    var name: String
    /// Encrypted at rest in the file — see BackupService.encrypt/decrypt.
    var keyValueEncrypted: String
    var isEnabled: Bool
    var dailyQuotaLimit: Int
    var reservedQuota: Int
    var createdAt: Date
}

// MARK: - PV Site

struct PVSiteDTO: Codable, Sendable, Equatable {
    var id: UUID
    var name: String
    /// Encrypted at rest — see BackupService.encrypt/decrypt.
    var solcastSiteIDEncrypted: String
    var colorHex: String
    var apiKeyID: UUID?
    var createdAt: Date
}

// MARK: - Location

struct LocationDTO: Codable, Sendable, Equatable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
}

// MARK: - Forecast Point
// Named with a _Backup suffix to avoid colliding with the existing
// ForecastPointDTO used for the Solcast API response shape, which has
// different fields (periodEnd string + period string, no periodStart, no
// isMock) and serves a completely different purpose.

struct ForecastPointDTO_Backup: Codable, Sendable, Equatable {
    var pointID: String
    var pvSiteID: UUID
    var periodStart: Date
    var periodEnd: Date
    var period: String
    var pvEstimate: Double
    var pvEstimate10: Double
    var pvEstimate90: Double
    var isMock: Bool
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case wrongKind(expected: BackupKind, found: BackupKind)
    case missingSettings
    case missingData
    /// The final SwiftData save during import failed. Previously this was
    /// silently discarded (try? ctx.save()) — the import UI would show no
    /// error at all, even though nothing was actually persisted.
    case persistenceFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "This backup was created by a newer version of SolarCast (format v\(v)) and can't be read."
        case .wrongKind(let expected, let found):
            return "Expected a \(expected.rawValue) backup file, but this file contains \(found.rawValue)."
        case .missingSettings:
            return "This file doesn't contain settings data."
        case .missingData:
            return "This file doesn't contain forecast data."
        case .persistenceFailed(let underlying):
            return "Import couldn't be saved: \(underlying)"
        }
    }
}
