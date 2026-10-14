import UIKit

/// The fonts the Text tool offers: the iOS system ones, so nothing is bundled or downloaded. Only those this iOS really has
/// (an unknown name would silently draw in the system font).
struct EditorFont: Identifiable {
    let postScript: String
    let title: String
    var id: String { postScript }

    private static let candidates: [(String, String)] = [
        ("HelveticaNeue-Bold", "Helvetica"), ("AvenirNext-Heavy", "Avenir"), ("TrebuchetMS-Bold", "Trebuchet"), ("Verdana-Bold", "Verdana"),
        ("GillSans-Bold", "Gill Sans"), ("Georgia-Bold", "Georgia"), ("Didot-Bold", "Didot"), ("Baskerville-Bold", "Baskerville"),
        ("Palatino-Bold", "Palatino"), ("Futura-CondensedExtraBold", "Futura"), ("Copperplate-Bold", "Copperplate"), ("Optima-ExtraBlack", "Optima"),
        ("MarkerFelt-Wide", "Marker Felt"), ("Chalkduster", "Chalkduster"), ("AmericanTypewriter-Bold", "Typewriter"), ("Courier-Bold", "Courier"),
        ("SnellRoundhand-Black", "Snell"), ("BradleyHandITCTT-Bold", "Bradley"), ("Noteworthy-Bold", "Noteworthy"), ("Papyrus", "Papyrus"),
        ("PartyLetPlain", "Party"), ("Zapfino", "Zapfino"),
    ]

    @MainActor static let available: [EditorFont] = candidates.filter { UIFont(name: $0.0, size: 12) != nil }.map { EditorFont(postScript: $0.0, title: $0.1) }
}
