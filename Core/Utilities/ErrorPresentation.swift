import Foundation

/// Shared, human-readable message formatting for errors surfaced to the
/// user or written to logs — used by both DashboardViewModel.refresh()
/// (manual refresh) and the staleness-triggered fetch path (AppDelegate,
/// DashboardView's scene-phase resume handler), so both produce identical
/// messages from one source instead of duplicated switch logic that could
/// silently drift apart.
///
/// Previously this lived as a static function on DashboardViewModel,
/// which meant AppDelegate (an app-lifecycle file, not a Dashboard
/// feature) had to reference a Dashboard-layer type to log a real error
/// message — harmless in practice (the function is stateless and has no
/// dependency on DashboardViewModel's instance behavior), but an
/// unnecessary cross-layer reference. Living here in Core/Utilities,
/// alongside other cross-cutting helpers like AppLogger and
/// DateUTCHelpers, is a more natural home for something neither layer
/// specifically owns.
extension Error {
    var humanReadableMessage: String {
        switch self {
        case let e as FetchError:
            return e.localizedDescription
        case let e as NetworkError:
            switch e {
            case .unauthorized:        return "API key rejected. Check your key in Settings."
            case .rateLimited:         return "Solcast rate limit reached. Try again shortly."
            case .quotaExceeded:       return "API quota exceeded for this key."
            case .noConnectivity:      return "No internet connection."
            case .serverError(let c):  return "Solcast server error (\(c)). Try again later."
            default:                   return "Fetch failed: \(e.localizedDescription)"
            }
        default:
            return "Unexpected error: \(self.localizedDescription)"
        }
    }
}
