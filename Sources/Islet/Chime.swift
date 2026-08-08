import AppKit

/// Every sound Islet makes, and there are only three.
///
/// The frequency rule that governs animation governs audio more strictly — an
/// animation can be ignored out of the corner of an eye, a sound cannot. So each
/// sound carries exactly one meaning:
///
/// - `workEnded`  — 25 minutes are up, a break begins.
/// - `breakEnded` — the break is over, work begins.
/// - `delete`     — a task was removed.
/// - `sessionEnd` — the whole session is complete.
///
/// The two transitions have their *own* sounds rather than sharing one, and that
/// is worth more than it sounds: the whole reason a transition makes a noise is
/// that you are not looking. One sound tells you *something* changed; two tell
/// you **which way**, which is the part you actually needed.
///
/// Checking a task, adding one, opening the panel and switching filters are all
/// deliberately silent: they happen tens of times a day, and a sound on any of
/// them would be noise within a day. Start and pause are silent for a different
/// reason — they are opposites, and one sound for both says nothing.
@MainActor
enum Chime {
    /// A task removed with the trash or a swipe.
    case delete
    /// Work ran out; a break begins. ~4×/day.
    case workEnded
    /// The break ran out; work begins. ~4×/day. The reason a sound exists at all
    /// is that the announcement is otherwise purely visual.
    case breakEnded
    /// A whole session finished. 2–3×/day, so it is allowed to be conclusive.
    case sessionEnd

    /// The role is the case; the file is a detail. Swapping a sound never means
    /// touching anything but this table.
    private var fileName: String? {
        switch self {
        case .delete: "pop"
        case .workEnded: "work-done-back-to-break"
        case .breakEnded: "break-done-back-to-work"
        case .sessionEnd: "ping-bing"
        }
    }

    /// The fallback is not politeness. A missing or unreadable asset would leave
    /// the app silently mute — the one failure nobody would ever notice.
    private var systemName: String {
        switch self {
        case .delete: "Pop"
        case .workEnded: "Tink"
        case .breakEnded: "Bottle"
        case .sessionEnd: "Glass"
        }
    }

    /// Loudness matched by ear against the files' measured peaks (pop 0.21 FS,
    /// ping-bing 0.35 FS), so one does not jump out beside the other.
    /// Matched by **measured RMS**, not by peak and not by ear.
    ///
    /// The two transition files arrived roughly 10 dB hotter than the others
    /// (RMS −18 dBFS against −28), so at equal volume they would have flattened
    /// everything else. These levels put them ~2.5 dB above the confirmations:
    /// an announcement should carry a little further than an acknowledgement,
    /// but only a little.
    private var volume: Float {
        switch self {
        case .delete: 0.8
        case .workEnded: 0.50
        case .breakEnded: 0.42
        case .sessionEnd: 0.75
        }
    }

    private static let extensions = ["wav", "aiff", "aif", "caf", "m4a", "mp3"]
    private static var cache: [Chime: NSSound] = [:]
    private static var lastPlayed: [Chime: Date] = [:]

    /// Three deletions in quick succession should confirm three times, not
    /// rattle. Short enough that a deliberate repeat still sounds; long enough
    /// that two fires in the same frame collapse into one.
    private static let minimumGap: TimeInterval = 0.12

    /// `ISLET_SOUND_LOG=1` prints each play, so the sequence of a session can be
    /// read rather than guessed at by ear.
    static let logsPlays = ProcessInfo.processInfo.environment["ISLET_SOUND_LOG"] != nil

    /// Called at launch: reading a file on first play would put disk I/O in the
    /// middle of a moment that is meant to feel immediate.
    static func preload() {
        for chime in [Chime.delete, .workEnded, .breakEnded, .sessionEnd] {
            _ = chime.sound
            // Says which source won. macOS ships a sound called "Pop" too, so
            // "it made a noise" is not proof the bundled file is being used.
            log("chime \(chime) → \(chime.resolvedSource)")
        }
    }

    private var resolvedSource: String {
        guard let fileName else { return "system \(systemName)" }
        for ext in Self.extensions where Bundle.main.url(
            forResource: fileName, withExtension: ext, subdirectory: "Sounds"
        ) != nil {
            return "bundled \(fileName).\(ext)"
        }
        return "system \(systemName) (no bundled file found)"
    }

    func play(enabled: Bool) {
        guard enabled, let sound else { return }

        let now = Date()
        if let last = Self.lastPlayed[self], now.timeIntervalSince(last) < Self.minimumGap {
            return
        }
        Self.lastPlayed[self] = now

        sound.stop()   // a second fire must restart, not layer
        sound.play()
        if Self.logsPlays { log("played \(self)") }
    }

    private var sound: NSSound? {
        if let cached = Self.cache[self] { return cached }

        let loaded = bundledSound() ?? NSSound(named: systemName)
        if loaded == nil {
            log("no sound available for \(self) — this event will be silent")
        }
        loaded?.volume = volume
        if let loaded { Self.cache[self] = loaded }
        return loaded
    }

    private func bundledSound() -> NSSound? {
        guard let fileName else { return nil }
        for ext in Self.extensions {
            guard let url = Bundle.main.url(forResource: fileName,
                                            withExtension: ext,
                                            subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: fileName, withExtension: ext)
            else { continue }
            if let sound = NSSound(contentsOf: url, byReference: false) {
                return sound
            }
            log("could not read \(url.lastPathComponent) — falling back to \(systemName)")
        }
        return nil
    }
}
