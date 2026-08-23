import Foundation
import BackgroundTasks

/// Owns all BGTaskScheduler interaction for the app — TWO real
/// background tasks, genuinely different real request types:
///
/// - `refreshTaskID` (BGAppRefreshTaskRequest): auto-fetch and every
///   enabled API key's own auto-refresh — short, periodic work.
/// - `maintenanceTaskID` (BGProcessingTaskRequest): daily quota-usage
///   and log cleanup — longer-budgeted, heavier real work (Apple's own
///   documented use case for this request type explicitly includes
///   database maintenance, which is genuinely what this job does).
///
/// This app previously used TWO identifiers that were BOTH
/// BGAppRefreshTaskRequest — a real, confirmed bug, since that request
/// type has an app-wide limit of exactly ONE pending request at a
/// time, shared ACROSS every identifier of that same type, not a
/// separate budget per identifier. The two were silently competing for
/// one shared slot. Consolidating to a single BGAppRefreshTaskRequest
/// identifier fixed that. Splitting fetch/refresh and maintenance
/// across these TWO, genuinely DIFFERENT real request types is safe
/// in the same way the original two-identifier design was NOT:
/// BGAppRefreshTaskRequest and BGProcessingTaskRequest each have their
/// own, real, independent scheduling budget — they do not share the
/// same real, single-slot constraint the original bug depended on.
///
/// scheduleNext() computes the earliest upcoming trigger across
/// auto-fetch, every enabled API key's auto-refresh, and daily
/// maintenance — each independently gated on its own real enabled
/// state — and submits to WHICHEVER of the two real identifiers that
/// specific winning trigger belongs to. The other identifier's own,
/// separate pending request (if any) is left alone, since the two are
/// now genuinely independent, not competing for one shared slot.
final class BGTaskCoordinator {
    static let refreshTaskID = "com.ioanmihaila.solarcast.refresh"
    static let maintenanceTaskID = "com.ioanmihaila.solarcast.maintenance"

    /// What kind of work the currently-pending refresh task represents,
    /// and (for refresh) which key. Persisted as a raw string + optional
    /// UUID string pair rather than trying to encode the whole
    /// ScheduledTrigger, since UserDefaults has no native support for
    /// arbitrary enums. Only .fetch/.refresh are ever persisted here —
    /// .logCleanup has its own, separate real task identifier now, with
    /// no metadata handoff needed at all (it's the only real kind of
    /// work that identifier ever does).
    private static let pendingTriggerKindKey = "solarcast.pendingTriggerKind"
    private static let pendingRefreshKeyIDDefaultsKey = "solarcast.pendingRefreshKeyID"
    enum PendingTriggerKind: String {
        case fetch, refresh, logCleanup
    }

    private let fetchForecastUseCase: FetchForecastUseCase
    private let schedulingEngine: SchedulingEngine
    init(fetchForecastUseCase: FetchForecastUseCase, schedulingEngine: SchedulingEngine) {
        self.fetchForecastUseCase = fetchForecastUseCase; self.schedulingEngine = schedulingEngine
    }

    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { [weak self] task in
            self?.handleRefresh(task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.maintenanceTaskID, using: nil) { [weak self] task in
            self?.handleMaintenance(task as! BGProcessingTask)
        }
    }

    /// Queries the OS directly for what's actually pending, right now —
    /// not just "did submit() return without throwing," which only
    /// confirms the REQUEST was accepted, not what the OS still genuinely
    /// has queued a moment later. getPendingTaskRequests is
    /// completion-handler based, not async, so this bridges it into the
    /// async callers below via withCheckedContinuation.
    func pendingRequests() async -> [BGTaskRequest] {
        await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func logPendingRequests() async {
        let requests = await pendingRequests()
        if requests.isEmpty {
            AppLogger.shared.info("BGTaskCoordinator: getPendingTaskRequests — no pending requests")
        } else {
            for req in requests {
                AppLogger.shared.info("BGTaskCoordinator: pending request — \(req.identifier), earliestBeginDate=\(req.earliestBeginDate?.description ?? "nil")")
            }
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .pendingBGTasksChanged, object: nil)
        }
    }

