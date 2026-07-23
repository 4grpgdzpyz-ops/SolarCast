import SwiftUI
struct SettingsCard<Content: View>: View {
    let title: String; @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.scMuted).tracking(1)
            content
        }
        .padding(16).background(Color.scCard).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.scBorder, lineWidth: 1))
    }
}
