import Foundation

/// File-based logger that persists to the app's documents directory.
/// Rotates daily at UTC midnight. Thread-safe via serial DispatchQueue.
final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private static let enabledKey = "solarcast.loggingEnabled"

    /// Whether logging is enabled. Persisted in UserDefaults. Defaults to true.
    var isEnabled: Bool {
        get {
            // Default to true if never set
            if UserDefaults.standard.object(forKey: Self.enabledKey) == nil { return false }
            return UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// Deletes every stored log file immediately, synchronously on the
    /// calling thread — not queued on the background logging queue like
    /// cleanupOldLogs(), since "disable logging" is expected to remove the
    /// data right away, not eventually. Call this when logging is turned
    /// off; it does not touch the isEnabled flag itself.
    func deleteAllLogs() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    private let queue = DispatchQueue(label: "com.ioanmihaila.solarcast.logger")
    private(set) var lastCleanupDate: Date = .distantPast
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var logsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Logs", isDirectory: true)
    }

    private init() {
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        if isEnabled { cleanupOldLogs() }
    }

    /// The next UTC-midnight boundary at or after `now`. This is what "Next
    /// cleanup" in the UI actually means — old files are removed by
    /// cleanupOldLogs() whenever it runs (hourly while logging is active,
    /// or at launch), based on a 48h age cutoff, not on a literal midnight
    /// timer. But the intended rotation boundary IS midnight UTC, so the
    /// UI should show that, not an arbitrary "last write + 1h" value.
    func nextCleanupBoundary(now: Date = Date()) -> Date {
        let cal = UTCCalendar.calendar
        let startOfToday = cal.startOfDay(for: now)
        if let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) {
            return startOfTomorrow
        }
        return now.addingTimeInterval(86400) // fallback, should never hit
    }

    // MARK: - Public API

    func log(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
        guard isEnabled else { return }
        if Date().timeIntervalSince(lastCleanupDate) > 3600 {
            lastCleanupDate = Date()
            cleanupOldLogs()
        }
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let entry = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"

        // Also print to console
        print(entry.trimmingCharacters(in: .newlines))

        queue.async { [weak self] in
            self?.appendToFile(entry)
        }
    }

    func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }

    func warn(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warn, file: file, line: line)
    }

    func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }

    func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }

    func step(_ step: Int, _ message: String, file: String = #file, line: Int = #line) {
        log("STEP \(step) — \(message)", level: .info, file: file, line: line)
    }

    func stepFailed(_ step: Int, _ message: String, file: String = #file, line: Int = #line) {
        log("STEP \(step) FAILED — \(message)", level: .error, file: file, line: line)
    }

    /// Returns the log content for the past 24 hours (today + yesterday UTC).
    func logsForPast24Hours() -> String {
        let today = fileDateFormatter.string(from: Date())
        let yesterday = fileDateFormatter.string(from: Date().addingTimeInterval(-86400))

        var combined = ""
        for dateStr in [yesterday, today] {
            let url = logFileURL(for: dateStr)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                combined += content
            }
        }

        if combined.isEmpty {
            return "No logs available for the past 24 hours."
        }
        return combined
    }

    /// Returns a temporary file URL containing the past 24 hours of logs,
    /// suitable for sharing via UIActivityViewController.
    func exportLogsFile() -> URL? {
        let content = logsForPast24Hours()
        let timestamp = fileDateFormatter.string(from: Date())
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("solarcast-log-\(timestamp).txt")
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to write log export: \(error)")
            return nil
        }
    }

    // MARK: - Private

    private func logFileURL(for dateString: String) -> URL {
        logsDirectory.appendingPathComponent("solarcast-\(dateString).log")
    }

    private func todayLogFile() -> URL {
        logFileURL(for: fileDateFormatter.string(from: Date()))
    }

    private func appendToFile(_ entry: String) {
        let url = todayLogFile()
        if fileManager.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Removes log files older than 48 hours.
    func cleanupOldLogs() {
        cleanupOldLogs(completion: nil)
    }

    /// Same cleanup, with a completion callback — used by the background
    /// task so it can call setTaskCompleted only once the sweep genuinely
    /// finishes, rather than immediately after firing it onto the queue.
    func cleanupOldLogs(completion: (() -> Void)?) {
        queue.async { [weak self] in
            guard let self = self else { completion?(); return }
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            guard let files = try? self.fileManager.contentsOfDirectory(
                at: self.logsDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
                completion?(); return
            }
            for file in files {
                guard let attrs = try? self.fileManager.attributesOfItem(atPath: file.path),
                      let created = attrs[.creationDate] as? Date,
                      created < cutoff else { continue }
                try? self.fileManager.removeItem(at: file)
            }
            completion?()
        }
    }
}

enum LogLevel: String {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
}

/// Convenience global function
func appLog(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
    AppLogger.shared.log(message, level: level, file: file, line: line)
}

extension Notification.Name {
    static let settingsImported = Notification.Name("solarcast.settingsImported")
    /// Posted when a staleness-triggered fetch (cold launch or resume)
    /// actually wrote new forecast data. AppDelegate has no reference to
    /// any view model, so this is how it tells the dashboard "reload
    /// yourself" without one — same pattern as .settingsImported.
    static let forecastDataRefreshed = Notification.Name("solarcast.forecastDataRefreshed")
    /// Posted after DIContainer.reloadAPIClient() completes — the mock/real
    /// data toggle in DeveloperSettingsCard fired this off as a bare
    /// Task { await reloadAPIClient() } with nothing observing completion,
    /// so the Dashboard kept showing whatever it last loaded (a mix of
    /// stale chart/stats/breakdown state from before the switch) until
    /// something UNRELATED happened to trigger a reload — producing
    /// exactly the "summary doesn't match chart" symptom this notification
    /// exists to fix, by explicitly telling the dashboard to reload
    /// everything once the mode switch has actually finished.
    static let mockModeChanged = Notification.Name("solarcast.mockModeChanged")
    /// Posted by BGTaskCoordinator right after any real change to the
    /// pending com.ioanmihaila.solarcast.worker task — a new one submitted, an
    /// existing one cancelled, or the OS invoking it and the app
    /// rescheduling the next one at completion. Lets a live UI section
    /// (the "BGTaskScheduler background tasks" toggle in
    /// DeveloperSettingsCard) stay current without polling or needing a
    /// manual refresh button.
    static let pendingBGTasksChanged = Notification.Name("solarcast.pendingBGTasksChanged")
    /// Posted after any real quota-consuming action (manual refresh via
    /// DashboardViewModel, a completed background auto-fetch/auto-refresh
    /// via BGTaskCoordinator.handleWorker, or a stale-check-triggered
    /// fetch via FetchForecastUseCase.executeAppLaunchIfStale) reschedules
    /// the actual background task. The reschedule itself is already
    /// correctly wired end to end (SchedulingEngine.computeNextRefresh
    /// genuinely reflects live quota usage) — but that only updates the
    /// real BGTaskScheduler state, which the pending-tasks debug card
    /// reads directly and live. SettingsViewModel's own displayed
    /// nextAutoRefreshTime/computedRefreshIntervalMinutes are a SEPARATE,
    /// cached computation that only refreshes when reloadQuotaTimes()
    /// itself runs — with nothing telling it to do so when quota changed
    /// elsewhere in the app while the Settings sheet happened to already
    /// be open. This notification closes that gap for that specific case.
    static let quotaAffectingRescheduleOccurred = Notification.Name("solarcast.quotaAffectingRescheduleOccurred")
}
