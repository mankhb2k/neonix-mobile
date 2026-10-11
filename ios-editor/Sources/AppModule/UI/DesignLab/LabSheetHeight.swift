import SwiftUI

/// How tall the control sheet is, so heights can be compared on the device. The Curves sheet uses `.medium`.
enum LabSheetHeight: String, CaseIterable, Identifiable {
    case compact = "Compact (240 pt)"
    case standard = "Standard (300 pt)"
    case tall = "Tall (380 pt)"
    case resizable = "Resizable (260 pt / half)"

    var id: String { rawValue }

    func detents(extra: CGFloat = 0) -> Set<PresentationDetent> {
        switch self {
        case .compact: return [.height(240 + extra)]
        case .standard: return [.height(300 + extra)]
        case .tall: return [.height(380 + extra)]
        case .resizable: return [.height(260 + extra), .medium]
        }
    }

    var showsGrabber: Bool { self == .resizable }
}
