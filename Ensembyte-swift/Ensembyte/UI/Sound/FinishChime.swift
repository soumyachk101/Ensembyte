import AppKit

/// A short struck-tone chime, defined by its numbers and rendered to WAV on first use, so a
/// chime ships as a few numbers rather than a sound file and stays tunable right here.
/// The rendered sound is cached per chime: NSSound declines a play while one is in flight,
/// so two triggers of the same chime in the same moment make one chime, never a pile-up.
@MainActor
struct Chime {
    var notes: [ToneSynth.Note]
    var partials: [ToneSynth.Partial]
    /// How long the rendered wave is, in seconds.
    var duration: Double
    /// How loud the chime plays relative to the system volume.
    var volume: Float
    /// True for a chime that must replay from the top: it stops any prior playback before
    /// playing, so triggering it twice ticks twice. Left false, a chime in flight is left
    /// to finish and a second trigger is declined.
    var restartsOnReplay = false

    func play() {
        if restartsOnReplay {
            // A replay from the top, so settling two threads in a row ticks twice.
            Self.sound(for: self)?.stop()
        }
        Self.sound(for: self)?.play()
    }

    private static var cache: [Chime: NSSound?] = [:]

    private static func sound(for chime: Chime) -> NSSound? {
        if let sound = cache[chime] { return sound }
        let sound = NSSound(data: ToneSynth.wave(notes: chime.notes, partials: chime.partials, duration: chime.duration))
        sound?.volume = chime.volume
        cache[chime] = sound
        return sound
    }
}

extension Chime: Hashable {
    // A chime is what it plays: the cache keys off the whole recipe, so two chimes that
    // differ in any number get distinct sounds.
    nonisolated static func == (lhs: Chime, rhs: Chime) -> Bool {
        lhs.notes.count == rhs.notes.count
            && zip(lhs.notes, rhs.notes).allSatisfy {
                $0.frequency == $1.frequency && $0.onset == $1.onset && $0.level == $1.level
            }
            && lhs.partials.count == rhs.partials.count
            && zip(lhs.partials, rhs.partials).allSatisfy {
                $0.multiple == $1.multiple && $0.level == $1.level && $0.decay == $1.decay
            }
            && lhs.duration == rhs.duration
            && lhs.volume == rhs.volume
            && lhs.restartsOnReplay == rhs.restartsOnReplay
    }

    nonisolated func hash(into hasher: inout Hasher) {
        for note in notes {
            hasher.combine(note.frequency)
            hasher.combine(note.onset)
            hasher.combine(note.level)
        }
        for partial in partials {
            hasher.combine(partial.multiple)
            hasher.combine(partial.level)
            hasher.combine(partial.decay)
        }
        hasher.combine(duration)
        hasher.combine(volume)
        hasher.combine(restartsOnReplay)
    }
}

extension Chime {
    /// The soft two-note chime that marks a turn finishing: a rising fifth with a
    /// celesta-like tone. Well under a stock alert: it registers without cutting into
    /// whatever else is playing.
    static let finish = Chime(
        notes: [
            // D5 up to A5, the second note a beat later and a touch stronger, the way "done" lands.
            ToneSynth.Note(frequency: 587.33, onset: 0, level: 0.8),
            ToneSynth.Note(frequency: 880, onset: 0.14, level: 1),
        ],
        partials: [
            // The fundamental carries the tone; the octave and double octave add a brief
            // glint at the strike and are gone within a tenth of a second, which keeps it
            // soft rather than pingy.
            ToneSynth.Partial(multiple: 1, level: 1, decay: 0.14),
            ToneSynth.Partial(multiple: 2, level: 0.22, decay: 0.06),
            ToneSynth.Partial(multiple: 4, level: 0.08, decay: 0.04),
        ],
        duration: 0.7,
        volume: 0.35
    )
}
