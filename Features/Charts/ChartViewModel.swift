import Foundation
import Observation

@Observable final class ChartViewModel {
    var activeIndex: Int?

    /// Non-observed so restarting the timer doesn't invalidate the view.
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /// Select a point and (re)start the 3s auto-dismiss countdown.
    func handleTap(at index: Int) {
        activeIndex = index
        scheduleDismiss()
    }

    func clearSelection() {
        dismissTask?.cancel()
        dismissTask = nil
        activeIndex = nil
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.activeIndex = nil
            self?.dismissTask = nil
        }
    }
}
