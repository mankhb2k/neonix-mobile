import Foundation

/// Minimal undo/redo: each edit snapshots the authoring V2 project together
/// with editor-only transition intents rather than storing a per-command
/// inverse operation. This keeps transition authoring out of Protocol V2
/// while undo/redo still restores a complete editor state. A generalized diffing/patch engine is explicitly out of scope
/// until document size or real-time collaboration actually requires it —
/// same reasoning as CLAUDE.md's "CRDT deferred" rule. See the
/// "Bottom nav tools" roadmap plan for where this fits.
struct EditorHistory {
    struct Snapshot {
        var project: V2Project
        var transitions: [EditorTransitionIntent]
    }

    private var past: [Snapshot] = []
    private var future: [Snapshot] = []

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// Call right before replacing `current` with the result of a
    /// command — records `current` so `undo()` can return to it, and
    /// clears any redo history (a fresh edit invalidates whatever had
    /// been undone before it, same convention every undo stack uses).
    mutating func record(current: V2Project) {
        record(current: current, transitions: [])
    }

    mutating func record(current: V2Project, transitions: [EditorTransitionIntent]) {
        past.append(Snapshot(project: current, transitions: transitions))
        future.removeAll()
    }

    mutating func undo(current: V2Project) -> V2Project? {
        undo(current: current, transitions: [])?.project
    }

    mutating func undo(current: V2Project, transitions: [EditorTransitionIntent]) -> Snapshot? {
        guard let previous = past.popLast() else { return nil }
        future.append(Snapshot(project: current, transitions: transitions))
        return previous
    }

    mutating func redo(current: V2Project) -> V2Project? {
        redo(current: current, transitions: [])?.project
    }

    mutating func redo(current: V2Project, transitions: [EditorTransitionIntent]) -> Snapshot? {
        guard let next = future.popLast() else { return nil }
        past.append(Snapshot(project: current, transitions: transitions))
        return next
    }
}
