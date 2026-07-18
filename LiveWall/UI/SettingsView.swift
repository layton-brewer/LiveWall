import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: WallpaperEngine

    private enum Tab: String, CaseIterable, Identifiable {
        case displays = "Displays"
        case preferences = "Preferences"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .displays

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 17)
            .padding(.bottom, 2)

            switch tab {
            case .displays:
                DisplaysView(engine: engine)
            case .preferences:
                PreferencesView(engine: engine)
            }
        }
        .frame(width: 380, height: 376)
        .ignoresSafeArea()
    }
}