    /// Computes the earliest of (auto-fetch, every enabled key's
    /// auto-refresh, log cleanup) — each independently gated on its own
    /// real enabled state inside SchedulingEngine.nextScheduledFetch — and
    /// submits ONE request for whichever wins. If none are enabled (or
    /// none produce a valid trigger), any existing pending request is
    /// actively cancelled — skipping a new submission doesn't retroactively
    /// remove an old one still sitting in the OS queue from before.
    /// Independently schedules BOTH real, genuinely separate background
    /// tasks — refresh (fetch/refresh, whichever wins) and maintenance
    /// (always, unconditionally the next UTC midnight). Neither depends
    /// on or is gated by the other; each has its own real, independent
    /// BGTaskScheduler slot and its own real submission logic below.
    func scheduleNext(config: FetchTriggerConfiguration, location: UserLocation) async {
        await scheduleRefresh(config: config, location: location)
        await scheduleMaintenance()
    }

    /// Computes the earliest of (auto-fetch, every enabled key's
    /// auto-refresh) — each independently gated on its own real enabled
    /// state inside SchedulingEngine.nextScheduledFetch — and submits to
    /// refreshTaskID for whichever wins. If neither is enabled (or
    /// neither produces a valid trigger), any existing pending refresh
    /// request is actively cancelled — skipping a new submission doesn't
    /// retroactively remove an old one still sitting in the OS queue.
    private func scheduleRefresh(config: FetchTriggerConfiguration, location: UserLocation) async {
        guard let trigger = await schedulingEngine.nextScheduledFetch(config: config, location: location) else {
            AppLogger.shared.info("BGTaskCoordinator: scheduleRefresh skipped submission — no trigger returned by SchedulingEngine (see SchedulingEngine log lines above for the specific reason)")
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
            UserDefaults.standard.removeObject(forKey: Self.pendingTriggerKindKey)
            UserDefaults.standard.removeObject(forKey: Self.pendingRefreshKeyIDDefaultsKey)
            AppLogger.shared.info("BGTaskCoordinator: cancelled pending refresh task")
            await logPendingRequests()
            return
        }
        let d = UserDefaults.standard

        // Skip resubmission entirely if the OS already has a pending
        // refresh request whose date AND kind/key genuinely, exactly
        // match this new trigger.
        let currentlyPending = await pendingRequests().first(where: { $0.identifier == Self.refreshTaskID })
        if let pendingDate = currentlyPending?.earliestBeginDate, pendingDate == trigger.date {
            let currentKind = PendingTriggerKind(rawValue: d.string(forKey: Self.pendingTriggerKindKey) ?? "")
            let currentKeyID = d.string(forKey: Self.pendingRefreshKeyIDDefaultsKey)
            let sameKindAndKey: Bool
            switch trigger {
            case .fetch:
                sameKindAndKey = currentKind == .fetch
            case .refresh(_, let apiKeyID):
                sameKindAndKey = currentKind == .refresh && currentKeyID == apiKeyID.uuidString
            case .logCleanup:
                sameKindAndKey = false // genuinely unreachable — nextScheduledFetch never returns this case
            }
            if sameKindAndKey {
                AppLogger.shared.info("BGTaskCoordinator: scheduleRefresh skipped resubmission — already scheduled at \(pendingDate), kind/key unchanged")
                await logPendingRequests()
                return
            }
        }

        let req = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        req.earliestBeginDate = trigger.date

        switch trigger {
        case .fetch:
            d.set(PendingTriggerKind.fetch.rawValue, forKey: Self.pendingTriggerKindKey)
            d.removeObject(forKey: Self.pendingRefreshKeyIDDefaultsKey)
        case .refresh(_, let apiKeyID):
            d.set(PendingTriggerKind.refresh.rawValue, forKey: Self.pendingTriggerKindKey)
            d.set(apiKeyID.uuidString, forKey: Self.pendingRefreshKeyIDDefaultsKey)
        case .logCleanup:
            break // genuinely unreachable
        }

        do {
            try BGTaskScheduler.shared.submit(req)
            AppLogger.shared.info("BGTaskCoordinator: scheduled next refresh task (\(trigger)) for \(trigger.date)")
            await logPendingRequests()
        } catch {
            AppLogger.shared.error("BGTaskCoordinator: failed to submit refresh task request: \(error)")
        }
    }

