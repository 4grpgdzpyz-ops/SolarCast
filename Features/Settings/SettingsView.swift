import SwiftUI
struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var themeStore
    @State private var showAddSite = false
    @State private var showAddKey = false
    @State private var showLocationPicker = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppearanceSettingsCard()
                    LocationSettingsCard(location: viewModel.location, onTap: { showLocationPicker = true }, onDelete: { Task { await viewModel.clearLocation() } })
                    AutoFetchSettingsCard(
                        autoFetchEnabled: $viewModel.autoFetchEnabled,
                        autoFetchTiming: $viewModel.autoFetchTiming,
                        nextAutoFetchTime: viewModel.nextAutoFetchTime)
                    AutoRefreshSettingsCard(
                        autoRefreshEnabled: $viewModel.autoRefreshEnabled,
                        computedIntervalMinutes: viewModel.computedRefreshIntervalMinutes,
                        nextAutoRefreshTime: viewModel.nextAutoRefreshTime)
                    APIKeysSettingsCard(apiKeys: viewModel.apiKeys, sites: viewModel.sites,
                                        onToggleEnabled: { id in Task { await viewModel.toggleKeyEnabled(id) } },
                                        onAddKey: { showAddKey = true },
                                        onDelete: { id in Task { await viewModel.deleteKey(id) } })
                    PVSitesSettingsCard(sites: viewModel.sites, onAddSite: { showAddSite = true }, onDelete: { id in Task { await viewModel.deleteSite(id) } })
                    SettingsBackupCard()
                    DeveloperSettingsCard()
                    AboutCard()
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
            }
            .background(Color.scBackground)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(themeStore.colorScheme)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showAddSite, onDismiss: { Task { await viewModel.load() } }) {
                NavigationStack {
                    PVSiteEditView(viewModel: DIContainer.shared.makePVSiteEditViewModel(site: nil))
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button { showAddSite = false } label: { Image(systemName: "chevron.left") }
                            }
                        }
                }.environment(themeStore)
            }
            .sheet(isPresented: $showAddKey, onDismiss: { Task { await viewModel.load() } }) {
                NavigationStack {
                    APIKeyEditView(viewModel: DIContainer.shared.makeAPIKeyEditViewModel(key: nil))
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button { showAddKey = false } label: { Image(systemName: "chevron.left") }
                            }
                        }
                }.environment(themeStore)
            }
            .sheet(isPresented: $showLocationPicker, onDismiss: { Task { await viewModel.load() } }) {
                LocationPickerView(viewModel: DIContainer.shared.makeLocationPickerViewModel())
                    .environment(themeStore)
            }
            .task { await viewModel.load() }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .settingsImported)) { _ in
            Task { await viewModel.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaAffectingRescheduleOccurred)) { _ in
            Task { await viewModel.reloadQuotaTimes() }
        }
        .id(themeStore.renderID)
    }
}

#Preview {
    SettingsView(viewModel: DIContainer.shared.makeSettingsViewModel())
        .environment(ThemeStore())
}
