import SwiftUI

/// The geometry of a turn's work, drawn flat on the conversation: a quiet summary line
/// with its chevron, and under it a thin tree whose trunk runs down the chevron's centre
/// and rounds off into a short branch for every step. The step's icon sits at the branch
/// tip and its words follow, so every step, thought and narrated line shares one column.
enum ActivityMetrics {
    /// The trunk's x, on a half point so a one-point line lands on whole pixels.
    static let trunkX: CGFloat = 12.5
    static let bendRadius: CGFloat = 6
    /// Where a branch stops, four points short of the step's icon.
    static let branchEndX: CGFloat = 28
    /// The gutter before a step's own icon column.
    static let gutterWidth: CGFloat = 32
    /// A step's first line, centred in a 32-point band: the branch meets it at the middle.
    static let stepPadding: CGFloat = 8
    static let branchY: CGFloat = 16
    static let headerHeight: CGFloat = 26
    /// The chevron's slot: the chevron's centre sits on the trunk.
    static let chevronSlot: CGFloat = 22
    static let chevronSize: CGFloat = 14
    static let headerSpacing: CGFloat = 6
    static let bodyTopPadding: CGFloat = 2
    static let lineOpacity = 0.12
    /// Past this many steps the oldest wait behind a paging row.
    static let stepPage = 60

    /// The fold, both ways.
    static let fold = Animation.easeOut(duration: 0.14)
    /// A step arriving: its words fade up from four points below.
    static let rowReveal = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.36)
    static let revealLift: CGFloat = 4
    /// The branch drawing to a new step: brisk, then easing into the tip.
    static let connectorDuration: TimeInterval = 0.48
    static func connector(duration: TimeInterval) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }
    /// The share of the connector's time the step above spends growing its trunk down to
    /// the new step, before the new step's own leg starts.
    static let continuationShare = 0.45
    /// A new group's first step waits for the header to land.
    static let firstStepDelay: TimeInterval = 0.09
}

/// The steps that already drew themselves in, so a step scrolling back into view, or a
/// block rebuilt by the lazy stack, never plays its arrival again.
@MainActor
enum ActivityReveal {
    private static var seen: Set<String> = []

    /// True the first time `id` is asked about, false every time after.
    static func claim(_ id: String) -> Bool {
        if seen.count > 20_000 { seen.removeAll(keepingCapacity: true) }
        return seen.insert(id).inserted
    }
}

/// The summary line over a group: "Thought 2 times · Ran 2 commands · Edited 3 files".
/// Counted from the steps' kinds only, so a step's streaming output never reworded it.
@MainActor
enum ActivitySummary {
    static func text(for entries: [TimelineEntry]) -> String {
        var thoughts = 0
        var commands = 0
        var edited: Set<String> = []
        var reads = 0
        var searches = 0
        var fetches = 0
        var tools = 0
        var failed = 0
        for entry in entries {
            switch entry.item.content {
            case .reasoning:
                thoughts += 1
            case .tool(let call):
                if call.status == .failed { failed += 1 }
                switch call.kind {
                case .command:
                    commands += 1
                    // A command that changed files edited them, as its edit lines show.
                    for edit in call.edits where !edit.path.isEmpty { edited.insert(edit.path) }
                case .edit:
                    let paths = call.edits.map(\.path).filter { !$0.isEmpty }
                    if paths.isEmpty { edited.insert(call.title) } else { edited.formUnion(paths) }
                case .read: reads += 1
                case .search: searches += 1
                case .web: fetches += 1
                case .mcp, .agent, .other: tools += 1
                }
            default:
                break
            }
        }
        var parts: [String] = []
        switch thoughts {
        case 0: break
        case 1: parts.append("thought process")
        default: parts.append("thought \(thoughts) times")
        }
        if commands > 0 { parts.append("ran \(count(commands, "command", "commands"))") }
        if !edited.isEmpty { parts.append("edited \(count(edited.count, "file", "files"))") }
        if reads > 0 { parts.append("read \(count(reads, "file", "files"))") }
        if searches > 0 { parts.append("searched \(count(searches, "time", "times"))") }
        if fetches > 0 { parts.append("fetched \(count(fetches, "page", "pages"))") }
        if tools > 0 { parts.append("called \(count(tools, "tool", "tools"))") }
        if failed > 0 { parts.append("\(failed) failed") }
        guard !parts.isEmpty else { return "Worked" }
        let summary = parts.joined(separator: " · ")
        return summary.prefix(1).uppercased() + summary.dropFirst()
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }
}

