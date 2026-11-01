import AppKit

extension Chime {
    /// The small sound of a thread settling: two soft wooden notes stepping down, the way a
    /// checkbox ticks and the row comes to rest. Quieter and shorter than the finish chime,
    /// and the setting can silence it.
    static let settle = Chime(
        notes: [
            // E5 down to C5, the second note right behind the first: a small landing.
            ToneSynth.Note(frequency: 659.26, onset: 0, level: 0.7),
            ToneSynth.Note(frequency: 523.25, onset: 0.075, level: 1),
        ],
        partials: [
            // A woody tone: the fundamental fades fast, a quiet third harmonic gives it a
            // knock at the strike, and the octave only glints.
            ToneSynth.Partial(multiple: 1, level: 1, decay: 0.075),
            ToneSynth.Partial(multiple: 3, level: 0.16, decay: 0.02),
            ToneSynth.Partial(multiple: 2, level: 0.08, decay: 0.03),
        ],
        duration: 0.32,
        volume: 0.18,
        restartsOnReplay: true
    )
}
