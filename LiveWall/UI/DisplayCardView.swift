import SwiftUI
import UniformTypeIdentifiers

/// One card per display: drop zone with thumbnail preview plus scaling,
/// mute/volume, file picker, and remove controls.
struct DisplayCardView: View {
    let state: DisplayState
    @ObservedObject var engine: WallpaperEngine

    @State private var isDropTargeted = false
    @State private var thumbnail: NSImage?

    private static let allowedExtensions: Set<String> = ["mov", "mp4", "m4v"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(state.name)
                    .font(.headline)
                Spacer()
                Text(state.resolutionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            dropZone

            if let url = state.videoURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            controls
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.5))
        )
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.25))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: state.videoURL == nil ? "arrow.down.doc" : "film")
                        .font(.title2)
                    Text(state.videoURL == nil ? "Drop a video here" : "Loading preview…")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first,
                  Self.allowedExtensions.contains(url.pathExtension.lowercased()) else {
                return false
            }
            engine.assignVideo(url: url, to: state.id)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .task(id: state.videoURL) {
            guard let url = state.videoURL else {
                thumbnail = nil
                return
            }
            thumbnail = await ThumbnailCache.shared.thumbnail(for: url)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Scaling", selection: Binding(
                get: { state.scaling },
                set: { engine.setScaling($0, for: state.id) }
            )) {
                ForEach(ScalingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 90)
            .disabled(state.videoURL == nil)

            Button {
                engine.setMuted(!state.isMuted, for: state.id)
            } label: {
                Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .disabled(state.videoURL == nil)
            .help(state.isMuted ? "Unmute" : "Mute")

            if state.videoURL != nil && !state.isMuted {
                Slider(value: Binding(
                    get: { Double(state.volume) },
                    set: { engine.setVolume(Float($0), for: state.id) }
                ), in: 0...1)
                .frame(width: 70)
            }

            Spacer()

            Button("Choose…") {
                chooseFile()
            }

            Button {
                engine.removeVideo(from: state.id)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(state.videoURL == nil)
            .help("Remove wallpaper")
        }
        .controlSize(.small)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.quickTimeMovie, .mpeg4Movie]
        if let m4v = UTType("com.apple.m4v-video") {
            types.append(m4v)
        }
        panel.allowedContentTypes = types
        panel.message = "Choose a video for \(state.name)"

        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            engine.assignVideo(url: url, to: state.id)
        }
    }
}
