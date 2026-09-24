import Foundation

final class MockSolcastAPIClient: SolcastAPIClientProtocol, @unchecked Sendable {
    private let locationRepository: LocationRepository
    private let sunWindowCalculator: SunWindowCalculator
    private let pvSiteRepository: PVSiteRepository
    private let apiKeyRepository: APIKeyRepository

    init(locationRepository: LocationRepository, sunWindowCalculator: SunWindowCalculator,
         pvSiteRepository: PVSiteRepository, apiKeyRepository: APIKeyRepository) {
        self.locationRepository = locationRepository
        self.sunWindowCalculator = sunWindowCalculator
        self.pvSiteRepository = pvSiteRepository
        self.apiKeyRepository = apiKeyRepository
    }

    /// 0 outside the real sun window, tapers smoothly (not an abrupt
    /// cutoff) toward both edges. Peak time is skewed away from true solar
    /// noon by siteBias (fixed for this one generation run) plus a slow
    /// per-day drift across the 7-day span — real day-to-day structure,
    /// not per-call randomness.
    private func shapeFactor(timeOfDayHours: Double, sunriseHours: Double, sunsetHours: Double,
                             dayOffset: Int, siteBias: Double, dayPhase: Double) -> Double {
        guard timeOfDayHours > sunriseHours, timeOfDayHours < sunsetHours else { return 0.0 }
        let window = sunsetHours - sunriseHours
        guard window > 0 else { return 0.0 }
        let trueNoon = sunriseHours + window / 2
        let dayDrift = sin(Double(dayOffset) * 0.5 + dayPhase) * 0.35
        let effectiveNoon = trueNoon + siteBias + dayDrift
        let x = (timeOfDayHours - effectiveNoon) / (window / 2)
        let cosValue = max(0.0, cos(x * .pi / 2))
        return pow(cosValue, 1.5)
    }

    /// Smooth, slot-to-slot correlated variation — sums two sine waves at
    /// different slow frequencies/phases (fixed for this one generation
    /// run) so a "cloud passing" cycle spans roughly 2-6 hours, not one
    /// isolated slot. Range +-25%.
    private func weatherNoise(slotIndex: Int, phase1: Double, phase2: Double, freq1: Double, freq2: Double) -> Double {
        let wave = 0.7 * sin(Double(slotIndex) * freq1 + phase1)
                 + 0.3 * sin(Double(slotIndex) * freq2 + phase2)
        return 1.0 + wave * 0.25
    }

