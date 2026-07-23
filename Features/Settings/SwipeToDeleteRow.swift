import SwiftUI

struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var revealed = false

    private let deleteWidth: CGFloat = 76

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button sits behind the row
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    offset = 0
                    revealed = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onDelete()
                }
            }) {
                ZStack {
                    Color.red
                    VStack(spacing: 3) {
                        Image(systemName: "trash")
                            .foregroundStyle(.white)
                            .font(.system(size: 15, weight: .semibold))
                        Text("Delete")
                            .foregroundStyle(.white)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(width: deleteWidth)
            }

            // Row slides left to reveal delete
            content()
                .background(Color.scCard)
                .offset(x: offset)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            // Only respond to primarily horizontal drags
                            let h = value.translation.width
                            let v = value.translation.height
                            guard abs(h) > abs(v) else { return }
                            if h < 0 {
                                offset = max(h, -deleteWidth)
                            } else if revealed {
                                offset = min(0, -deleteWidth + h)
                            }
                        }
                        .onEnded { value in
                            let h = value.translation.width
                            let v = value.translation.height
                            guard abs(h) > abs(v) else { return }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                if h < -(deleteWidth / 2) {
                                    offset = -deleteWidth
                                    revealed = true
                                } else {
                                    offset = 0
                                    revealed = false
                                }
                            }
                        }
                )
        }
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                if revealed {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        offset = 0
                        revealed = false
                    }
                }
            }
        )
    }
}
