import Foundation

/// Where and how an Editor layer sits on the canvas: the Editor-tier intent behind Protocol V2's `transform`
/// (`translate` / `scale` / `rotate`). Plain numbers in composition units, every field optional in JSON; the
/// defaults put the layer centred, upright and at its own size, which is what a layer without a transform does.
/// `PresetCompiler` lowers it to a `V2Transform` on the layer itself - never on the group wrapper a preset adds
/// (that one carries only the preset's keyframes, CLAUDE.md "Group layers compose by real nesting"), so a preset
/// animates *around* the layer's resting place.
struct EditorTransform: Codable, Equatable {
    /// Offset from the canvas centre, composition px (x right, y down).
    var x: Double
    var y: Double
    /// Scale factors around the layer's own centre (1 = its frame size).
    var scaleX: Double
    var scaleY: Double
    /// Degrees, clockwise.
    var rotation: Double

    init(x: Double = 0, y: Double = 0, scale: Double = 1, rotation: Double = 0) {
        self.init(x: x, y: y, scaleX: scale, scaleY: scale, rotation: rotation)
    }

    init(x: Double, y: Double, scaleX: Double, scaleY: Double, rotation: Double) {
        self.x = x
        self.y = y
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
    }

    private enum CodingKeys: String, CodingKey { case x, y, scale, scaleX, scaleY, rotation }

    /// Every key is optional; `scale` is shorthand for both axes, `scaleX`/`scaleY` override it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let uniform = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        scaleX = try c.decodeIfPresent(Double.self, forKey: .scaleX) ?? uniform
        scaleY = try c.decodeIfPresent(Double.self, forKey: .scaleY) ?? uniform
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
    }

    /// Writes only what differs from the defaults, so an untouched layer's JSON is unchanged.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if x != 0 { try c.encode(x, forKey: .x) }
        if y != 0 { try c.encode(y, forKey: .y) }
        if scaleX == scaleY {
            if scaleX != 1 { try c.encode(scaleX, forKey: .scale) }
        } else {
            try c.encode(scaleX, forKey: .scaleX)
            try c.encode(scaleY, forKey: .scaleY)
        }
        if rotation != 0 { try c.encode(rotation, forKey: .rotation) }
    }

    /// The Protocol V2 form: pivot at the layer's own centre (anchor 0), no skew, no 3D.
    var v2: V2Transform {
        V2Transform(
            translate: V2Vec3(x: x, y: y, z: 0),
            scale: V2Vec3(x: scaleX, y: scaleY, z: 1),
            rotate: V2Vec3(x: 0, y: 0, z: rotation),
            skew: V2Vec2(x: 0, y: 0),
            anchor: V2Vec3(x: 0, y: 0, z: 0)
        )
    }

    /// Where a point `(dx, dy)` given in this layer's own (rotated, scaled) space ends up on the canvas - for
    /// building a child that must stay glued to a parent (a photo inside a polaroid frame).
    func canvasPoint(dx: Double, dy: Double) -> (x: Double, y: Double) {
        let radians = rotation * .pi / 180
        let sx = dx * scaleX, sy = dy * scaleY
        return (x + sx * cos(radians) - sy * sin(radians), y + sx * sin(radians) + sy * cos(radians))
    }
}
