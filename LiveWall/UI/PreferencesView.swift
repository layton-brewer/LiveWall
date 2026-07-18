import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject var engine: WallpaperEngine

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var saverInstalled = SaverInstaller.isInstalled
    @State private var saverError: String?
    @State private var aerialInstalled = AerialInstaller.isInstalled
    @State private var aerialError: String?
    @State private var aerialBusy = false
    @ObservedObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        ScrollView {
            content
                .padding(12)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            saverInstalled = SaverInstaller.isInstalled
            aerialInstalled = AerialInstaller.isInstalled
        }
        .onChange(of: aerialInstalled, handleAerialToggle)
        .onChange(of: saverInstalled, handleSaverToggle)
        .onChange(of: launchAtLogin, handleLaunchAtLoginToggle)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("General") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Toggle("Pause when on battery", isOn: $engine.pauseOnBattery)
                    Toggle("Pause in Low Power Mode", isOn: $engine.pauseOnLowPower)
                    updateRow
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Screen Saver") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Use video as screen saver", isOn: $saverInstalled)
                    if let saverError {
                        Text(saverError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if AerialInstaller.isSupported {
                GroupBox("Lock Screen & Wallpaper Tile") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Add video to Wallpaper & Lock Screen", isOn: $aerialInstalled)
                            .disabled(aerialBusy)
                        if let aerialError {
                            Text(aerialError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit LiveWall", systemImage: "power")
                }
            }
        }
    }

    private var updateRow: some View {
        HStack(spacing: 8) {
            switch updateChecker.status {
            case .idle:
                Button("Check for Updates…") { updateChecker.checkNow() }
                    .controlSize(.small)
                Spacer()
            case .checking:
                Text("Checking for updates…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            case .upToDate:
                Text("You're on the latest version (\(updateChecker.currentVersion))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            case .updateAvailable(let version):
                Text("Version \(version) is available")
                    .font(.caption)
                Spacer()
                Button("Download") {
                    NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
                }
                .controlSize(.small)
            case .failed:
                Text("Couldn't check for updates")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") { updateChecker.checkNow() }
                    .controlSize(.small)
            }
        }
    }

    private func handleAerialToggle(_ oldValue: Bool, _ newValue: Bool) {
        guard newValue != AerialInstaller.isInstalled else { return }
        if newValue {
            guard let url = engine.saverVideoURL else {
                aerialInstalled = false
                aerialError = "Assign a video to a display first."
                return
            }
            aerialBusy = true
            Task {
                do {
                    try await AerialInstaller.install(
                        videoURL: url,
                        displayName: url.deletingPathExtension().lastPathComponent
                    )
                    aerialError = nil
                } catch {
                    aerialInstalled = false
                    aerialError = "Couldn't register the video: \(error.localizedDescription)"
                }
                aerialBusy = false
            }
        } else {
            do {
                try AerialInstaller.uninstall()
                aerialError = nil
            } catch {
                aerialInstalled = AerialInstaller.isInstalled
                aerialError = "Couldn't remove: \(error.localizedDescription)"
            }
        }
    }

    private func handleSaverToggle(_ oldValue: Bool, _ newValue: Bool) {
        guard newValue != SaverInstaller.isInstalled else { return }
        do {
            if newValue {
                try SaverInstaller.install()
                if let url = engine.saverVideoURL {
                    SaverInstaller.syncVideoInBackground(url)
                }
            } else {
                try SaverInstaller.uninstall()
            }
            saverError = nil
        } catch {
            saverInstalled = SaverInstaller.isInstalled
            saverError = "Couldn't update screen saver: \(error.localizedDescription)"
        }
    }

    private func handleLaunchAtLoginToggle(_ oldValue: Bool, _ newValue: Bool) {
        let currentlyEnabled = SMAppService.mainApp.status == .enabled
        guard newValue != currentlyEnabled else { return }
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLogin = currentlyEnabled
            launchAtLoginError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
}
