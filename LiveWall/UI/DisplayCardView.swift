import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// One card per display: drop zone with thumbnail preview plus scaling,
/// mute/volume, file picker, trim, and remove controls.
struct DisplayCardView: View {
    let state: DisplayState
    @ObservedObject var engine: WallpaperEngine

    @State private var isDropTargeted = false
    @State private var thumbnail: NSImage?
    @State private var isTrimExpanded = false
    @State private var videoDuration: Double?
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0

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

            if isTrimExpanded {
                trimEditor
            }
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
            // A different video means the old thumbnail, duration, and trim
            // handles are all stale.
            isTrimExpanded = false
            videoDuration = nil
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
                .frame(width: 60)
            }

            Spacer()

            Button("Choose…") {
                chooseFile()
            }

            Button {
                toggleTrimEditor()
            } label: {
                Image(systemName: "scissors")
            }
            .disabled(state.videoURL == nil)
            .help("Trim the loop")

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

    private var trimEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let videoDuration, videoDuration > 0 {
                HStack(spacing: 8) {
                    Text("Start")
                        .font(.caption)
                        .frame(width: 32, alignment: .leading)
                    Slider(value: $trimStart, in: 0...videoDuration) { editing in
                        if !editing { commitTrim() }
                    }
                    Text(timeString(trimStart))
                        .font(.caption.monospacedDigit())
                        .frame(width: 48, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Text("End")
                        .font(.caption)
                        .frame(width: 32, alignment: .leading)
                    Slider(value: $trimEnd, in: 0...videoDuration) { editing in
                        if !editing { commitTrim() }
                    }
                    Text(timeString(trimEnd))
                        .font(.caption.monospacedDigit())
                        .frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Text("Loops \(timeString(trimStart)) – \(timeString(trimEnd))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        trimStart = 0
                        trimEnd = videoDuration
                        engine.setTrim(start: nil, end: nil, for: state.id)
                    }
                    .controlSize(.small)
                }
            } else {
                Text("Reading video length…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: state.videoURL) {
            await loadDuration()
        }
    }

    private func toggleTrimEditor() {
        isTrimExpanded.toggle()
        if isTrimExpanded, videoDuration == nil {
            Task { await loadDuration() }
        }
    }

    private func loadDuration() async {
        guard let url = state.videoURL else { return }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds,
              duration.isFinite, duration > 0 else { return }
        videoDuration = duration
        trimStart = state.trimStart ?? 0
        trimEnd = state.trimEnd ?? duration
    }

    private func commitTrim() {
        guard let videoDuration else { return }
        // Keep at least half a second between the handles, since a shorter
        // loop than that isn't really a loop.
        if trimEnd - trimStart < 0.5 {
            trimStart = max(0, min(trimStart, trimEnd - 0.5))
            trimEnd = min(videoDuration, max(trimEnd, trimStart + 0.5))
        }
        // Handles at the very ends mean "whole file" — store that as no
        // trim at all.
        if trimStart <= 0.01 && trimEnd >= videoDuration - 0.01 {
            engine.setTrim(start: nil, end: nil, for: state.id)
        } else {
            engine.setTrim(start: trimStart, end: trimEnd, for: state.id)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
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