    func fetchForecast(endpoint: SolcastEndpoint) async throws -> [ForecastPointDTO] {
        AppLogger.shared.info("MockSolcastAPIClient: generating mock data for site \(endpoint.solcastSiteID)")
        try await Task.sleep(nanoseconds: 300_000_000)

        let cal = UTCCalendar.calendar

        guard let location = try await locationRepository.fetchCurrent() else {
            AppLogger.shared.error("MockSolcastAPIClient: no location configured, cannot generate sun-window-aware mock data")
            throw NetworkError.unknown("Mock data requires a configured location")
        }

        let now = Date()
        guard let todayWindow = await sunWindowCalculator.resolve(date: now, location: location) else {
            AppLogger.shared.error("MockSolcastAPIClient: could not resolve today's sun window")
            throw NetworkError.unknown("Mock data could not resolve sun window")
        }

        // Start ~30 minutes before today's sunrise, floored to the 30-min
        // grid — matches the app's own grid alignment elsewhere.
        let iv: TimeInterval = 1800
        let flooredSunrise = (todayWindow.sunrise.timeIntervalSince1970 / iv).rounded(.down) * iv
        let start = Date(timeIntervalSince1970: flooredSunrise - iv)

        let siteID = endpoint.solcastSiteID
        let totalSlots = 7 * 24 * 2 // 7*24 hours, 30-min slots

        // Every value below is genuinely random (Double.random, real system
        // entropy), computed ONCE per fetchForecast call and reused across
        // every slot in this run — not derived from a fixed seed string.
        // Two separate calls (e.g. two manual refreshes) now produce
        // different output every time, which is the actual requirement —
        // a deterministic per-day seed (tried previously) still produced
        // identical output for repeated same-day calls, which wasn't what
        // was wanted. Random-ONCE-then-reused (rather than random on every
        // individual value read) is what keeps a single run's curve
        // internally smooth and coherent instead of dissolving into
        // incoherent per-slot noise.
        let hardCapKW = Double.random(in: 6.0...8.0)
        // Split across the REAL number of active sites (assigned to an
        // enabled API key — same rule as DashboardViewModel.activeSites),
        // not a fixed assumed maximum. The earlier fixed /3 split meant a
        // 2-site setup could never reach the real hard cap, since it always
        // reserved a third site's share that didn't exist. max(1, ...)
        // guards against dividing by zero if site/key state is misconfigured
        // at the exact moment this resolves.
        let allSites = (try? await pvSiteRepository.fetchAll()) ?? []
        let enabledKeyIDs = Set(((try? await apiKeyRepository.fetchAll()) ?? []).filter(\.isEnabled).map(\.id))
        let activeSiteCount = max(1, allSites.filter { site in
            guard let keyID = site.apiKeyID else { return false }
            return enabledKeyIDs.contains(keyID)
        }.count)
        let perSiteCapKW = hardCapKW / Double(activeSiteCount)
        let sitePeak = perSiteCapKW * Double.random(in: 0.5...1.0)
        let siteBias = Double.random(in: -0.3...0.3)
        let dayPhase = Double.random(in: 0...(2 * .pi))
        let noisePhase1 = Double.random(in: 0...(2 * .pi))
        let noisePhase2 = Double.random(in: 0...(2 * .pi))
        let noiseFreq1 = Double.random(in: 0.15...0.25)
        let noiseFreq2 = Double.random(in: 0.4...0.7)
        let confidenceSpread = Double.random(in: 0...1)

        // Resolve each real day's sun window once (not per-slot) — a
        // rolling 8-day cache covers every day the 7*24h span could touch.
        // Caches BOTH the resolved SunWindow AND its derived hour-of-day
        // values (sunriseHours/sunsetHours) per day — previously only the
        // SunWindow itself was cached, but sunriseHours/sunsetHours were
        // still recomputed via 4 separate Calendar.component() calls on
        // EVERY slot within that day (~48 slots/day), even though the
        // underlying window hadn't changed. Calendar component extraction
        // does real calendrical computation, not a cheap field read, so
        // this was genuine redundant work — not the dominant cost in this
        // function (which has its own deliberate 300ms artificial delay),
        // but cheap and correct to eliminate regardless.
        var windowCache: [Int: (window: SunWindow, sunriseHours: Double, sunsetHours: Double)] = [:]
        func sunWindow(forDayOffset dayOffset: Int) async -> (window: SunWindow, sunriseHours: Double, sunsetHours: Double)? {
            if let cached = windowCache[dayOffset] { return cached }
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: start) else { return nil }
            guard let w = await sunWindowCalculator.resolve(date: day, location: location) else { return nil }
            let sunriseHours = cal.component(.hour, from: w.sunrise).d + cal.component(.minute, from: w.sunrise).d / 60.0
            let sunsetHours  = cal.component(.hour, from: w.sunset).d  + cal.component(.minute, from: w.sunset).d / 60.0
            let entry = (window: w, sunriseHours: sunriseHours, sunsetHours: sunsetHours)
            windowCache[dayOffset] = entry
            return entry
        }

        var dtos: [ForecastPointDTO] = []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for slot in 0..<totalSlots {
            let periodEnd = start.addingTimeInterval(TimeInterval(slot) * iv + iv)
            let dayOffset = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: periodEnd)).day ?? 0
            guard let dayInfo = await sunWindow(forDayOffset: dayOffset) else { continue }
            let sunriseHours = dayInfo.sunriseHours
            let sunsetHours = dayInfo.sunsetHours
            let hour = cal.component(.hour, from: periodEnd)
            let minute = cal.component(.minute, from: periodEnd)
            let timeOfDayHours = Double(hour) + Double(minute) / 60.0

            let shape = shapeFactor(timeOfDayHours: timeOfDayHours, sunriseHours: sunriseHours, sunsetHours: sunsetHours,
                                    dayOffset: dayOffset, siteBias: siteBias, dayPhase: dayPhase)
            let noise = weatherNoise(slotIndex: slot, phase1: noisePhase1, phase2: noisePhase2, freq1: noiseFreq1, freq2: noiseFreq2)
            let pv = min(sitePeak, sitePeak * shape * noise)

            dtos.append(ForecastPointDTO(
                pvEstimate:   pv,
                pvEstimate10: pv * (0.65 + confidenceSpread * 0.3),
                pvEstimate90: pv * (1.05 + confidenceSpread * 0.2),
                periodEnd:    iso.string(from: periodEnd),
                period:       "PT30M"
            ))
        }

        AppLogger.shared.info("MockSolcastAPIClient: generated \(dtos.count) mock points for site \(siteID), site peak \(String(format: "%.2f", sitePeak))kW, hard cap \(String(format: "%.2f", hardCapKW))kW split across \(activeSiteCount) active site(s)")
        return dtos
    }
}

private extension Int {
    var d: Double { Double(self) }
}
