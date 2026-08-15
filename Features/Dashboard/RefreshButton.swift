import SwiftUI

struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var rotation: Double = 0
    @State private var animating = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(rotation))
        }
        .disabled(isRefreshing)
        .onAppear {
            // Closes a real, specific gap at app launch: isRefreshing can
            // be set true and then false again, both within one async
            // Task, without SwiftUI ever getting a distinct render pass to
            // observe the transition via .onChange below — since the app
            // is doing a real amount of other, concurrent setup work at
            // that exact moment. Checking the current value directly here
            // means a refresh already in progress by the time this view
            // first renders still visibly spins, rather than silently
            // completing with no animation at all.
            if isRefreshing { startSpinning() }
        }
        .onChange(of: isRefreshing) { _, spinning in
            if spinning {
                startSpinning()
            } else if animating {
                // Stop: cancel the repeating animation and snap back
                animating = false
                withAnimation(.linear(duration: 0.15)) {
                    rotation = 0
                }
            }
        }
    }

    private func startSpinning() {
        guard !animating else { return }
        animating = true
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}
