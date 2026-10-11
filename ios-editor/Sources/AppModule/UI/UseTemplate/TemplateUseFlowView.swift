import SwiftUI

/// "Use template": download + unpack the package (free), let the user fill the slots, then show the result screen
/// (preview, replace/crop, music, texts, Export). The template's credit price is spent by the first Export, not here.
struct TemplateUseFlowView: View {
    let template: APITemplate

    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case preparing
        case failed(String)
        case picking(TemplatePackage)
        case building
        case editing(TemplateEditModel)
    }

    @State private var step: Step = .preparing
    @State private var versionId: String?
    /// Kept for the whole flow so going back from the result screen finds the picks where they were left.
    @State private var pickerModel: SlotPickerModel?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            switch step {
            case .preparing:
                busy("Preparing template…")
            case .building:
                busy("Building your video…")
            case .failed(let message):
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
                    Text(message).multilineTextAlignment(.center)
                    HStack {
                        Button("Close") { dismiss() }.buttonStyle(.bordered)
                        Button("Try again") { Task { await prepare() } }.buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            case .picking(let package):
                if let pickerModel {
                    SlotPickerView(model: pickerModel, templateTitle: template.title, onClose: { dismiss() }) { picks, slots in
                        Task { await build(package: package, picks: picks, slots: slots) }
                    }
                }
            case .editing(let model):
                TemplateEditView(template: template, versionId: versionId, model: model) {
                    // Back (or finished): to the picker with the same picks, or out of the flow.
                    step = .picking(model.package)
                }
            }
        }
        .task { await prepare() }
    }

    private func busy(_ text: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(text).foregroundColor(.secondary)
        }
    }

    private func prepare() async {
        step = .preparing
        do {
            let client = NeonixAPIClient(config: .current)
            let info = try await client.packageInfo(templateId: template.id)
            let zip = try await client.downloadPackage(info)
            let package = try TemplateInstaller.install(zip: zip, templateId: template.id, version: info.version)
            versionId = info.versionId
            pickerModel = SlotPickerModel(slots: package.manifest.slots)
            step = .picking(package)
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func build(package: TemplatePackage, picks: [PickedMedia?], slots: [TemplateManifest.Slot]) async {
        step = .building
        do {
            step = .editing(try await TemplateEditModel.make(package: package, picks: picks, slots: slots))
        } catch {
            step = .failed(error.localizedDescription)
        }
    }
}