/// Whether a tool row is drawn as a step of the tree: its icon at the branch tip, the
/// call's verb in the primary colour and its subject after it, the chevron on hover.
private struct ActivityTreeStyleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var activityTreeStyle: Bool {
        get { self[ActivityTreeStyleKey.self] }
        set { self[ActivityTreeStyleKey.self] = newValue }
    }
}

/// The header line of a group, and of a finished turn: the chevron in the trunk's slot,
/// pointing down while open, and the title, quiet until the pointer is on it. A group the
/// turn is still working in sweeps a soft light across its title.
struct ActivityHeaderLabel: View {
    let title: String
    let isOpen: Bool
    var isActive = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: ActivityMetrics.headerSpacing) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: ActivityMetrics.chevronSize, height: ActivityMetrics.chevronSize)
                .rotationEffect(.degrees(isOpen ? 0 : -90))
                .padding(.leading, ActivityMetrics.trunkX - ActivityMetrics.chevronSize / 2)
                .frame(width: ActivityMetrics.chevronSlot, alignment: .leading)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .modifier(ActivityShimmer(isActive: isActive))
        }
        .font(.chat(.callout))
        .foregroundStyle(isHovering ? AnyShapeStyle(Chrome.primaryText) : AnyShapeStyle(Chrome.secondaryText))
        .frame(height: ActivityMetrics.headerHeight)
        .padding(.trailing, 4)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }
}

/// A slow light sweeping across a working group's title. The highlight is the title again
/// in the primary colour, shown through a soft band that crosses it about every 1.7
/// seconds; a still frame while the reader scrolls, and none at all with reduced motion.
private struct ActivityShimmer: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("performanceMode", store: CaptureRun.defaults ?? .standard) private var performanceMode = false
    @State private var width: CGFloat = 0

    private static let period: TimeInterval = 3.4
    /// Half the band, as a share of the title's width.
    private static let halfBand: CGFloat = 0.36

    /// Where the band crossing the title is centred at `date`, in title widths: copies of
    /// the band sit three widths apart and travel six widths a period, so one crosses about
    /// every 1.7 seconds. Off the title (-1) between crossings.
    private static func bandCentre(at date: Date) -> CGFloat {
        let phase = CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
        let lead: CGFloat = -2.5 + phase * 6
        for copy in -2...2 {
            let centre = lead + CGFloat(copy) * 3
            if centre > -halfBand, centre < 1 + halfBand { return centre }
        }
        return -1
    }

    func body(content: Content) -> some View {
        if !isActive || reduceMotion || performanceMode {
            content
        } else {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .overlay {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: ScrollActivity.shared.isScrolling)) { context in
                        let centre = Self.bandCentre(at: context.date)
                        content
                            .foregroundStyle(Chrome.primaryText)
                            .mask(alignment: .leading) {
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white, location: 0.5),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: max(1, width * Self.halfBand * 2))
                                .offset(x: (centre - Self.halfBand) * width)
                            }
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

/// The trunk coming down from above and rounding off into this step's branch.
private struct ActivityBranch: Shape {
    func path(in rect: CGRect) -> Path {
        let x = ActivityMetrics.trunkX
        let y = ActivityMetrics.branchY
        let r = ActivityMetrics.bendRadius
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: y - r))
        path.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: ActivityMetrics.branchEndX, y: y))
        return path
    }
}

