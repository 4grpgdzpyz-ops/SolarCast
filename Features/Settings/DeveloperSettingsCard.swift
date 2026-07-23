import SwiftUI
import BackgroundTasks

struct DeveloperSettingsCard: View {
    // BG tasks section — first, per direct instruction.
    @State private var showBGTasks = UserDefaults.standard.bool(forKey: "solarcast.showBGTasks")
    @State private var pendingTasks: [PendingTaskSummary] = []

    struct PendingTaskSummary: Identifiable {
        let id = UUID()
        let identifier: String
        let earliestBeginDate: Date?
    }

    @State private var useMock = UserDefaults.standard.bool(forKey: "solarcast.useMockData")
    @State private var showMockConfirm = false
    @State private var pendingMockValue = false
    @State private var loggingEnabled = AppLogger.shared.isEnabled

    private var logFileURL: URL {
        let content = AppLogger.shared.logsForPast24Hours()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("solarcast-log-\(fmt.string(from: Date())).log")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private var nextCleanupTime: String {
        let next = AppLogger.shared.nextCleanupBoundary()
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: next) + " UTC"
    }

    var body: some View {
        SettingsCard(title: "Developer") {
            VStack(alignment: .leading, spacing: 10) {
                // BG tasks — first, per direct instruction.
                Toggle(isOn: $showBGTasks) {
                    Text("BGTaskScheduler").font(.system(size: 13)).foregroundStyle(Color.scText)
                }
                .tint(Color.scAccent)
                .onChange(of: showBGTasks) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "solarcast.showBGTasks")
                    if newValue { Task { await refreshPendingTasks() } }
                }

                Text("View scheduled background tasks")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.scMuted)

                if showBGTasks {
                    if pendingTasks.isEmpty {
                        Text("No pending requests")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.scMuted)
                    } else {
                        ForEach(pendingTasks) { task in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.identifier)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.scText)
                                Text(task.earliestBeginDate.map { "earliestBeginDate: \($0)" } ?? "earliestBeginDate: nil")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.scMuted)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Divider().padding(.vertical, 2)

                // Mock data — second.
                Toggle(isOn: Binding(
                    get: { useMock },
                    set: { newValue in
                        pendingMockValue = newValue
                        showMockConfirm = true
                    }
                )) {
                    Text("Use mock data").font(.system(size: 13)).foregroundStyle(Color.scText)
                }
                .tint(Color.scAccent)

                Text(useMock
                     ? "Mock mode: Generates simulated forecast data."
                     : "Live mode: Using Solcast API data and consuming quota.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.scMuted)

                Divider().padding(.vertical, 2)

                // Logging — third.
                Toggle(isOn: $loggingEnabled) {
                    Text("Enable logging").font(.system(size: 13)).foregroundStyle(Color.scText)
                }
                .tint(Color.scAccent)
                .onChange(of: loggingEnabled) { _, newValue in
                    AppLogger.shared.isEnabled = newValue
                    if !newValue { AppLogger.shared.deleteAllLogs() }
                    // Logging is one of the three real scheduling
                    // conditions (auto-fetch, auto-refresh, logging) —
                    // SchedulingEngine.nextScheduledFetch reads
                    // AppLogger.shared.isEnabled directly when computing
                    // candidates, so toggling this needs to trigger the
                    // same real recomputation any other settings change
                    // does, not a separate submit/cancel path of its own.
                    Task {
                        guard let ctx = await DIContainer.shared.loadSchedulingContext(), let loc = ctx.1 else { return }
                        await DIContainer.shared.makeBGTaskCoordinator().scheduleNext(config: ctx.0, location: loc)
                    }
                }

                if loggingEnabled {
                    ShareLink(item: logFileURL) {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Download Logs (24h)")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.scAccent)
                        .background(Color.scAccent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.scAccent,
                                          style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                }

                Text(loggingEnabled
                     ? "Logs are cleaned up daily at UTC midnight."
                     : "Logging is disabled. No data is being written to disk.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.scMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if loggingEnabled {
                    Text("Next cleanup: \(nextCleanupTime)")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.scGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .alert(pendingMockValue ? "Enable Mock Data?" : "Disable Mock Data?",
               isPresented: $showMockConfirm) {
            Button(pendingMockValue ? "Enable" : "Disable",
                   role: pendingMockValue ? nil : .destructive) {
                useMock = pendingMockValue
                UserDefaults.standard.set(pendingMockValue, forKey: "solarcast.useMockData")
                AppLogger.shared.info("Settings changed: mock data -> \(pendingMockValue)")
                Task {
                    await DIContainer.shared.reloadAPIClient()
                    await MainActor.run {
                        NotificationCenter.default.post(name: .mockModeChanged, object: nil)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                // Don't change anything — Toggle reverts because useMock didn't change
            }
        } message: {
            Text(pendingMockValue
                 ? "This will use simulated data instead of real Solcast API data."
                 : "This will switch back to real Solcast API data.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsImported)) { _ in
            // Combined handler for both merged sections' state — a single
            // view can't cleanly stack two separate onReceive(.settingsImported)
            // modifiers the way each card had independently before merging.
            useMock = UserDefaults.standard.bool(forKey: "solarcast.useMockData")
            loggingEnabled = AppLogger.shared.isEnabled
            showBGTasks = UserDefaults.standard.bool(forKey: "solarcast.showBGTasks")
        }
        .onReceive(NotificationCenter.default.publisher(for: .pendingBGTasksChanged)) { _ in
            // Live refresh whenever BGTaskCoordinator actually changes the
            // pending worker task — scheduled, cancelled, or rescheduled
            // at completion. Only refetches while the section is actually
            // visible, since there's no reason to query the OS for a list
            // nobody can see.
            if showBGTasks {
                Task { await refreshPendingTasks() }
            }
        }
    }

    private func refreshPendingTasks() async {
        let pending = await DIContainer.shared.makeBGTaskCoordinator().pendingRequests()
        pendingTasks = pending.map { PendingTaskSummary(identifier: $0.identifier, earliestBeginDate: $0.earliestBeginDate) }
    }
}
