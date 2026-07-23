import Foundation
import BackgroundTasks

/// Owns all BGTaskScheduler interaction for the app — ONE real background
/// task, `workerTaskID`. Previously this used two separate identifiers
/// (fetch/refresh and log cleanup), both submitted as BGAppRefreshTaskRequest
/// — but BGAppRefreshTaskRequest has a real, documented, APP-WIDE limit of
/// exactly ONE pending request at a time, shared ACROSS every identifier,
/// not a separate budget per identifier. Two identifiers were never two
/// independent slots; they were silently competing for the same single
/// slot, and whichever was submitted last silently won — this was the
/// actual root cause of "the fetch job never appears in pending requests"
/// investigated at length. Consolidating into one identifier makes this
/// constraint impossible to violate by construction.
///
/// scheduleNext() computes the earliest upcoming trigger across auto-fetch
/// (a global, once-daily event), every enabled API key's own auto-refresh
/// interval, and daily maintenance (always scheduled; log cleanup within
/// it is conditional on the logging toggle, quota-usage cleanup is not) —
/// genuinely a min() across all three, then submits ONE
/// BGAppRefreshTaskRequest for whichever wins. Since only
/// one request exists at a time but the app needs to know WHICH kind of
/// work to actually do when it fires, the winning trigger's kind (and key
/// ID, for refresh) is persisted to UserDefaults at submission time and
/// read back in handleWorker when the task actually fires later —
/// BGAppRefreshTaskRequest itself has no field for custom metadata, so
/// this is the simplest durable handoff across a possible app
/// suspend/resume in between.
final class BGTaskCoordinator {
    static let workerTaskID = "com.ioanmihaila.solarcast.worker"

    /// What kind of work the currently-pending worker task represents, and
    /// (for refresh) which key. Persisted as a raw string + optional UUID
    /// string pair rather than trying to encode the whole ScheduledTrigger,
    /// since UserDefaults has no native support for arbitrary enums.
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
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.workerTaskID, using: nil) { [weak self] task in
            self?.handleWorker(task as! BGAppRefreshTask)
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
    func scheduleNext(config: FetchTriggerConfiguration, location: UserLocation) async {
        guard let trigger = await schedulingEngine.nextScheduledFetch(config: config, location: location) else {
            AppLogger.shared.info("BGTaskCoordinator: scheduleNext skipped submission — no trigger returned by SchedulingEngine (see SchedulingEngine log lines above for the specific reason)")
            cancelWorker()
            return
        }
        let d = UserDefaults.standard

        // Skip resubmission entirely if the OS already has a pending
        // request whose date AND kind/key genuinely, exactly match this
        // new trigger — now safe to do, since SchedulingEngine's own
        // stable-target cache means the computed trigger no longer
        // drifts later on every re-trigger the way it used to; a
        // genuinely unchanged trigger really does mean "nothing to do."
        // A date-only check wouldn't be sufficient — a different kind
        // or key landing at the same date would still need the
        // persisted metadata updated, or the eventual background task
        // would read the wrong kind/key and do the wrong work.
        let currentlyPending = await pendingRequests().first(where: { $0.identifier == Self.workerTaskID })
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
                sameKindAndKey = currentKind == .logCleanup
            }
            if sameKindAndKey {
                AppLogger.shared.info("BGTaskCoordinator: scheduleNext skipped resubmission — already scheduled at \(pendingDate), kind/key unchanged")
                return
            }
        }

        let req = BGAppRefreshTaskRequest(identifier: Self.workerTaskID)
        req.earliestBeginDate = trigger.date

        switch trigger {
        case .fetch:
            d.set(PendingTriggerKind.fetch.rawValue, forKey: Self.pendingTriggerKindKey)
            d.removeObject(forKey: Self.pendingRefreshKeyIDDefaultsKey)
        case .refresh(_, let apiKeyID):
            d.set(PendingTriggerKind.refresh.rawValue, forKey: Self.pendingTriggerKindKey)
            d.set(apiKeyID.uuidString, forKey: Self.pendingRefreshKeyIDDefaultsKey)
        case .logCleanup:
            d.set(PendingTriggerKind.logCleanup.rawValue, forKey: Self.pendingTriggerKindKey)
            d.removeObject(forKey: Self.pendingRefreshKeyIDDefaultsKey)
        }

        do {
            try BGTaskScheduler.shared.submit(req)
            AppLogger.shared.info("BGTaskCoordinator: scheduled next worker task (\(trigger)) for \(trigger.date)")
            await logPendingRequests()
        } catch {
            AppLogger.shared.error("BGTaskCoordinator: failed to submit worker task request: \(error)")
        }
    }

    /// Cancels the currently-pending worker task, if any. Used when
    /// nextScheduledFetch produces no candidate at all — auto-fetch,
    /// auto-refresh, and logging are all disabled (or none produced a
    /// valid trigger) — since there's nothing left to wake the app for.
    func cancelWorker() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.workerTaskID)
        UserDefaults.standard.removeObject(forKey: Self.pendingTriggerKindKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingRefreshKeyIDDefaultsKey)
        AppLogger.shared.info("BGTaskCoordinator: cancelled pending worker task (\(Self.workerTaskID))")
        Task { await logPendingRequests() }
    }

    private func handleWorker(_ task: BGAppRefreshTask) {
        AppLogger.shared.info("BGTaskCoordinator: OS invoked handleWorker (task \(task.identifier))")
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
                case .logCleanup:
                    await BadgeManager.shared.postJobStartedBanner(kind: .logCleanup)
                    // Quota-usage cleanup runs unconditionally — this is
                    // a real, core feature with no dependency on the
                    // logging toggle at all, unlike log cleanup itself.
                    await DIContainer.shared.quotaManager.cleanupOldQuotaUsage()
                    if AppLogger.shared.isEnabled {
                        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                            AppLogger.shared.cleanupOldLogs {
                                AppLogger.shared.info("BGTaskCoordinator: background log cleanup completed")
                                continuation.resume()
                            }
                        }
                    }
                case .fetch, .none:
                    // .none covers both "never set" (shouldn't happen if
                    // scheduleNext always persists a kind before
                    // submitting) and any decode failure — falling back
                    // to the same behavior .fetch always had (touch every
                    // eligible site) is the safest default, since it's
                    // the one path that was never key-specific to begin
                    // with.
                    await BadgeManager.shared.postJobStartedBanner(kind: .fetch)
                    try await fetchForecastUseCase.executeAutoFetch()
                    AppLogger.shared.info("BGTaskCoordinator: background auto-fetch completed successfully")
                }
                task.setTaskCompleted(success: true)
            } catch {
                AppLogger.shared.error("BGTaskCoordinator: background worker task failed: \(error)")
                task.setTaskCompleted(success: false)
            }
            // Badge reflects "a job ran while you weren't looking," not
            // "a job succeeded" — incremented regardless of which branch
            // above actually ran or whether it threw.
            await BadgeManager.shared.incrementForBackgroundJob()
            d.removeObject(forKey: Self.pendingTriggerKindKey)
            d.removeObject(forKey: Self.pendingRefreshKeyIDDefaultsKey)
            // Reschedule for the next min(time) across all three triggers,
            // whatever that turns out to be now — same real config/location
            // lookup already used everywhere else in this file.
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
