import XCTest
import SwiftData
@testable import SolarCast

/// Integration-style (real in-memory SwiftData, not mocked) — BackupService
/// takes a concrete ModelContainer, not an injectable repository protocol,
/// so this mirrors PersistenceIntegrationTests' established pattern rather
/// than attempting to unit-test it in isolation.
final class BackupServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var backupService: BackupService!
    private var siteRepo: SwiftDataPVSiteRepository!
    private var keyRepo: SwiftDataAPIKeyRepository!
    private var locationRepo: SwiftDataLocationRepository!

    override func setUp() async throws {
        container = try ModelContainerFactory.makeInMemoryContainer()
        backupService = BackupService(modelContainer: container)
        siteRepo = SwiftDataPVSiteRepository(modelContainer: container)
        keyRepo = SwiftDataAPIKeyRepository(modelContainer: container)
        locationRepo = SwiftDataLocationRepository(modelContainer: container)
    }

    /// UserDefaults.standard is genuinely global/shared, unlike the
    /// in-memory ModelContainer above (which is fresh and isolated per
    /// test). No other test file in this codebase touches it directly —
    /// this is the first, so cleaning up explicitly here rather than
    /// leaving these keys to leak into subsequent test runs.
    override func tearDown() {
        let d = UserDefaults.standard
        for key in ["solarcast.appTheme", "solarcast.useMockData", "solarcast.loggingEnabled",
                    "solarcast.showBGTasks",
                    "solarcast.fetchTrigger.autoFetchEnabled", "solarcast.fetchTrigger.autoRefreshEnabled",
                    "solarcast.fetchTrigger.timingType", "solarcast.fetchTrigger.timingOffset",
                    "solarcast.fetchTrigger.timingHour", "solarcast.fetchTrigger.timingMinute"] {
            d.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Settings export/import round-trip

    func test_settingsBackup_roundTrips_preservesValues() async throws {
        UserDefaults.standard.set("dark", forKey: "solarcast.appTheme")
        UserDefaults.standard.set(true, forKey: "solarcast.useMockData")
        FetchTriggerConfigurationStore.save(FetchTriggerConfiguration(
            autoFetchEnabled: true,
            autoFetchTiming: .sunriseRelative(offsetMinutes: -45),
            autoRefreshEnabled: true))

        let backup = await backupService.createSettingsBackup()
        XCTAssertEqual(backup.kind, .settings)
        XCTAssertEqual(backup.version, AppBackup.currentVersion)

        // Change the live settings AFTER export, to prove import actually
        // restores from the backup rather than the change being a no-op
        // against unchanged live state.
        FetchTriggerConfigurationStore.save(FetchTriggerConfiguration(
            autoFetchEnabled: false,
            autoFetchTiming: .sunriseRelative(offsetMinutes: 0),
            autoRefreshEnabled: false))

        try await backupService.importBackup(backup, expecting: .settings)

        let restored = FetchTriggerConfigurationStore.load()
        XCTAssertTrue(restored.autoFetchEnabled)
        XCTAssertTrue(restored.autoRefreshEnabled)
        if case .sunriseRelative(let offset) = restored.autoFetchTiming {
            XCTAssertEqual(offset, -45)
        } else {
            XCTFail("Expected sunriseRelative timing to survive the round-trip")
        }
    }

    // MARK: - API key / site encryption round-trip
    //
    // These don't test the encryption ALGORITHM directly (encrypt/decrypt
    // are private) — they test the observable contract that matters:
    // a real, sensitive value (an API key, a Solcast site ID) survives a
    // full export-then-import cycle completely unchanged, despite being
    // encrypted at rest in the exported JSON in between.

    func test_apiKeyBackup_roundTrips_keyValueSurvivesEncryption() async throws {
        try await keyRepo.save(TestFixtures.primaryKey)

        let backup = await backupService.createSettingsBackup()
        let exportedKeyDTO = try XCTUnwrap(backup.apiKeys?.first(where: { $0.id == TestFixtures.apiKeyID }))

        // The exported field must NOT contain the real key value in plain
        // text — that's the whole point of encrypting it at rest.
        XCTAssertNotEqual(exportedKeyDTO.keyValueEncrypted, TestFixtures.primaryKey.keyValue)
        XCTAssertFalse(exportedKeyDTO.keyValueEncrypted.isEmpty)

        // Wipe the real entity, then import the backup — the real value
        // must come back exactly as it was.
        try await keyRepo.delete(id: TestFixtures.apiKeyID)
        XCTAssertNil(try await keyRepo.fetch(id: TestFixtures.apiKeyID))

        try await backupService.importBackup(backup, expecting: .settings)

        let restoredKey = try await keyRepo.fetch(id: TestFixtures.apiKeyID)
        XCTAssertEqual(restoredKey?.keyValue, TestFixtures.primaryKey.keyValue)
    }

    func test_pvSiteBackup_roundTrips_solcastSiteIDSurvivesEncryption() async throws {
        try await keyRepo.save(TestFixtures.primaryKey)
        try await siteRepo.save(TestFixtures.siteEast)

        let backup = await backupService.createSettingsBackup()
        let exportedSiteDTO = try XCTUnwrap(backup.pvSites?.first(where: { $0.id == TestFixtures.siteEastID }))

        XCTAssertNotEqual(exportedSiteDTO.solcastSiteIDEncrypted, TestFixtures.siteEast.solcastSiteID)

        try await siteRepo.delete(id: TestFixtures.siteEastID)
        try await backupService.importBackup(backup, expecting: .settings)

        let restoredSite = try await siteRepo.fetch(id: TestFixtures.siteEastID)
        XCTAssertEqual(restoredSite?.solcastSiteID, TestFixtures.siteEast.solcastSiteID)
    }

    // MARK: - Data backup includes forecast points; settings backup does not

    func test_dataBackup_includesForecastPoints_settingsBackupDoesNot() async throws {
        try await keyRepo.save(TestFixtures.primaryKey)
        try await siteRepo.save(TestFixtures.siteEast)
        // Seed a real forecast point via the actual repository, same
        // ModelContainer BackupService reads from.
        let forecastRepo = SwiftDataForecastRepository(modelContainer: container)
        let point = TestFixtures.point(pvSiteID: TestFixtures.siteEastID, periodEnd: Date(), pvEstimate: 3.5)
        try await forecastRepo.upsert(points: [point])

        let dataBackup = await backupService.createDataBackup()
        XCTAssertEqual(dataBackup.kind, .data)
        XCTAssertEqual(dataBackup.forecastPoints?.count, 1)

        let settingsBackup = await backupService.createSettingsBackup()
        XCTAssertEqual(settingsBackup.kind, .settings)
        XCTAssertNil(settingsBackup.forecastPoints, "A settings-only backup must not include forecast data")
    }

    // MARK: - Kind mismatch rejection

    func test_import_rejectsWrongKind() async throws {
        try await keyRepo.save(TestFixtures.primaryKey)
        let dataBackup = await backupService.createDataBackup()

        do {
            try await backupService.importBackup(dataBackup, expecting: .settings)
            XCTFail("Expected importBackup to throw when kinds don't match")
        } catch let error as BackupError {
            if case .wrongKind(let expected, let found) = error {
                XCTAssertEqual(expected, .settings)
                XCTAssertEqual(found, .data)
            } else {
                XCTFail("Expected .wrongKind, got \(error)")
            }
        }
    }

    // MARK: - Unsupported version rejection

    func test_import_rejectsUnsupportedVersion() async throws {
        var backup = await backupService.createSettingsBackup()
        // AppBackup.init always sets version = currentVersion; simulate a
        // backup from a hypothetical future app version by overwriting it
        // afterward — version is a plain mutable var specifically to make
        // this kind of forward-compatibility testing possible without
        // needing to hand-construct raw JSON.
        backup.version = AppBackup.currentVersion + 1

        do {
            try await backupService.importBackup(backup, expecting: .settings)
            XCTFail("Expected importBackup to throw for an unsupported future version")
        } catch let error as BackupError {
            if case .unsupportedVersion(let v) = error {
                XCTAssertEqual(v, AppBackup.currentVersion + 1)
            } else {
                XCTFail("Expected .unsupportedVersion, got \(error)")
            }
        }
    }

    // MARK: - Missing content rejection

    func test_import_rejectsSettingsBackupWithNilSettings() async throws {
        // Construct a malformed "settings" backup with settings == nil —
        // shouldn't normally happen via createSettingsBackup(), but
        // importBackup must defend against it regardless (e.g. a
        // hand-edited or corrupted file).
        var backup = AppBackup(kind: .settings)
        backup.settings = nil

        do {
            try await backupService.importBackup(backup, expecting: .settings)
            XCTFail("Expected importBackup to throw for a settings backup with no settings payload")
        } catch let error as BackupError {
            if case .missingSettings = error {
                // expected
            } else {
                XCTFail("Expected .missingSettings, got \(error)")
            }
        }
    }

    // MARK: - Location round-trip

    func test_locationBackup_roundTrips() async throws {
        let location = UserLocation(name: "Home", latitude: 51.5, longitude: -0.1)
        try await locationRepo.save(location)

        let backup = await backupService.createSettingsBackup()
        XCTAssertEqual(backup.location?.name, "Home")

        try await locationRepo.delete()
        XCTAssertNil(try await locationRepo.fetchCurrent())

        try await backupService.importBackup(backup, expecting: .settings)

        let restored = try await locationRepo.fetchCurrent()
        XCTAssertEqual(restored?.name, "Home")
        XCTAssertEqual(restored?.latitude, 51.5, accuracy: 0.0001)
        XCTAssertEqual(restored?.longitude, -0.1, accuracy: 0.0001)
    }
}
