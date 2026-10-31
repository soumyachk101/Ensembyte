import SwiftUI

/// The thread's to-do list as a floating glass panel, read live from the thread's
/// `.todos` entries, the artifact panel's recipe.
struct TodoPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let runtime: ThreadRuntime
    let size: CGSize
    /// The pointer's travel since the handle was grabbed.
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HydraPanel.cornerRadius, style: .continuous)
        Group {
            content
        }
        .padding(.top, HydraPanel.stripHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Thread tasks"))
        .overlay(alignment: .top) {
            strip
        }
        .frame(width: size.width, height: size.height)
        .background {
            // The helper panel's recipe: one glass surface, a scrim for the text over
            // whatever the panel floats above, and the theme's tint.
            let isDark = colorScheme == .dark
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.fill(Chrome.glassTint.opacity(isDark ? 0.22 : 0.16))
                }
        }
        .clipShape(shape)
        // The scrim sits under the glass and carries the panel's shadow, drawn once.
        .background {
            let isDark = colorScheme == .dark
            shape
                .fill((isDark ? Color.black : Color.white).opacity(0.3))
                .shadow(color: .black.opacity(isDark ? 1 : 0.65), radius: 28, y: 10)
        }
    }

    /// The most recent non-empty `.todos` entry of this thread. The entries array and
    /// each entry's `item` are observed, so the panel redraws whenever the agent
    /// rewrites the checklist.
    private var steps: [TodoStep] {
        runtime.entries.reversed()
            .compactMap { entry -> [TodoStep] in
                if case .todos(let todoSteps) = entry.item.content { todoSteps } else { [] }
            }
            .first(where: { !$0.isEmpty }) ?? []
    }

    @ViewBuilder
    private var content: some View {
        if steps.isEmpty {
            emptyState
        } else {
            taskList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 22))
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Chrome.overlay(0.05))
                )
            Text("No tasks yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Chrome.primaryText)
            Text("The agent's to-do list appears here as it works.")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskList: some View {
        let done = steps.count { $0.status == .done }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(done) of \(steps.count) done")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
            ProgressView(value: Double(done), total: Double(max(1, steps.count)))
                .tint(Chrome.accent)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        stepRow(step)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, Chrome.chromeHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// One step: its glyph, its words — what it is doing while it runs — and the spinner
    /// on the step that is under way.
    private func stepRow(_ step: TodoStep) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Self.symbol(for: step.status))
                .font(.system(size: 12))
                .foregroundStyle(Self.iconColor(for: step.status))
            Text(verbatim: Self.text(for: step))
                .font(.system(size: 12.5))
                .foregroundStyle(Chrome.primaryText)
                .strikethrough(step.status == .done, color: .secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if step.status == .active {
                MiniSpinner()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if step.status == .active {
                Capsule().fill(Chrome.accent.opacity(0.14))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(Self.text(for: step)), \(step.status == .done ? "done" : (step.status == .active ? "in progress" : "not started"))")
        )
    }

    /// The step's words: while it is under way, the provider's own words for what it is
    /// doing; otherwise its plain text.
    private static func text(for step: TodoStep) -> String {
        if step.status == .active, let active = step.activeForm, !active.isEmpty { return active }
        return step.text
    }

    private static func symbol(for status: TodoStep.Status) -> String {
        switch status {
        case .pending: "circle"
        case .active: "circle.dotted.circle"
        case .done: "checkmark.circle.fill"
        }
    }

    private static func iconColor(for status: TodoStep.Status) -> Color {
        switch status {
        case .pending: Chrome.secondaryText
        case .active: Chrome.accent
        case .done: Chrome.success
        }
    }

    /// The handle across the top: the title at the left, the close button at the
    /// right, and the room between them drags the panel.
    private var strip: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                Text("Todos")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Chrome.primaryText.opacity(0.92))
            }
            .padding(.horizontal, Chrome.capsuleHorizontalPadding)
            .frame(height: Chrome.capsuleContentHeight)
            .padding(.vertical, Chrome.capsuleVerticalPadding)
            .fixedSize()
            .chromeGlassCapsule()
            // The title is a label, not a control, so it drags the panel too.
            .overlay {
                PanelDragHandle(onDrag: onDrag, onDragEnd: onDragEnd)
            }
            .padding(.top, Chrome.chromeTopPadding)
            .padding(.leading, Chrome.chromeHorizontalPadding)
            PanelDragHandle(onDrag: onDrag, onDragEnd: onDragEnd)
                .frame(maxWidth: .infinity)
                .frame(height: HydraPanel.stripHeight)
                .help("Drag to move")
                .accessibilityLabel(Text("Drag to move"))
            ChromeCircleButton(symbol: "xmark", help: "Close the todos panel") {
                dismiss()
            }
            .padding(.top, Chrome.chromeTopPadding)
            .padding(.trailing, Chrome.chromeHorizontalPadding)
        }
    }
}