    /// Always, unconditionally submits the next UTC-midnight maintenance
    /// trigger to maintenanceTaskID — genuinely never cancelled, since
    /// there's no real scenario where maintenance has nothing to do
    /// (quota-usage cleanup always runs; log cleanup within it is
    /// separately gated on the logging toggle inside handleMaintenance
    /// itself, not here).
    private func scheduleMaintenance() async {
        let trigger = await schedulingEngine.nextMaintenance()
        guard case .logCleanup(let date) = trigger else { return } // always true in practice

        let currentlyPending = await pendingRequests().first(where: { $0.identifier == Self.maintenanceTaskID })
        if let pendingDate = currentlyPending?.earliestBeginDate, pendingDate == date {
            AppLogger.shared.info("BGTaskCoordinator: scheduleMaintenance skipped resubmission — already scheduled at \(pendingDate)")
            await logPendingRequests()
            return
        }

        let req = BGProcessingTaskRequest(identifier: Self.maintenanceTaskID)
        req.earliestBeginDate = date
        // Deliberately left unset (both default false) — this app never
        // explicitly requires external power or network connectivity for
        // maintenance; adding either would only narrow the real,
        // already-limited windows iOS chooses to run it in, not broaden
        // them.
        do {
            try BGTaskScheduler.shared.submit(req)
            AppLogger.shared.info("BGTaskCoordinator: scheduled next maintenance task for \(date)")
            await logPendingRequests()
        } catch {
            AppLogger.shared.error("BGTaskCoordinator: failed to submit maintenance task request: \(error)")
        }
    }

