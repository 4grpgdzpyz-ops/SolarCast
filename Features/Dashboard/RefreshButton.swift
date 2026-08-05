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
        .onChange(of: isRefreshing) { _, spinning in
            if spinning {
                animating = true
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else if animating {
                // Stop: cancel the repeating animation and snap back
                animating = false
                withAnimation(.linear(duration: 0.15)) {
                    rotation = 0
                }
            }
        }
    }
}
