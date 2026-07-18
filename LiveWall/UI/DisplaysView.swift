import SwiftUI

struct DisplaysView: View {
    @ObservedObject var engine: WallpaperEngine
    @StateObject private var memoryMonitor = MemoryUsageMonitor()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if engine.displayStates.isEmpty {
                    Text("No displays detected.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
                ForEach(engine.displayStates) { state in
                    DisplayCardView(state: state, engine: engine)
                }

                Text("Memory Usage: \(Int(memoryMonitor.usageMB.rounded())) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 17)
        }
    }
}