    /// Cancels the currently-pending worker task, if any. Used when
    /// nextScheduledFetch produces no candidate at all — auto-fetch,
    /// auto-refresh, and logging are all disabled (or none produced a
    /// valid trigger) — since there's nothing left to wake the app for.
    /// Cancels both currently-pending tasks, if any — used when
    /// nextScheduledFetch produces no candidate at all across EITHER
    /// real identifier (auto-fetch, auto-refresh, and logging are all
    /// disabled, or none produced a valid trigger), since there's
    /// nothing left to wake the app for on either one.
    private func handleRefresh(_ task: BGAppRefreshTask) {
        AppLogger.shared.info("BGTaskCoordinator: OS invoked handleRefresh (task \(task.identifier))")
        let work = Task { [weak self] in
            guard let self else { return }
            let d = UserDefaults.standard
            let kind = PendingTriggerKind(rawValue: d.string(forKey: Self.pendingTriggerKindKey) ?? "")
            do {
                switch kind {
                case .refresh:
                    if let keyIDString = d.string(forKey: Self.pendingRefreshKeyIDDefaultsKey),
                       let keyID = UUID(uuidString: keyIDString) {
                        await BadgeManager.shared.postJobStartedBanner(kind: .refresh)
                        try await fetchForecastUseCase.executeAutoRefresh(apiKeyID: keyID)
                        AppLogger.shared.info("BGTaskCoordinator: background auto-refresh completed successfully (key \(keyID))")
                    } else {
                        AppLogger.shared.error("BGTaskCoordinator: pending kind was .refresh but no valid key ID was persisted — skipping")
                    }
                case .fetch, .none, .logCleanup:
                    // .none covers both "never set" (shouldn't happen if
                    // scheduleNext always persists a kind before
                    // submitting) and any decode failure — falling back
                    // to the same behavior .fetch always had (touch every
                    // eligible site) is the safest default, since it's
                    // the one path that was never key-specific to begin
                    // with. .logCleanup is genuinely unreachable here now
                    // — that real kind of work has its own, separate
                    // maintenanceTaskID/handleMaintenance entirely — but
                    // included for real, exhaustive switch coverage.
                    await BadgeManager.shared.postJobStartedBanner(kind: .fetch)
                    try await fetchForecastUseCase.executeAutoFetch()
                    AppLogger.shared.info("BGTaskCoordinator: background auto-fetch completed successfully")
                }
                task.setTaskCompleted(success: true)
            } catch {
                AppLogger.shared.error("BGTaskCoordinator: background refresh task failed: \(error)")
                task.setTaskCompleted(success: false)
            }
            // Badge reflects "a job ran while you weren't looking," not
            // "a job succeeded" — incremented regardless of which branch
            // above actually ran or whether it threw.
            await BadgeManager.shared.incrementForBackgroundJob()
            d.removeObject(forKey: Self.pendingTriggerKindKey)
            d.removeObject(forKey: Self.pendingRefreshKeyIDDefaultsKey)
            // Reschedule both real identifiers, whatever they each turn
            // out to be now — same real config/location lookup already
            // used everywhere else in this file.
            if let ctx = await DIContainer.shared.loadSchedulingContext(), let loc = ctx.1 {
                await scheduleNext(config: ctx.0, location: loc)
                await MainActor.run {
                    NotificationCenter.default.post(name: .quotaAffectingRescheduleOccurred, object: nil)
                }
            }
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Handles the maintenance task (BGProcessingTask) — quota-usage and
    /// log cleanup. Genuinely the only real kind of work this identifier
    /// ever does, so unlike handleRefresh, there's no persisted
    /// PendingTriggerKind to read back at all.
    private func handleMaintenance(_ task: BGProcessingTask) {
        AppLogger.shared.info("BGTaskCoordinator: OS invoked handleMaintenance (task \(task.identifier))")
        let work = Task { [weak self] in
            guard let self else { return }
            // Defaults true, matching the badge's own existing, correct
            // behavior — only the specific, named case below (logging
            // disabled, so log cleanup itself did nothing) sets it false.
            var shouldIncrementBadge = true
            // Quota-usage cleanup runs unconditionally — this is a real,
            // core feature with no dependency on the logging toggle at
            // all, unlike log cleanup itself.
            await DIContainer.shared.quotaManager.cleanupOldQuotaUsage()
            if AppLogger.shared.isEnabled {
                await BadgeManager.shared.postJobStartedBanner(kind: .logCleanup)
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    AppLogger.shared.cleanupOldLogs {
                        AppLogger.shared.info("BGTaskCoordinator: background log cleanup completed")
                        continuation.resume()
                    }
                }
            } else {
                // Logging is disabled — this job genuinely did nothing
                // log-related at all (only the real, unconditional quota
                // cleanup above ran), so no banner and no badge increment
                // for it, per direct instruction.
                shouldIncrementBadge = false
            }
            task.setTaskCompleted(success: true)
            if shouldIncrementBadge {
                await BadgeManager.shared.incrementForBackgroundJob()
            }
            // Reschedule both real identifiers — same, shared
            // scheduleNext() handleRefresh's own completion already uses.
            if let ctx = await DIContainer.shared.loadSchedulingContext(), let loc = ctx.1 {
                await scheduleNext(config: ctx.0, location: loc)
                await MainActor.run {
                    NotificationCenter.default.post(name: .quotaAffectingRescheduleOccurred, object: nil)
                }
            }
        }
        task.expirationHandler = { work.cancel() }
    }
}
