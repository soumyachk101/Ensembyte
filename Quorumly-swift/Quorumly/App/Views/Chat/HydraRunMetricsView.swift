import SwiftUI

/// What a Hydra run recorded, read off the turn records themselves: the tokens each turn
/// spent and the phases its heads went through.
///
/// Scoped as conversation totals on purpose. A request a provider continues lands on a
/// following turn, so no turn can be tied back to the delegation that started it; these
/// numbers are labelled as what the whole conversation recorded, never as one run's
/// comparison. Nothing here reads a live cumulative counter, so the text only moves when a
/// turn records something new rather than with every token a stream prints.
struct HydraRunMetrics: Equatable {
    /// Tokens one turn spent, as the provider reported them.
    struct Scope: Equatable {
        /// Turns in this scope, and how many of them carried usage.
        var turns = 0
        var turnsWithUsage = 0
        var hasUnloadedHistory = false
        /// Nil when no turn in the scope recorded usage: missing, never shown as zero.
        var tokens: Int?
        /// Where the scope's tokens came from, biggest first.
        var groups: [Group] = []

        /// Some of the scope's turns recorded nothing, so its total is a floor.
        var isPartial: Bool { hasUnloadedHistory || (tokens == nil ? turns > 0 : turnsWithUsage < turns) }
    }

    /// One provider and model's share of a scope.
    struct Group: Equatable, Identifiable {
        var id: String
        var provider: ProviderKind
        var model: String?
        var tokens: Int
    }

    /// A phase boundary that was never recorded stays unavailable rather than reading as a
    /// duration nobody measured.
    enum Phase: Equatable {
        case measured(TimeInterval)
        case running
        case unavailable

        var text: String {
            switch self {
            case .measured(let seconds): RelativeTime.duration(max(0, seconds))
            case .running: "in progress"
            case .unavailable: "unavailable"
            }
        }
    }

    /// One head's phases: the same boundaries the head's record holds, and nothing inferred.
    struct HeadTiming: Equatable, Identifiable {
        var id: UUID
        var personaIndex: Int
        var name: String
        var status: HydraHeadInfo.Status
        var queue: Phase = .unavailable
        var startup: Phase = .unavailable
        var execution: Phase = .unavailable
        /// Nil where no landing phase ever applied to this head.
        var landing: Phase?
    }

    var lead = Scope()
    var heads = Scope()
    var timings: [HeadTiming] = []

    /// The recorded total, nil when neither the lead nor its heads recorded anything.
    var recordedTokens: Int? {
        switch (lead.tokens, heads.tokens) {
        case let (leadTokens?, headTokens?): leadTokens + headTokens
        case let (leadTokens?, nil): leadTokens
        case let (nil, headTokens?): headTokens
        case (nil, nil): nil
        }
    }

    /// Some turns in the run recorded no usage, so the total is a floor.
    var isPartial: Bool { lead.isPartial || heads.isPartial }

    /// Two providers or more are blended into one number, which guides rather than bills.
    var spansProviders: Bool {
        Set((lead.groups + heads.groups).map(\.provider)).count > 1
    }

    var hasTimings: Bool { !timings.isEmpty }
}

/// Reads the snapshot. A closure supplies each head's turns, so the view stays the only
/// place that touches the head runtimes.
@MainActor
enum HydraRunMetricsReader {
    static func snapshot(
        leadTurns: [TurnRecord],
        heads: [ChatThread],
        headTurns: @MainActor (ChatThread) -> [TurnRecord]?
    ) -> HydraRunMetrics {
        var metrics = HydraRunMetrics()
        metrics.lead = spend(in: leadTurns)
        var headScope = HydraRunMetrics.Scope()
        var timings: [HydraRunMetrics.HeadTiming] = []
        for head in heads {
            if let timing = timing(of: head) { timings.append(timing) }
            guard let turns = headTurns(head) else {
                headScope.hasUnloadedHistory = true
                continue
            }
            let one = spend(in: turns)
            headScope.turns += one.turns
            headScope.turnsWithUsage += one.turnsWithUsage
            headScope.groups.append(contentsOf: one.groups)
            if let tokens = one.tokens {
                headScope.tokens = (headScope.tokens ?? 0) + tokens
            }
        }
        metrics.heads = HydraRunMetrics.Scope(
            turns: headScope.turns,
            turnsWithUsage: headScope.turnsWithUsage,
            hasUnloadedHistory: headScope.hasUnloadedHistory,
            tokens: headScope.tokens,
            groups: merged(headScope.groups)
        )
        metrics.timings = timings
        return metrics
    }