/// The trunk carrying on past this step to the next one, alongside whatever the step
/// has opened beneath its line.
private struct ActivityContinuation: Shape {
    func path(in rect: CGRect) -> Path {
        let x = ActivityMetrics.trunkX
        var path = Path()
        path.move(to: CGPoint(x: x, y: ActivityMetrics.branchY - ActivityMetrics.bendRadius))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        return path
    }
}

/// One step of a group: the gutter with its piece of the tree, then the step itself.
/// A step that arrives while the turn runs draws its branch in and then lifts its words
/// into place; one already there when the block was built draws whole and still.
private struct ActivityStep<Content: View>: View {
    let continues: Bool
    @ViewBuilder let content: Content
    @State private var connector: CGFloat
    @State private var revealed: Bool
    private let delay: TimeInterval
    private let hasPredecessor: Bool

    init(id: String, hasPredecessor: Bool, continues: Bool, animatesArrival: Bool, isFirstOfNewGroup: Bool, @ViewBuilder content: () -> Content) {
        self.continues = continues
        self.content = content()
        self.hasPredecessor = hasPredecessor
        let arrives = ActivityReveal.claim(id) && animatesArrival
        _connector = State(initialValue: arrives ? 0 : 1)
        _revealed = State(initialValue: !arrives)
        delay = isFirstOfNewGroup ? ActivityMetrics.firstStepDelay : 0
    }

    var body: some View {
        content
            .padding(.vertical, ActivityMetrics.stepPadding)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : ActivityMetrics.revealLift)
            .padding(.leading, ActivityMetrics.gutterWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ActivityBranch()
                        .trim(from: 0, to: connector)
                        .stroke(Chrome.primaryText.opacity(ActivityMetrics.lineOpacity), lineWidth: 1)
                    ActivityContinuation()
                        .trim(from: 0, to: continues ? 1 : 0)
                        .stroke(Chrome.primaryText.opacity(ActivityMetrics.lineOpacity), lineWidth: 1)
                        .animation(.easeIn(duration: ActivityMetrics.connectorDuration * ActivityMetrics.continuationShare), value: continues)
                }
                .frame(width: ActivityMetrics.gutterWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityHidden(true)
            }
            .onAppear {
                guard connector < 1 else { return }
                // Below a step, the trunk first grows down to this one; the first step of
                // a group draws its whole leg itself.
                let lead = hasPredecessor ? ActivityMetrics.connectorDuration * ActivityMetrics.continuationShare : 0
                let draw = ActivityMetrics.connectorDuration - lead
                withAnimation(ActivityMetrics.connector(duration: draw).delay(delay + lead)) { connector = 1 }
                // The words follow the branch into its tip.
                withAnimation(ActivityMetrics.rowReveal.delay(delay + lead + draw * 0.6)) { revealed = true }
            }
    }
}

/// A run of the turn's work as one group: the summary header and, open, the tree of its
/// steps. The group the turn is working in stays open on its own and closes once the turn
/// moves past it (reply text after it, or the turn's end); a group the reader opened or
/// closed keeps that choice.
struct ActivityGroup: View, Equatable {
    let id: String
    let entries: [TimelineEntry]
    let runtime: ThreadRuntime
    var workingDirectory: String?
    /// Whether the turn is still working in this group.
    var isLive = false
    @Environment(\.revealTimelineEnd) private var revealBox
    @Environment(\.timelineLiveAppearance) private var liveAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fallbackPin: Bool?
    @State private var fallbackStepLimit = ActivityMetrics.stepPage
    @State private var headerRevealed: Bool

    init(id: String, entries: [TimelineEntry], runtime: ThreadRuntime, workingDirectory: String? = nil, isLive: Bool = false) {
        self.id = id
        self.entries = entries
        self.runtime = runtime
        self.workingDirectory = workingDirectory
        self.isLive = isLive
        _headerRevealed = State(initialValue: !(isLive && ActivityReveal.claim("header-" + id)))
    }

