import Foundation
import Observation

/// Where an editor session came from, so Export knows which template to charge for.
struct TemplateExportContext {
    let templateId: String
    /// Version the project was started from.
    let versionId: String?
    /// What the first export costs (shown when the wallet is too low); an owned template costs nothing.
    let creditCost: Int
}

/// Turns a project into a video file on the device.
protocol ProjectExporter {
    var isAvailable: Bool { get }
    func export(_ project: V2Project) async throws
}

enum ExportError: LocalizedError {
    case notAvailable
    var errorDescription: String? { "Video export isn't available in this build yet." }
}

/// Placeholder until the offline render pipeline exists.
struct UnavailableExporter: ProjectExporter {
    var isAvailable: Bool { false }
    func export(_ project: V2Project) async throws { throw ExportError.notAvailable }
}

/// Export button logic: for a template project the server is asked first (POST /v1/exports spends the credits,
/// or says the template is already owned, so it is free); only when it answers OK does the render start. Out of credits stops here
/// with a message, nothing is rendered.
@MainActor
@Observable
final class ExportGate {
    struct Alert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    typealias Charge = (TemplateExportContext) async throws -> APIExportResult

    private(set) var isWorking = false
    private(set) var completed = false
    var alert: Alert?

    private let charge: Charge
    private let exporter: ProjectExporter
    private let chargesWithoutExporter: Bool

    /// Debug builds charge even though nothing can be rendered yet, so the credit flow can be tried;
    /// release builds do not take credits for a video they cannot produce.
    nonisolated static var defaultChargesWithoutExporter: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    init(
        charge: @escaping Charge = { context in
            try await NeonixAPIClient(config: .current).createExport(templateId: context.templateId, versionId: context.versionId)
        },
        exporter: ProjectExporter = UnavailableExporter(),
        chargesWithoutExporter: Bool = ExportGate.defaultChargesWithoutExporter
    ) {
        self.charge = charge
        self.exporter = exporter
        self.chargesWithoutExporter = chargesWithoutExporter
    }

    func export(project: V2Project, context: TemplateExportContext?) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        if !exporter.isAvailable && !(context != nil && chargesWithoutExporter) {
            alert = Alert(title: "Export isn't available yet", message: "Video export is coming soon. No credits were used.")
            return
        }
        if let context {
            do {
                _ = try await charge(context)
            } catch let error as APIError where error.isInsufficientCredits {
                alert = Alert(title: "Not enough credits", message: "Unlocking this template costs \(context.creditCost) credits, once. Add credits to export this video.")
                return
            } catch {
                alert = Alert(title: "Couldn't check your credits", message: error.localizedDescription)
                return
            }
        }
        do {
            try await exporter.export(project)
            completed = true
        } catch {
            alert = Alert(title: "Export failed", message: error.localizedDescription)
        }
    }
}