    /// The tokens the given turns recorded, with every turn's spend grouped by the pair
    /// that reported it.
    private static func spend(in turns: [TurnRecord]) -> HydraRunMetrics.Scope {
        var record = HydraRunMetrics.Scope()
        record.turns = turns.count
        var groups: [String: HydraRunMetrics.Group] = [:]
        var total = 0
        for turn in turns {
            guard let spends = turn.tokenSpends, !spends.isEmpty else { continue }
            record.turnsWithUsage += 1
            for entry in spends {
                total += entry.totalTokens
                let id = "\(entry.provider.rawValue)|\(entry.model ?? "")"
                groups[id, default: HydraRunMetrics.Group(id: id, provider: entry.provider, model: entry.model, tokens: 0)].tokens += entry.totalTokens
            }
        }
        guard record.turnsWithUsage > 0 else { return record }
        record.tokens = total
        record.groups = merged(Array(groups.values))
        return record
    }

    /// One group per provider and model, biggest first.
    private static func merged(_ groups: [HydraRunMetrics.Group]) -> [HydraRunMetrics.Group] {
        var byID: [String: HydraRunMetrics.Group] = [:]
        for group in groups {
            if var existing = byID[group.id] {
                existing.tokens += group.tokens
                byID[group.id] = existing
            } else {
                byID[group.id] = group
            }
        }
        return byID.values.sorted {
            $0.tokens == $1.tokens ? $0.id < $1.id : $0.tokens > $1.tokens
        }
    }

    /// A head's phases, from the boundaries its record carries.
    private static func timing(of head: ChatThread) -> HydraRunMetrics.HeadTiming? {
        guard let info = head.hydra else { return nil }
        var timing = HydraRunMetrics.HeadTiming(
            id: head.id,
            personaIndex: info.index,
            name: info.persona.name,
            status: info.status
        )
        if let queued = info.queuedAt {
            timing.queue = .measured(info.startedAt.timeIntervalSince(queued))
        }
        if let executing = info.executionStartedAt {
            timing.startup = .measured(executing.timeIntervalSince(info.startedAt))
        }
        timing.execution = phase(from: info.executionStartedAt, to: info.executionFinishedAt, isRunning: info.status == .running)
        // A head that never landed has no landing phase; only a head that started one and
        // cannot show its end is missing data.
        if info.landingStartedAt != nil || info.landingFinishedAt != nil {
            timing.landing = phase(from: info.landingStartedAt, to: info.landingFinishedAt, isRunning: info.status == .running)
        }
        return timing
    }

    private static func phase(from start: Date?, to end: Date?, isRunning: Bool) -> HydraRunMetrics.Phase {
        guard let start else { return .unavailable }
        guard let end else { return isRunning ? .running : .unavailable }
        return .measured(end.timeIntervalSince(start))
    }
}

/// A run's recorded usage and head timings, hung under the panel's strip while it is open.
/// One snapshot is read per change to the turns behind it, and the card itself is equatable
/// so redrawing the panel for any other reason leaves this text alone.
struct HydraRunMetricsView: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let heads: [ChatThread]

    var body: some View {
        HydraRunMetricsCard(metrics: snapshot)
            .equatable()
            .task(id: heads.map(\.id)) {
                await runtime.ensureLoaded()
                for head in heads {
                    guard !Task.isCancelled else { return }
                    await model.runtime(for: head.id).ensureLoaded()
                }
            }
    }

    private var snapshot: HydraRunMetrics {
        HydraRunMetricsReader.snapshot(leadTurns: runtime.turns, heads: heads) { head in
            guard let headRuntime = model.existingRuntime(for: head.id), !headRuntime.isLoadingHistory else { return nil }
            return headRuntime.turns
        }
    }
}

/// The card itself: what was recorded, where it was recorded, and what each head's phases
/// were. Deliberately flat on the panel's glass, like the head footer.
private struct HydraRunMetricsCard: View, Equatable {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let metrics: HydraRunMetrics