    nonisolated static func == (lhs: ActivityGroup, rhs: ActivityGroup) -> Bool {
        lhs.id == rhs.id && lhs.entries == rhs.entries && lhs.runtime === rhs.runtime
            && lhs.workingDirectory == rhs.workingDirectory && lhs.isLive == rhs.isLive
    }

    private var pin: Bool? {
        get { revealBox?.presentation.groups[id] ?? fallbackPin }
        nonmutating set {
            if let revealBox { revealBox.presentation.groups[id] = newValue } else { fallbackPin = newValue }
        }
    }

    /// Kept with the timeline's presentation, like `pin`: a block windowed out and built
    /// again comes back showing the steps it showed, at the height its spacer stood in for.
    private var stepLimit: Int {
        get { revealBox?.presentation.activityStepLimits[id] ?? fallbackStepLimit }
        nonmutating set {
            if let revealBox { revealBox.presentation.activityStepLimits[id] = newValue }
            fallbackStepLimit = newValue
        }
    }

    var body: some View {
        let isOpen = pin ?? isLive
        let hidden = max(0, entries.count - stepLimit)
        let visible = hidden > 0 ? Array(entries.suffix(stepLimit)) : entries
        let animates = liveAppearance && isLive && !reduceMotion
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(ActivityMetrics.fold) { pin = !isOpen }
                if !isOpen { revealBox?.action() }
            } label: {
                ActivityHeaderLabel(title: ActivitySummary.text(for: entries), isOpen: isOpen, isActive: isLive)
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Hide these steps" : "Show these steps")
            .accessibilityLabel(Text(ActivitySummary.text(for: entries)))
            .accessibilityHint(Text(isOpen ? "Hides these steps" : "Shows these steps"))
            .opacity(headerRevealed ? 1 : 0)
            .offset(y: headerRevealed ? 0 : ActivityMetrics.revealLift)

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    if hidden > 0 {
                        Button(TurnFinishedBlock.earlierStepsLabel(hidden: hidden)) {
                            stepLimit += ActivityMetrics.stepPage
                        }
                        .buttonStyle(.plain)
                        .font(.chat(.callout))
                        .foregroundStyle(.secondary)
                        .padding(.leading, ActivityMetrics.gutterWidth + TimelineMetrics.iconWidth + TimelineMetrics.iconSpacing)
                        .padding(.vertical, ActivityMetrics.stepPadding)
                    }
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        ActivityStep(
                            id: entry.id,
                            hasPredecessor: index > 0,
                            continues: index < visible.count - 1,
                            animatesArrival: animates,
                            isFirstOfNewGroup: index == 0 && !headerRevealed
                        ) {
                            step(entry)
                        }
                    }
                }
                .padding(.top, ActivityMetrics.bodyTopPadding)
                .environment(\.activityTreeStyle, true)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : ActivityMetrics.fold, value: isOpen)
        .onAppear {
            guard !headerRevealed else { return }
            withAnimation(ActivityMetrics.rowReveal) { headerRevealed = true }
        }
    }

    @ViewBuilder
    private func step(_ entry: TimelineEntry) -> some View {
        switch entry.kind {
        case .tool:
            ToolRow(entry: entry, runtime: runtime, workingDirectory: workingDirectory)
        case .reasoning:
            ActivityThoughtStep(entry: entry, revealBox: revealBox)
        case .assistant:
            ActivityNarrationStep(entry: entry, runtime: runtime)
        default:
            EmptyView()
        }
    }
}

/// An animated, glowing AI reasoning shader orb with dynamic multi-color rotation.
struct ThinkingShaderOrb: View {
    var isThinking: Bool = true
    var size: CGFloat = 13

