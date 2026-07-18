import AVFoundation

/// The three ways a video can be scaled to fill its display.
enum ScalingMode: String, Codable, CaseIterable, Identifiable {
    case fill
    case fit
    case stretch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }
}