    /// Only the snapshot decides the drawing: the panel redraws for plenty of reasons that
    /// leave the card's text alone.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.metrics == rhs.metrics }


    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headline
            VStack(alignment: .leading, spacing: 6) {
                scopeRow("Lead", metrics.lead)
                scopeRow("Heads", metrics.heads)
                Divider()
                HStack(spacing: 8) {
                    Text(verbatim: "Total recorded")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Chrome.primaryText)
                    Spacer(minLength: 8)
                    Text(verbatim: totalText)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Chrome.primaryText)
                }
            }
            ForEach(metrics.lead.groups) { group in
                groupRow(group, scope: "Lead")
            }
            ForEach(metrics.heads.groups) { group in
                groupRow(group, scope: "Heads")
            }
            if metrics.hasTimings {
                Divider()
                Text(verbatim: "Head timings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Chrome.primaryText)
                ForEach(metrics.timings) { timing in
                    timingRow(timing)
                }
            }
            notes
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Chrome.panelControlFill(isDark: colorScheme == .dark))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Recorded usage and timings"))
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: metrics.recordedTokens == nil ? "No usage recorded yet" : "Recorded usage and timings")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Chrome.primaryText)
            Text(verbatim: "This conversation's lead and heads, as their turns reported it")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var totalText: String {
        guard let tokens = metrics.recordedTokens else { return "Not recorded" }
        let reported = "\(UsagePanel.tokens(tokens)) tokens"
        return metrics.isPartial ? reported + " or more" : reported
    }

    private func scopeRow(_ label: String, _ scope: HydraRunMetrics.Scope) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: label)
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
            Spacer(minLength: 8)
            Text(verbatim: scopeText(scope))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(scope.tokens == nil ? Chrome.secondaryText : Chrome.primaryText)
        }
    }

    private func scopeText(_ scope: HydraRunMetrics.Scope) -> String {
        guard let tokens = scope.tokens else {
            return scope.hasUnloadedHistory ? "Loading history…" : (scope.turns == 0 ? "None yet" : "Not recorded")
        }
        let reported = "\(UsagePanel.tokens(tokens)) tokens"
        guard scope.turnsWithUsage < scope.turns else { return reported }
        return reported + " · \(scope.turnsWithUsage) of \(scope.turns) turns"
    }

    /// The pair that reported this share, so a blended total says which models it blends.
    private func groupRow(_ group: HydraRunMetrics.Group, scope: String) -> some View {
        HStack(spacing: 6) {
            ProviderIcon(provider: group.provider, size: 11)
                .foregroundStyle(Chrome.secondaryText)
            Text(verbatim: modelName(group))
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(verbatim: "\(UsagePanel.tokens(group.tokens))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Chrome.secondaryText)
        }
        .padding(.leading, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(scope), \(modelName(group)), \(group.tokens) tokens"))
    }

    private func modelName(_ group: HydraRunMetrics.Group) -> String {
        let short = group.model.flatMap { model.providers.model($0, for: group.provider)?.shortName }
        return short ?? group.model ?? group.provider.displayName
    }

    /// One head's phases on one line: whatever its record actually carries.
    private func timingRow(_ timing: HydraRunMetrics.HeadTiming) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                HydraGlyph(persona: HydraRoster.persona(at: timing.personaIndex), size: 14, isRunning: timing.status == .running, status: timing.status)
                Text(verbatim: timing.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.primaryText)
                    .lineLimit(1)
                if timing.status == .running { MiniSpinner() }
                Spacer(minLength: 8)
            }
            Text(verbatim: phaseText(timing))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Chrome.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(timing.name), \(phaseText(timing))"))
    }

    private func phaseText(_ timing: HydraRunMetrics.HeadTiming) -> String {
        var parts = [
            "Queue \(timing.queue.text)",
            "Startup \(timing.startup.text)",
            "Run \(timing.execution.text)"
        ]
        if let landing = timing.landing { parts.append("Landing \(landing.text)") }
        return parts.joined(separator: " · ")
    }

    /// What the numbers are, and what they are not.
    private var notes: some View {
        VStack(alignment: .leading, spacing: 3) {
            note("Totals cover the conversation and its retained heads, not one run. Providers may omit usage for some requests.")
            if metrics.isPartial {
                note("Some turns recorded no usage, so the totals are lower bounds.")
            }
            if metrics.spansProviders {
                note("Recorded across providers, so the total guides rather than bills.")
            }
            if metrics.hasTimings {
                note("Heads work at the same time, so their durations overlap and are not added up.")
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10.5))
            .foregroundStyle(Chrome.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