    @State private var isRotating = false
    @State private var isBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Vibrant cyan/purple/fuchsia/blue gradient
    private static let orbColors = [
        Color(red: 0.22, green: 0.74, blue: 0.97), // Cyan
        Color(red: 0.55, green: 0.36, blue: 0.96), // Violet
        Color(red: 0.91, green: 0.30, blue: 0.65), // Fuchsia
        Color(red: 0.23, green: 0.51, blue: 0.96)  // Blue
    ]

    var body: some View {
        ZStack {
            if isThinking {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: Self.orbColors,
                            center: .center,
                            angle: .degrees(isRotating ? 360 : 0)
                        )
                    )
                    .blur(radius: 3.5)
                    .opacity(isBreathing ? 0.8 : 0.45)
                    .scaleEffect(isBreathing ? 1.25 : 1.0)

                Circle()
                    .fill(
                        AngularGradient(
                            colors: Self.orbColors,
                            center: .center,
                            angle: .degrees(isRotating ? 360 : 0)
                        )
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.6)
                    }
                    .scaleEffect(isBreathing ? 1.05 : 0.95)
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.85),
                                Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion, isThinking else { return }
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                isRotating = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .onChange(of: isThinking) { _, thinking in
            guard !reduceMotion else { return }
            if thinking {
                withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    isRotating = true
                }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            } else {
                isRotating = false
                isBreathing = false
            }
        }
    }
}

/// The agent's thinking as an expandable trail:
/// features a live shader orb, present-tense step with running timer while streaming,
/// auto-collapsing to "Thought for 12s" when done, and an expandable trail with vertical guide line.
private struct ActivityThoughtStep: View {
    let entry: TimelineEntry
    let revealBox: TimelineRevealBox?
    @State private var fallbackPin: Bool?
    @State private var isHovering = false
    @State private var streamStartedAt: Date? = nil
    @State private var liveElapsed: Int = 0

    /// Kept with the timeline's presentation, so a windowed-out block comes back as it was.
    private var pin: Bool? {
        get { revealBox?.presentation.thoughtPins[entry.id] ?? fallbackPin }
        nonmutating set {
            if let revealBox { revealBox.presentation.thoughtPins[entry.id] = newValue } else { fallbackPin = newValue }
        }
    }

    private func durationText(for block: ReasoningBlock) -> String {
        let sec: Int
        if let d = block.durationSeconds, d > 0 {
            sec = max(1, Int(round(d)))
        } else if liveElapsed > 0 {
            sec = liveElapsed
        } else {
            let words = block.text.split(separator: " ").count
            sec = max(1, Int(round(Double(words) / 30.0)))
        }
        if sec < 60 { return "\(sec)s" }
        return "\(sec / 60)m \(sec % 60)s"
    }

    var body: some View {
        if case .reasoning(let block) = entry.item.content {
            let isOpen = pin ?? block.isStreaming
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(ActivityMetrics.fold) { pin = !isOpen }
                } label: {
                    HStack(spacing: 8) {
                        ThinkingShaderOrb(isThinking: block.isStreaming, size: 13)

                        if block.isStreaming {
                            Text("Thinking…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Chrome.primaryText)

                            Text("\(max(1, liveElapsed))s")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Chrome.secondaryText)
                                .contentTransition(.numericText())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Chrome.overlay(0.08)))
                        } else {
                            Text("Thought for \(durationText(for: block))")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(isHovering ? Chrome.primaryText : Chrome.secondaryText)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Chrome.secondaryText)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isOpen)
                            .opacity(isHovering || !block.isStreaming ? 0.9 : 0.5)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isHovering ? Chrome.overlay(0.08) : Chrome.overlay(0.035))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(isHovering ? Color.white.opacity(0.12) : Color.white.opacity(0.05), lineWidth: 0.8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help(isOpen ? "Hide reasoning trail" : "Show reasoning trail")

                if isOpen {
                    HStack(alignment: .top, spacing: 10) {
                        // Vertical trail guide line
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.7),
                                        Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.3),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 2)
                            .padding(.leading, 15)
                            .padding(.vertical, 2)

                        MarkdownView(text: block.text, isStreaming: block.isStreaming).equatable()
                            .foregroundStyle(.secondary)
                            .environment(\.markdownPointSize, 12)
                            .environment(\.markdownDimmed, true)
                            .padding(.trailing, 12)
                    }
                    .transition(.opacity)
                }
            }
            .task(id: block.isStreaming) {
                if block.isStreaming {
                    if streamStartedAt == nil { streamStartedAt = .now }
                    while !Task.isCancelled && block.isStreaming {
                        if let start = streamStartedAt {
                            liveElapsed = max(1, Int(Date.now.timeIntervalSince(start)))
                        }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            }
        }
    }
}

