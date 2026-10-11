import Foundation

/// Minimal undo/redo: each edit snapshots the *whole* previous `V2Project`
/// rather than storing a per-command inverse operation. Simpler and
/// trivially correct — this app's documents are small, `V2Project` is a
/// plain `Codable` value type, so snapshotting costs nothing meaningful
/// yet. A generalized diffing/patch engine is explicitly out of scope
/// until document size or real-time collaboration actually requires it —
/// same reasoning as CLAUDE.md's "CRDT deferred" rule. See the
/// "Bottom nav tools" roadmap plan for where this fits.
struct EditorHistory {
    private var past: [V2Project] = []
    private var future: [V2Project] = []

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// Call right before replacing `current` with the result of a
    /// command — records `current` so `undo()` can return to it, and
    /// clears any redo history (a fresh edit invalidates whatever had
    /// been undone before it, same convention every undo stack uses).
    mutating func record(current: V2Project) {
        past.append(current)
        future.removeAll()
    }

    mutating func undo(current: V2Project) -> V2Project? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    mutating func redo(current: V2Project) -> V2Project? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }
}
