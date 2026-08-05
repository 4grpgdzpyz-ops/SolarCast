import SwiftUI
struct APIKeyEditView: View {
    @State var viewModel: APIKeyEditViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var limitText = ""
    @State private var showKey = false
    var body: some View {
        Form {
                Section("Key Details") {
                    TextField("Name", text: $viewModel.name)
                    HStack {
                        Group {
                            if showKey {
                                TextField("API Key Value", text: $viewModel.keyValue)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("API Key Value", text: $viewModel.keyValue)
                            }
                        }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(Color.scMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    Toggle("Enabled", isOn: $viewModel.isEnabled)
                }
                Section("Daily Quota Limit") {
                    HStack {
                        TextField("10", text: $limitText).keyboardType(.numberPad)
                            .onChange(of: limitText) { _, v in viewModel.dailyQuotaLimit = Int(v) ?? 0 }
                        Text(viewModel.dailyQuotaLimit == 0 ? "Unlimited" : "calls/day")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Assigned PV Sites") {
                    if viewModel.availableSites.isEmpty {
                        Text("No sites available.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.availableSites) { site in
                        Button { viewModel.toggleSite(site.id) } label: {
                            HStack {
                                Circle().fill(site.color).frame(width: 10, height: 10)
                                Text(site.name).foregroundStyle(Color.scText)
                                Spacer()
                                if viewModel.assignedSiteIDs.contains(site.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.scAccent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(viewModel.name.isEmpty ? "New API Key" : viewModel.name)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { Task { if await viewModel.save() { dismiss() } } }
                }
            }
            .task { limitText = String(viewModel.dailyQuotaLimit); await viewModel.loadAvailableSites() }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
    }
}