import SwiftUI
import UniformTypeIdentifiers

struct SettingsBackupCard: View {
    @State private var showSettingsImporter = false
    @State private var showDataImporter = false
    @State private var importMessage: String?
    @State private var showImportResult = false

    // Bound to fileExporter's document: parameter. Set inside each button's
    // action closure, immediately before isPresented flips true — the
    // document is built fresh from BackupService at that exact moment, not
    // read from something computed at an earlier render.
    @State private var settingsExportDoc: BackupFileDocument?
    @State private var dataExportDoc: BackupFileDocument?
    @State private var showSettingsExporter = false
    @State private var showDataExporter = false

    var body: some View {
        SettingsCard(title: "Backup") {
            VStack(spacing: 10) {
                // Export Settings — one tap: build the backup fresh from
                // BackupService, then immediately present the system save
                // dialog via .fileExporter. No intermediate "now tap this
                // link" step, no custom share-sheet wrapper.
                Button {
                    Task {
                        let backup = await DIContainer.shared.backupService.createSettingsBackup()
                        settingsExportDoc = BackupFileDocument(backup: backup)
                        showSettingsExporter = true
                    }
                } label: {
                    backupButton(icon: "square.and.arrow.up", label: "Export Settings")
                }
                .fileExporter(isPresented: $showSettingsExporter, document: settingsExportDoc,
                              contentType: .json, defaultFilename: "solarcast-settings") { result in
                    handleExportResult(result)
                }

                // Import Settings
                Button { showSettingsImporter = true } label: {
                    backupButton(icon: "square.and.arrow.down", label: "Import Settings")
                }
                .fileImporter(isPresented: $showSettingsImporter, allowedContentTypes: [.json]) { result in
                    handleImport(result, expecting: .settings)
                }

                Text("Exports/imports settings and preferences.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.scMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().padding(.vertical, 2)

                // Export Data — same one-tap pattern.
                Button {
                    Task {
                        let backup = await DIContainer.shared.backupService.createDataBackup()
                        dataExportDoc = BackupFileDocument(backup: backup)
                        showDataExporter = true
                    }
                } label: {
                    backupButton(icon: "externaldrive.badge.arrow.up", label: "Export Data")
                }
                .fileExporter(isPresented: $showDataExporter, document: dataExportDoc,
                              contentType: BackupFileDocument.zlibType, defaultFilename: "solarcast-data") { result in
                    handleExportResult(result)
                }

                // Import Data
                Button { showDataImporter = true } label: {
                    backupButton(icon: "externaldrive.badge.arrow.down", label: "Import Data")
                }
                .fileImporter(isPresented: $showDataImporter, allowedContentTypes: [.json, BackupFileDocument.zlibType]) { result in
                    handleImport(result, expecting: .data)
                }

                Text("Exports/imports forecast history for device transfer.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.scMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("Backup", isPresented: $showImportResult) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func backupButton(icon: String, label: String) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
            Text(label).font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .foregroundStyle(Color.scAccent)
        .background(Color.scAccent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.scAccent, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            AppLogger.shared.error("SettingsBackupCard: export failed: \(error)")
        }
    }

    private func handleImport(_ result: Result<URL, Error>, expecting kind: BackupKind) {
        switch result {
        case .success(let url):
            let got = url.startAccessingSecurityScopedResource()
            defer { if got { url.stopAccessingSecurityScopedResource() } }
            do {
                let rawData = try Data(contentsOf: url)
                let isCompressed = url.pathExtension.lowercased() == "zlib"
                let backup = try BackupFileDocument.decodeBackup(from: rawData, isCompressed: isCompressed)
                Task {
                    do {
                        try await DIContainer.shared.backupService.importBackup(backup, expecting: kind)
                        await MainActor.run {
                            importMessage = "Imported successfully."
                            // Refresh theme
                            if let theme = UserDefaults.standard.string(forKey: "solarcast.appTheme") {
                                let t = AppTheme(rawValue: theme) ?? .system
                                DIContainer.shared.themeStore?.current = t
                            }
                        }
                        // Reload mock client state
                        await DIContainer.shared.reloadAPIClient()
                        // Notify SettingsView to reload
                        await MainActor.run {
                            NotificationCenter.default.post(name: .settingsImported, object: nil)
                            showImportResult = true
                        }
                    } catch {
                        AppLogger.shared.error("SettingsBackupCard: import failed: \(error)")
                        await MainActor.run {
                            importMessage = "Import failed: \(error.localizedDescription)"
                            showImportResult = true
                        }
                    }
                }
            } catch {
                AppLogger.shared.error("SettingsBackupCard: failed to decode backup file: \(error)")
                importMessage = "This file isn't a valid SolarCast backup: \(error.localizedDescription)"
                showImportResult = true
            }
        case .failure(let error):
            AppLogger.shared.error("SettingsBackupCard: file picker failed: \(error)")
            importMessage = "Could not open file: \(error.localizedDescription)"
            showImportResult = true
        }
    }
}
