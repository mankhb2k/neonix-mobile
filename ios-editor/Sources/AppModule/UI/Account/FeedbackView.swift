import MessageUI
import SwiftUI

/// Send feedback by email (approach A: no backend yet). Opens the system mail sheet, or `mailto:` when Mail isn't set up.
struct FeedbackView: View {
    static let supportAddress = "support@neonix.video"

    /// `rawValue` goes into the email subject (always English, for support); `label` is what the user sees.
    enum Kind: String, CaseIterable, Identifiable {
        case bug = "Bug", idea = "Idea", other = "Other"
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .bug: return "Bug"
            case .idea: return "Idea"
            case .other: return "Other"
            }
        }
    }

    @Environment(\.openURL) private var openURL
    @State private var kind = Kind.bug
    @State private var message = ""
    @State private var includeDeviceInfo = true
    @State private var showMail = false
    @State private var showNoMailAlert = false

    private var canSend: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var subject: String { "[Neonix] \(kind.rawValue)" }

    private var body_: String {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeDeviceInfo { text += "\n\n---\n" + Self.deviceInfo }
        return text
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Message") {
                TextEditor(text: $message)
                    .frame(minHeight: 160)
                    .accessibilityIdentifier("feedback-message")
            }
            Section {
                Toggle("Include device info", isOn: $includeDeviceInfo)
            } footer: {
                if includeDeviceInfo {
                    Text(verbatim: Self.deviceInfo)
                } else {
                    Text("Nothing but your message is sent.")
                }
            }
            Section {
                Button("Send") { send() }
                    .disabled(!canSend)
                    .accessibilityIdentifier("feedback-send")
            } footer: {
                Text("Goes to \(Self.supportAddress) by email.")
            }
        }
        .navigationTitle("Send feedback")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMail) {
            MailComposer(recipient: Self.supportAddress, subject: subject, body: body_)
        }
        .alert("Mail isn't set up", isPresented: $showNoMailAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Email your feedback to \(Self.supportAddress).")
        }
    }

    private func send() {
        if MFMailComposeViewController.canSendMail() {
            showMail = true
        } else if let url = Self.mailtoURL(to: Self.supportAddress, subject: subject, body: body_) {
            openURL(url) { accepted in if !accepted { showNoMailAlert = true } }
        } else {
            showNoMailAlert = true
        }
    }

    static func mailtoURL(to address: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return components.url
    }

    static var deviceInfo: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "App \(version) (\(build)), \(hardwareModel), iOS \(UIDevice.current.systemVersion)"
    }

    /// e.g. "iPhone14,5" (the marketing name isn't available offline).
    private static var hardwareModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }
}

private struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { dismiss() }
    }
}