/// A line the agent said on its way to the next step, read as a step: small and quiet,
/// in the column of the steps around it.
private struct ActivityNarrationStep: View {
    let entry: TimelineEntry
    let runtime: ThreadRuntime

    var body: some View {
        if case .assistant(let message) = entry.item.content {
            HStack(alignment: .firstTextBaseline, spacing: TimelineMetrics.iconSpacing) {
                Image(systemName: "text.bubble")
                    .font(.chat(.caption))
                    .foregroundStyle(Chrome.secondaryText)
                    .frame(width: TimelineMetrics.iconWidth)
                MarkdownView(text: message.text, isStreaming: message.isStreaming).equatable()
                    .foregroundStyle(.secondary)
                    .environment(\.markdownPointSize, 12)
                    .environment(\.markdownDimmed, true)
                    .padding(.trailing, 12)
            }
            .messageMenu(text: message.text, runtime: runtime)
        }
    }
}

/// The line under a running turn: the dot grid pulsing, a word for what the agent is up
/// to (a new one every seven seconds, rolling in) and the time the turn has taken. Flat
/// on the conversation, like the steps above it.
struct ActivityStatusLine: View {
    let runtime: ThreadRuntime
    @State private var now = Date.now

    var body: some View {
        let startedAt = runtime.turnStartedAt
        let elapsed = Int64(max(0, now.timeIntervalSince(startedAt ?? now)))
        // Before the turn has begun the clock would count the send's round trip and then
        // start over; until then the line says the message is on its way.
        let word = startedAt == nil ? "Sending" : WorkingWords.word(seed: WorkingWords.seed(runtime.threadID.uuidString), elapsedSeconds: elapsed)
        HStack(spacing: 8) {
            ThinkingShaderOrb(isThinking: true, size: 13)
            Text("\(word)…")
                .font(.chat(.callout))
                .foregroundStyle(Chrome.primaryText.opacity(0.85))
                .id(word)
                .transition(.asymmetric(
                    insertion: .offset(y: 6).combined(with: .opacity),
                    removal: .offset(y: -6).combined(with: .opacity)
                ))
            if startedAt != nil {
                Text(Self.format(elapsed))
                    .font(.chat(.subheadline).monospacedDigit())
                    .foregroundStyle(Chrome.secondaryText)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Chrome.overlay(0.08)))
                    .offset(y: 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Chrome.overlay(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
        )
        .animation(.easeOut(duration: 0.55), value: word)
        .animation(.easeOut(duration: 0.3), value: elapsed)
        .accessibilityElement(children: .combine)
        .task(id: FrontMonitor.shared.isVisible) {
            // The timer ticks only while someone can see it.
            guard FrontMonitor.shared.isVisible else { return }
            now = .now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }

    /// "22s", "4m 5s", "1h 2m", "2d 3h": two units at most.
    static func format(_ seconds: Int64) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        if s < 3_600 { return "\(s / 60)m \(s % 60)s" }
        if s < 86_400 { return "\(s / 3_600)h \((s % 3_600) / 60)m" }
        return "\(s / 86_400)d \((s % 86_400) / 3_600)h"
    }
}
