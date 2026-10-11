import Foundation

/// Everything the template result screen can change, applied to the creator's document in one pure step:
/// the user's media, their texts, and whether the template's music plays.
enum TemplateBuild {
    static func project(package: TemplatePackage, fills: [SlotFill], texts: [String: String], musicOn: Bool) throws -> V2Project {
        let filled = try TemplateFiller.fill(package, with: fills, texts: texts)
        var project = TemplateProjectBuilder.project(document: filled.document, trims: filled.trims)
        if !musicOn {
            project.audio = V2AudioDomain(sampleRate: project.audio.sampleRate, tracks: project.audio.tracks.map { track in
                var muted = track
                muted.muted = true
                return muted
            })
        }
        return project
    }
}
