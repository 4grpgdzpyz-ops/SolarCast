import SwiftUI

struct AppearanceSettingsCard: View {
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        @Bindable var store = themeStore
        SettingsCard(title: "Appearance") {
            Picker("Theme", selection: Binding(
                get: { store.current },
                set: { store.current = $0 }
            )) {
                ForEach(AppTheme.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
