import SwiftUI
import SwiftData

struct DashboardView: View {
    @State var viewModel: DashboardViewModel
    @State private var showSettings = false
    @State private var showDatePicker = false
    @State private var showStaleDataNotice = false
    @State private var staleDataFetchErrorMessage: String?
    @State private var wasBackgrounded = false
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if viewModel.isUnconfigured {
                        // ── No configuration yet ──────────────────────────
                        unconfiguredPrompt
                    } else if viewModel.hasNoData {
                        // ── Configured but no data for this date ──────────
                        noDataView
                    } else {
                        // ── Normal data view ──────────────────────────────
                        // Merged date-navigation + scenario-picker card —
                        // hidden entirely in the two branches above, per
                        // direct instruction ("when no data, hide this card
                        // completely too"). Previously the date navigator
                        // rendered unconditionally above this whole if/else;
                        // now both pieces live in one card, together, only
                        // in the branch where there's real data to navigate
                        // and a scenario to pick.
                        //
                        // .id() forces this view (and its underlying
                        // UISegmentedControl) to be destroyed and recreated
                        // whenever the theme changes. Without it, this
                        // picker is created once and persists for the whole
                        // session — its segmented control never gets a
                        // fresh instance, so it never picks up the
                        // appearance-proxy color ThemeStore sets on theme
                        // switch. (AutoFetchSettingsCard's picker doesn't
                        // need this because it's already behind a
                        // conditional that naturally recreates it — this
                        // card is now in exactly that same position.)
                        DateNavigatorView(
                            date: viewModel.selectedDate,
                            isToday: viewModel.isToday,
                            hasPreviousData: viewModel.hasPreviousData,
                            hasNextData: viewModel.hasNextData,
                            onPrevious: {
                                Task { await viewModel.changeDate(
                                    Calendar.current.date(byAdding: .day, value: -1, to: viewModel.selectedDate)!) }
                            },
                            onNext: {
                                Task { await viewModel.changeDate(
                                    Calendar.current.date(byAdding: .day, value: 1, to: viewModel.selectedDate)!) }
                            },
                            onTapTitle: { showDatePicker = true },
                            selectedScenario: viewModel.selectedScenario,
                            onSelectScenario: { scenario in
                                Task { await viewModel.changeScenario(scenario) }
                            }
                        )
                        .id(themeStore.renderID)
                        .padding(.horizontal, 14)

                        if let stats = viewModel.statsResult {
                            ForecastSummaryCard(stats: stats).padding(.horizontal, 14)
                            if let best = stats.bestInterval {
                                BestIntervalCard(interval: best).padding(.horizontal, 14)
                            }
                        }

                        ForecastChartCard(
                            series: viewModel.chartSeries,
                            hiddenIDs: $viewModel.hiddenSeriesIDs,
                            sunWindow: viewModel.statsResult?.sunWindow,
                            onToggleSeries: viewModel.toggleSeriesVisibility
                        ).padding(.horizontal, 14)

                        SiteBreakdownCard(sites: viewModel.activeSites, chartSeries: viewModel.chartSeries)
                            .padding(.horizontal, 14)

                        if let quota = viewModel.quotaStats {
                            APIUsageCard(quota: quota).padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
            .background(Color.scBackground)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    RefreshButton(isRefreshing: viewModel.isRefreshing) {
                        Task { await viewModel.refresh() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max.fill")
                            .font(.title3)
                            .foregroundStyle(Color.scAmber)
                        Text("SolarCast").font(.system(size: 22, weight: .bold))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 20))
                    }
                }
            }
            .applyToolbarTitleDisplayModeInlineIfAvailable()
            .sheet(isPresented: $showSettings, onDismiss: { Task { await viewModel.loadAll() } }) {
                SettingsView(viewModel: DIContainer.shared.makeSettingsViewModel())
                    .environment(themeStore)
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(
                    selectedDate: viewModel.selectedDate,
                    datesWithData: viewModel.datesWithData
                ) { picked in
                    showDatePicker = false
                    Task { await viewModel.changeDate(picked) }
                }
                .presentationDetents([.medium])
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // ScenePhase never delivers a single .background -> .active
                // callback — the real resume path is two separate calls:
                // (.background, .inactive) then (.inactive, .active). A
                // guard comparing oldPhase/newPhase directly for
                // .background/.active never matches either one. Track
                // whether the scene was backgrounded with a flag instead,
                // so a brief .active -> .inactive -> .active interruption
                // (Control Center, a call banner) — which never visits
                // .background — still doesn't trigger this.
                if newPhase == .background {
                    wasBackgrounded = true
                    return
                }
                guard newPhase == .active, wasBackgrounded else { return }
                wasBackgrounded = false
                Task {
                    await viewModel.goToToday()
                    // Still guards against overlapping with an
                    // already-in-flight manual refresh, checked up front —
                    // but isRefreshing itself is no longer set here. It's
                    // only set inside onWillFetch, which fires exactly when
                    // staleness has been confirmed and a real fetch is
                    // about to start — never while the staleness check
                    // itself is merely evaluating. Previously the arrow
                    // spun for the whole check-then-maybe-fetch sequence,
                    // even on the common path where nothing turned out to
                    // be stale.
                    guard !viewModel.isRefreshing else { return }
                    let result = await DIContainer.shared.performAppLaunchFetchIfNeeded(onWillFetch: {
                        await MainActor.run { viewModel.isRefreshing = true }
                    })
                    viewModel.isRefreshing = false
                    switch result {
                    case .fetchedSuccessfully:
                        // The fetch just wrote new data to the database, but
                        // nothing re-reads it — goToToday()'s own loadAll()
                        // already ran BEFORE this fetch, against the old
                        // data. Without this second reload, the popup below
                        // claims a refresh happened while the dashboard
                        // keeps showing the pre-fetch numbers.
                        await viewModel.loadAll()
                        showStaleDataNotice = true
                    case .fetchFailed(let error):
                        // Previously indistinguishable from .notStale at
                        // this call site — both silently did nothing.
                        // Worse, the underlying bug meant a genuine failure
                        // was reported as success here, showing "Data
                        // Refreshed" even though nothing was. Now a real
                        // failure shows its own, honest alert instead — and
                        // uses the same human-readable messages manual
                        // refresh already produces, not NetworkError's raw
                        // .localizedDescription (which has no LocalizedError
                        // conformance and falls back to Foundation's
                        // generic "SolarCast.NetworkError error 1"
                        // placeholder instead of anything useful).
                        staleDataFetchErrorMessage = error.humanReadableMessage
                        // The fetch itself failed, but the actual quota
                        // mutation (recordUsage, and for a real 429,
                        // QuotaManager.forceQuotaExhausted) already
                        // happened inside execute() before this branch was
                        // ever reached — reload quota here too, same
                        // reasoning as DashboardViewModel.refresh()'s own
                        // catch block, or a fully-failed staleness fetch
                        // (e.g. every stale site hitting a real 429) would
                        // never update the card at all.
                        await viewModel.loadQuota()
                    case .quotaExhausted:
                        // Something WAS stale, but the affected key's
                        // quota is already used up for the day — no
                        // alert shown here at all, per direct instruction:
                        // showing a failure message every single time the
                        // app comes to the foreground for a condition
                        // that's expected and will resolve itself at the
                        // next UTC reset would be genuinely unhelpful
                        // noise, not a real, actionable failure. Quota is
                        // still reloaded, though — nothing failed here,
                        // but a synthetic exhaustion event may have been
                        // recorded upstream if this was triggered by a
                        // real 429, and the card should reflect that.
                        await viewModel.loadQuota()
                    case .notStale:
                        break
                    }
                }
            }
            .alert("Data Refreshed", isPresented: $showStaleDataNotice) {
                Button("OK") {}
            } message: {
                Text("Your forecast data was out of date and has been refreshed.")
            }
            .alert("Refresh Failed", isPresented: Binding(
                get: { staleDataFetchErrorMessage != nil },
                set: { if !$0 { staleDataFetchErrorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text("Your forecast data was out of date, but refreshing it failed: \(staleDataFetchErrorMessage ?? "Unknown error.") It will be retried automatically.")
            }
            .task { await viewModel.loadAll() }
            .onReceive(NotificationCenter.default.publisher(for: .forecastDataRefreshed)) { _ in
                Task { await viewModel.loadAll() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mockModeChanged)) { _ in
                Task { await viewModel.loadAll() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsImported)) { _ in
                // A backup import can also change the mock/real mode (it
                // restores useMockData), and calls reloadAPIClient() the
                // same as the direct toggle — needs the same full reload.
                Task { await viewModel.loadAll() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .quotaAffectingRescheduleOccurred)) { _ in
                // Specifically covers the staleness-check-triggered
                // fetch (FetchForecastUseCase.executeAppLaunchIfStale,
                // called from AppDelegate/DIContainer at launch, with no
                // direct reference to this view model at all) — that
                // function's own quota mutation already happened by the
                // time this posts, but it has no other way to reach
                // Dashboard's display. Manual refresh doesn't need this
                // (DashboardViewModel.refresh() already calls loadQuota()
                // directly, synchronously, within the same function) —
                // this notification is the ONLY path for the stale-check
                // case specifically.
                Task { await viewModel.loadQuota() }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }

    private var unconfiguredPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "sun.max.fill").font(.system(size: 64)).foregroundStyle(Color.scAmber)
            Text("Welcome to SolarCast").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.scText)
            Text("Add your location, PV sites and API key to start forecasting.")
                .font(.system(size: 15)).foregroundStyle(Color.scMuted).multilineTextAlignment(.center)
            Button {
                showSettings = true
            } label: {
                Text("Open Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.scAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
        }
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }

    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud.sun").font(.system(size: 48)).foregroundStyle(Color.scMuted)
            Text("No forecast data").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.scText)
            Text("Tap refresh to fetch the latest forecast from Solcast.")
                .font(.system(size: 14)).foregroundStyle(Color.scMuted).multilineTextAlignment(.center)
        }
        .padding(.top, 60).padding(.horizontal, 24)
    }
}

#Preview {
    DashboardView(viewModel: DIContainer.shared.makeDashboardViewModel())
        .modelContainer(try! ModelContainerFactory.makeInMemoryContainer())
        .environment(ThemeStore())
}

private extension View {
    /// .toolbarTitleDisplayMode(_:) is iOS 18.0+ only — this project's
    /// deployment target is iOS 17.0, so it can't be applied unconditionally
    /// without failing to compile/run on iOS 17. On iOS 17 this is a no-op;
    /// on iOS 18+ it applies .inline, as requested.
    @ViewBuilder func applyToolbarTitleDisplayModeInlineIfAvailable() -> some View {
        if #available(iOS 18.0, *) {
            self.toolbarTitleDisplayMode(.inline)
        } else {
            self
        }
    }
}
