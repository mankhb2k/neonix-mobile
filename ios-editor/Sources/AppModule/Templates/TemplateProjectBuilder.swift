import Foundation

/// Turns an unpacked template into the `V2Project` the editor opens.
enum TemplateProjectBuilder {
    /// Compiles the template's document through the normal pipeline, then gives text layers their own timeline
    /// lanes: `EditorDocument` has no lane concept (`compile` leaves every layer on lane 0), and a lane must
    /// stay homogeneous by type (CLAUDE.md, "Timeline lanes"). Text layers that do not overlap in time share a lane.
    static func project(from package: TemplatePackage) -> V2Project {
        project(document: package.document, trims: [:])
    }

    /// `trims`: layer id -> `trimStart` (ms) of the crop window the user chose for a video layer.
    static func project(document: EditorDocument, trims: [String: Double]) -> V2Project {
        let project = compile(document)
        let textIds = Set(document.layers.filter { $0.kind == "text" }.map(\.id))

        var laneEnds: [Double] = []   // laneEnds[0] is lane 1
        var laneOfText: [String: Int] = [:]
        for layer in document.layers.filter({ textIds.contains($0.id) }).sorted(by: { $0.timing.start < $1.timing.start }) {
            let lane = laneEnds.firstIndex { $0 <= layer.timing.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(0) }
            laneEnds[lane] = layer.timing.start + layer.timing.duration
            laneOfText[layer.id] = lane + 1
        }

        let layers: [V2Layer] = project.layers.map { layer in
            // A preset wraps the layer in an invisible "<id>-fx" group; the wrapper rides the same lane.
            let owner = textIds.contains(layer.id) ? layer.id : (layer.id.hasSuffix("-fx") ? String(layer.id.dropLast(3)) : nil)
            var moved = layer
            if let owner, let lane = laneOfText[owner] { moved.order = lane }
            if let trim = trims[layer.id], case .video(var payload) = layer.payload {
                payload.trimStart = trim
                moved.payload = .video(payload)
            }
            return moved
        }
        return V2Project(
            id: project.id, composition: project.composition, assets: project.assets,
            filters: project.filters, layers: layers, audio: project.audio
        )
    }
}
