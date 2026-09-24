# SolarCast ☀️

A production-grade offline-first iOS app for PV solar production forecasting, built with Swift, SwiftUI and SwiftData.

## Features

- **Multi-site forecasting** — manage multiple PV sites from Solcast, each with their own colour for chart and statistics visualisation
- **Multi API key management** — assign API keys to sites, track per-key quota usage against Solcast's own real, calendar-day reset (UTC midnight)
- **Active-site scoping** — Average/Peak/Total, the chart's Total series, and the site breakdown all reflect only sites assigned to a currently *enabled* API key, not every stored site
- **Three forecast scenarios** — Pessimistic, Normal and Optimistic (pv_estimate10 / pv_estimate / pv_estimate90)
- **Interactive chart** — Swift Charts with Catmull-Rom spline interpolation, 30-minute grid resolution, tap/scrub selection with a position-following, edge-aware tooltip, per-line toggle, fullscreen mode, dashed estimated segments
- **Statistics** — Average kW over sun window, peak kW at HH:mm, total kWh, best appliance-run interval
- **Smart scheduling** — once-daily auto-fetch (sunrise-relative or fixed time) + per-key intra-day auto-refresh with quota-aware interval computation, anchored inside vs. outside the current sun window and edge-aware around real quota changes rather than drifting later on every re-trigger
- **Sun-window-aware staleness** — outside daylight hours, a key is stale only if it's missing today's data entirely; inside daylight hours, staleness is based on elapsed time since that key's last successful pull, weighed against its own computed refresh interval
- **Rate-limit handling** — a real HTTP 429 from Solcast forces that key's local quota tracking to fully exhausted immediately, rather than let the app keep attempting (and failing) further calls it believes it still has budget for
- **App icon badge** — increments whenever a scheduled background job runs, clears automatically when the app is brought to the foreground
- **Offline-first** — SwiftData is the single source of truth; network is write-only into the local store
- **App launch / resume conditional fetch** — re-evaluates staleness on cold launch and on returning from background, fetching only keys that are genuinely stale
- **Background fetch** — a single consolidated BGTaskScheduler task (`com.ioanmihaila.solarcast.worker`) computes the earliest of auto-fetch, every enabled key's auto-refresh interval, and a daily maintenance job, and reschedules itself for the next occurrence each time it runs — deliberately one identifier, not several, since `BGAppRefreshTaskRequest` allows only one pending request per app at a time, shared across every identifier
- **Daily maintenance** — quota-usage history older than the last UTC midnight is always cleaned up; log files are additionally cleaned up (24h retention) if logging is enabled — the two are independent, so disabling logging never silently stops quota cleanup
- **Mock data mode** — generates realistic, randomized forecast data locally with zero network calls or quota consumption, for development and demos without a live Solcast key; mock and real data are tracked independently and never mixed
- **Settings & data backup** — export/import settings (API keys, PV sites, location) as an encrypted, versioned JSON file, or full forecast data as the same, additionally zlib-compressed
- **Theme support** — System / Dark / Light with instant switching
- **Location picker** — address search or tap-to-pin map with Standard / Satellite / Hybrid layer toggle

## Architecture

```
┌─────────────────────────────────────────┐
│              SwiftUI Views               │
├─────────────────────────────────────────┤
│              ViewModels (@Observable)    │
├─────────────────────────────────────────┤
│         Domain (Entities + Use Cases)   │
├──────────────────┬──────────────────────┤
│   Networking     │   Persistence        │
│   (Solcast API)  │   (SwiftData)        │
└──────────────────┴──────────────────────┘
         Core (Scheduling · Quota · Stats)
```

- **Clean Architecture** — inward-only layer dependencies (one narrow, documented exception: a single use case reaches into the app-level dependency container specifically to reschedule the background worker after a launch-time fetch, since that's where the real coordinator is assembled)
- **Offline-first** — local always loads first; network is a write-only source
- **DST-safe timestamps** — `periodStart` derived via raw `TimeInterval` arithmetic, never `Calendar`
- **Parallel ingestion** — `TaskGroup`-based concurrent per-site API fetches
- **Quota management** — real, UTC-calendar-day tracking (not a rolling window) per API key, matching Solcast's own actual server-side reset boundary
- **Mock/real data isolation** — every stored forecast point and quota event carries an `isMock` flag; reads are scoped to whichever mode is currently active, so switching modes never mixes or silently overwrites the other mode's data

## Requirements

- iOS 17+
- Xcode 15+
- [Solcast API key](https://solcast.com) (free tier available)

## Dependencies

| Package | Source | Purpose |
|---------|--------|---------|
| [Solar](https://github.com/ceeK/Solar) | GitHub SPM | Sunrise / sunset calculation |

## Getting Started

1. Clone the repository
2. Open `SolarCast.xcodeproj` in Xcode — the Solar SPM package resolves automatically
3. Build and run on a device or simulator (iOS 17+)
4. Open **Settings** → set your **Location** → add a **PV Site** with your Solcast site ID → add an **API Key** and assign it to the site
5. Tap **↻ Refresh** on the dashboard to fetch your first forecast

Don't have a Solcast API key yet? Enable **Mock Data** under Settings → Developer to generate realistic sample forecasts locally, with no network calls or API quota consumed — useful for trying the app or developing against it before signing up for a real key.

## Project Structure

```
SolarCast/
├── App/                        # Entry point, DI container, AppDelegate, theme store
├── Domain/
│   ├── Entities/               # Pure Swift structs (ForecastPoint, PVSite, APIKey …)
│   ├── RepositoryProtocols/    # Abstractions over persistence
│   └── UseCases/               # Orchestration logic (fetch, stats, chart, quota, active-site scoping)
├── Core/
│   ├── Backup/                 # Versioned settings/data export & import (BackupService), zlib compression
│   ├── Networking/             # Solcast API client, mock API client, parallel fetch coordinator, DTOs
│   ├── Mappers/                # DTO <-> domain and domain <-> SwiftData-entity mapping
│   ├── Persistence/            # SwiftData schema + repository implementations
│   ├── Scheduling/             # BGTaskScheduler, SchedulingEngine, StalenessEvaluator
│   ├── Quota/                  # QuotaManager, UTC-day-based usage tracker, reservation/interval policy
│   ├── Stats/                  # StatsEngine, ChartDataAssembler, BestIntervalCalculator
│   ├── Solar/                  # ceeK Solar adapter (sunrise/sunset)
│   └── Utilities/              # Logging, badge manager, shared UTC calendar, ISO8601 period parser, error presentation, colour extensions
├── Features/
│   ├── Dashboard/              # Main forecast screen, summary/breakdown/usage cards
│   ├── Charts/                 # ForecastChartView (Swift Charts, Catmull-Rom interpolation, edge-aware tooltip)
│   ├── Settings/               # App settings, API key & site management, backup export/import, developer tools
│   ├── APIKeys/                # API key CRUD
│   ├── PVSites/                # PV site CRUD with full colour picker
│   └── LocationPicker/         # MapKit address search + tap-to-pin
└── SolarCastTests/
    ├── Unit/                   # Pure logic tests (StatsEngine, QuotaManager, StalenessEvaluator …)
    ├── Integration/            # Use-case pipeline + SwiftData roundtrip tests, backup roundtrip tests
    └── Mocks/                  # Protocol-backed test doubles
```

## Project Size

~7,900 lines of Swift across 106 app source files, plus ~1,500 lines across 23 test files, as of this writing. Counts will drift as the project evolves — treat this as a rough snapshot, not a maintained badge.

## License

MIT — see [LICENSE](LICENSE)
