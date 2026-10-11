import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    // Second in the sidebar: Hydra is what the app is about, so it sits right under General.
    case hydra
    case appearance
    case providers
    case mcp
    case models
    case voice
    case sourceControl
    case shortcuts
    case archive
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .providers: "Providers"
        case .mcp: "MCP"
        case .models: "Models"
        case .voice: "Voice"
        case .hydra: "Hydra"
        case .sourceControl: "Source control"
        case .shortcuts: "Shortcuts"
        case .archive: "Archive"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gear"
        case .appearance: "paintpalette"
        case .providers: "cpu"
        case .mcp: "puzzlepiece.extension"
        case .models: "slider.horizontal.3"
        case .voice: "waveform"
        // Never drawn: the sidebar gives the Hydra row the dragon mark instead. Kept so
        // the switch stays exhaustive and anything else that asks gets a sane symbol.
        case .hydra: "point.3.connected.trianglepath.dotted"
        case .sourceControl: "arrow.triangle.branch"
        case .shortcuts: "command"
        case .archive: "archivebox"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: Chrome.gray
        case .appearance: Color(red: 0.85, green: 0.44, blue: 0.36)
        case .providers: Chrome.blue
        case .mcp: Color(red: 0.95, green: 0.55, blue: 0.20)
        case .models: Color(red: 0.686, green: 0.322, blue: 0.871)
        case .voice: Color(red: 0.93, green: 0.30, blue: 0.40)
        case .hydra: Color(red: 0.188, green: 0.690, blue: 0.780)
        case .sourceControl: Color(red: 0.345, green: 0.337, blue: 0.839)
        case .shortcuts: Color(red: 0.32, green: 0.48, blue: 0.93)
        case .archive: Chrome.orange
        case .about: Color(red: 0.204, green: 0.780, blue: 0.349)
        }
    }

    var keywords: [String] {
        switch self {
        case .general: ["permissions", "worktree", "reasoning", "thinking", "notifications", "token", "tokens", "activity", "usage", "panel", "limits", "credits", "heatmap", "daily", "weekly", "cumulative", "settle", "settled", "finish", "finished", "done", "sound", "chime", "icon", "icons", "emoji", "symbol", "symbols", "project mark", "compact", "concise", "anti-slop", "slop", "verbose", "comments", "replies"]
        case .appearance: ["appearance", "theme", "transparency", "transparent", "opacity", "glass", "dark", "light", "accent", "tint", "catppuccin", "dracula", "tokyo", "nord", "gruvbox", "solarized", "github", "claude", "codex", "cursor", "matrix", "text", "size", "font", "zoom", "wallpaper", "sidebar", "performance", "gpu"]
        case .models: ["model", "effort", "reasoning", "fast", "slider", "picker"]
        case .voice: ["voice", "speech", "talk", "call", "microphone", "mic", "realtime", "orb", "codex", "style"]
        case .hydra: ["hydra", "heads", "subagents", "sub-agents", "agents", "team", "orchestrator", "worker", "pair", "pairs", "parallel", "delegate", "queue"]
        case .providers: ["codex", "claude", "cursor", "opencode", "opencode zen", "opencode go", "zen", "grok", "deepseek", "meta", "muse", "spark", "zai", "z.ai", "glm", "coding plan", "devin", "cognition", "antigravity", "agy", "google", "gemini", "copilot", "github", "command code", "commandcode", "cmd", "pi", "omp", "oh-my-pi", "binary", "path", "sign in", "login", "api key", "usage", "limits", "limit", "plan", "quota", "credits", "balance"]
        case .mcp: ["mcp", "model context protocol", "servers", "tools", "connect", "integrations", "github", "playwright", "notion", "linear", "slack", "figma", "supabase", "stripe", "resend", "email", "context7", "sentry", "postgres", "browser", "netlify", "deploy", "hosting"]
        case .sourceControl: ["git", "commit", "pull request", "titles", "text generation", "github", "clone", "repository", "repositories", "repo", "sign in", "token", "connect", "account"]
        case .shortcuts: ["keyboard", "keys"]
        case .archive: ["archived", "restore"]
        case .about: ["version", "license"]
        }
    }
}

extension SettingsPage {
    /// Where a run of rows starts after a gap: the nav is grouped by spacing alone, the app's
    /// own preferences first, then the agents and what they connect to, then the rest.
    var startsNavGroup: Bool {
        self == .providers || self == .shortcuts
    }
}

/// Whether Settings has taken over the main window, and the page it shows. Settings is no
/// window of its own: the page list stands where the chat sidebar was and the page fills
/// the rest, while the chats stay built behind it, so going back finds them as they were.
/// The page outlives a close, so the next open lands where the last one left off; a deep
/// link (the update notification, the Hydra intro, a provider without a key) names one.
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    private(set) var isPresented = false
    var page: SettingsPage = .general

    func present(page: SettingsPage? = nil) {
        withAnimation(Chrome.panelSlide) {
            if let page { self.page = page }
            isPresented = true
        }
    }

    func dismiss() {
        guard isPresented else { return }
        withAnimation(Chrome.panelSlide) { isPresented = false }
    }
}

/// The page list that stands in for the chat sidebar while Settings is open: Back on top,
/// the search under it, then every page in its group.
struct SettingsSidebar: View {
    @Bindable private var navigation = SettingsNavigation.shared
    @State private var search = ""
    @State private var scrollTracker = SettingsScrollTracker()

    private var visiblePages: [SettingsPage] {
        let query = search.trimmed
        guard !query.isEmpty else { return SettingsPage.allCases }
        return SettingsPage.allCases.filter { page in
            page.title.localizedCaseInsensitiveContains(query)
                || page.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: Chrome.trafficLightDiameter)
                .padding(.top, Chrome.trafficLightTop)
            SettingsNavRow(title: "Back", isSelected: false, action: { WindowManager.shared.hideSettings() }) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 13, weight: .medium))
            }
            .help("Back to your threads")
            .padding(.horizontal, Chrome.listInset)
            .padding(.top, 10)
            SidebarSearchField(text: $search) {
                if let first = visiblePages.first { navigation.page = first }
            }
            .padding(.horizontal, Chrome.listInset)
            .padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visiblePages) { item in
                        SettingsNavRow(title: item.title, isSelected: navigation.page == item, action: { navigation.page = item }) {
                            Self.icon(for: item)
                        }
                        // Groups part by spacing alone, and only over the whole list: a search's
                        // matches sit together.
                        .padding(.top, item.startsNavGroup && search.trimmed.isEmpty ? 14 : 0)
                    }
                    if visiblePages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No results")
                                .font(.system(.body, weight: .semibold))
                                .foregroundStyle(Chrome.primaryText.opacity(0.92))
                            Text("Try a setting or a provider name.")
                                .font(.system(.subheadline))
                                .foregroundStyle(Chrome.secondaryText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, Chrome.listInset)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .allowsHitTesting(!scrollTracker.isFrozen)
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, _ in
                scrollTracker.note()
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { scrollTracker.note() } else { scrollTracker.coast() }
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background { WindowDragArea() }
        .onDisappear {
            scrollTracker.end()
            search = ""
        }
        // A search that filters the selected page out of the list left the detail pane on a
        // page no row was selected for; the first match takes over instead.
        .onChange(of: visiblePages) { _, pages in
            guard !pages.isEmpty, !pages.contains(navigation.page), let first = pages.first else { return }
            navigation.page = first
        }
    }

    @ViewBuilder
    private static func icon(for page: SettingsPage) -> some View {
        let size = SettingsNavRow<EmptyView>.iconSize
        if page == .hydra {
            // The Hydra page wears the dragon mark, the same one as the composer button.
            HydraMarkImage()
                .frame(width: size * 1.1, height: size * 1.1)
        } else {
            Image(systemName: page.symbol)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .frame(width: Chrome.iconSize, height: Chrome.iconSize)
                .overlay(alignment: .topTrailing) {
                    if page == .about, UpdateChecker.shared.updateAvailable {
                        UpdateAvailableDot()
                    }
                }
        }
    }
}

/// One row of the Settings page list: a little taller than a chat row, with a muted label
/// that comes up to full strength on the selected page.
struct SettingsNavRow<Icon: View>: View {
    static var iconSize: CGFloat { 15 }

    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let icon: Icon

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let text = isSelected || isHovering ? Chrome.primaryText : Chrome.secondaryText
        Button(action: action) {
            HStack(spacing: 8) {
                icon
                    .frame(width: Chrome.iconSize, height: Chrome.iconSize)
                Text(verbatim: title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .foregroundStyle(text)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(fill) }
            .contentShape(shape)
            .animation(Chrome.hover, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var fill: Color {
        if isSelected { return Chrome.overlay(0.12) }
        if isHovering { return Chrome.overlay(0.06) }
        return .clear
    }
}

/// The selected Settings page, filling the main window's detail pane: a centered column
/// under the page's own title, scrolling to the window's top edge beneath the chrome row.
struct SettingsDetail: View {
    @Environment(AppModel.self) private var model
    private let navigation = SettingsNavigation.shared
    @State private var modelSearch = ""
    @State private var mcpSearch = ""
    @State private var scrollChrome = ChromeScrollModel()
    @State private var scrollTracker = SettingsScrollTracker()

    /// The column's measure: wide enough for a card row and its control, narrow enough
    /// that a line of detail still reads at a glance on a wide window.
    private static let pageMaxWidth: CGFloat = 680
    private static let pagePadding: CGFloat = 40

    private var page: SettingsPage { navigation.page }

    var body: some View {
        Group {
            if page == .archive, model.archivedThreads.isEmpty {
                // An empty archive is one symbol in the middle of the pane: no sentence, no chrome,
                // no button with nothing to delete.
                Image(systemName: "archivebox")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Chrome.secondaryText.opacity(0.6))
                    .accessibilityLabel(Text("No archived threads"))
            } else {
                pageScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .detailSheet()
        .onDisappear { scrollTracker.end() }
        .onChange(of: page, initial: true) {
            scrollChrome.update(travel: 0)
            modelSearch = ""
            mcpSearch = ""
        }
    }

    private var pageScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Chrome.sectionSpacing) {
                Text(verbatim: page.title)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Chrome.primaryText)
                    .accessibilityAddTraits(.isHeader)
                pageContent
            }
            .frame(maxWidth: Self.pageMaxWidth, alignment: .leading)
            .padding(.horizontal, Self.pagePadding)
            .frame(maxWidth: .infinity)
            // Every page clears the chrome row, which carries the compact title once the
            // page's own has scrolled away, and the page's controls where it has any.
            .padding(.top, Chrome.chromeTopPadding + Chrome.capsuleHeight + 10)
            .padding(.bottom, 48)
            .allowsHitTesting(!scrollTracker.isFrozen)
        }
        .scrollIndicators(.never)
        .id(page)
        .onScrollGeometryChange(for: CGFloat.self, of: Self.travel) { _, travel in
            scrollTracker.note()
            scrollChrome.update(travel: travel)
        }
        .onScrollPhaseChange { _, phase in
            // Fingers on the content freeze the rows (no click can land then anyway); the
            // moment the scroll coasts or settles they come back, so a click that stops a
            // flick always reaches its target. Wheel scrolling reports no phases and is
            // caught by the movement above instead.
            if phase == .interacting { scrollTracker.note() } else { scrollTracker.coast() }
        }
        .overlay(alignment: .top) {
            PaneTopVeil(model: scrollChrome)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 10) {
                ChromeCompactTitle(title: page.title, model: scrollChrome)
                if page == .models {
                    ChromeSearchField(query: $modelSearch, prompt: "Search models")
                }
                if page == .mcp {
                    ChromeSearchField(query: $mcpSearch, prompt: "Search servers")
                }
                if page == .providers {
                    ProvidersRefreshButton()
                }
                if page == .archive {
                    ArchiveDeleteAllButton()
                }
                if page == .about {
                    AboutUpdateChromeAccessory()
                }
            }
            .frame(minHeight: Chrome.capsuleHeight)
            .padding(.horizontal, Chrome.chromeHorizontalPadding)
            .padding(.top, Chrome.chromeTopPadding)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .general: GeneralSettingsPage()
        case .appearance: AppearanceSettingsPage()
        case .providers: ProvidersSettingsPage()
        case .mcp: MCPSettingsPage(query: mcpSearch)
        case .models:
            ModelsSettingsPage(query: modelSearch)
        case .hydra: HydraSettingsPage()
        case .voice: VoiceSettingsPage()
        case .sourceControl: SourceControlSettingsPage()
        case .shortcuts: ShortcutsSettingsPage()
        case .archive: ArchiveSettingsPage()
        case .about: AboutSettingsPage()
        }
    }

    private nonisolated static func travel(_ geometry: ScrollGeometry) -> CGFloat {
        geometry.contentOffset.y + geometry.contentInsets.top
    }
}

struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

private struct GeneralSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        // The Token activity heatmap leads the page: it summarizes what the
        // settings below configure, rather than configuring anything itself.
        TokenActivitySection()
        ChromeSection(title: "New threads") {
            ChromeCard {
                // No picker: a new thread follows the one it is made from, and the composer's
                // model picker is where the provider is chosen (see `AppModel.newThread`).
                ChromeRow(title: "Provider and model", detail: "A new thread follows the one you are in: its provider, model, effort and Hydra pair. With no thread open it starts on the provider you last chose.") {
                    EmptyView()
                }
                ChromeRowDivider()
                ChromeRow(title: "Permissions", detail: settings.defaultRuntimeMode.summary) {
                    GlassPickerButton(options: RuntimeMode.allCases.map { ($0, $0.title) }, selection: $settings.defaultRuntimeMode, symbol: { $0.symbol })
                }
                ChromeRowDivider()
                ChromeRow(title: "Workspace", detail: "Where a new thread makes its changes") {
                    ChromeVisualPicker(options: WorkspaceMode.allCases.map { ($0, $0.title) }, selection: $settings.defaultWorkspaceMode) { mode in
                        Image(systemName: mode == .local ? "folder" : "arrow.triangle.branch")
                    }
                }
            }
        }
            ChromeSection(title: "Conversation") {
                ChromeCard {
                    ChromeRow(title: "Show thinking", detail: "The agent's thinking shows as a step of its work") {
                        SettingsSwitch(isOn: $settings.showReasoning)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Concise AI replies", detail: "Built-in guidance for shorter replies, useful code comments, and focused work, including Hydra heads. Changes apply on the next message.") {
                        SettingsSwitch(isOn: $settings.antiSlopEnabled)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Timeline haptics", detail: "Play haptic feedback when hovering over timeline ticks and progress bars") {
                        GlassPickerButton(options: TimelineHapticStyle.allCases.map { ($0, $0.title) }, selection: $settings.timelineHapticStyle)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Recent downloads", detail: "The attach button offers recent downloads first") {
                        SettingsSwitch(isOn: $settings.recentDownloadsPicker)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Notify when a turn finishes") {
                    SettingsSwitch(isOn: $settings.notifyWhenFinished)
                }
                ChromeRowDivider()
                ChromeRow(title: "Chime when a turn finishes", detail: "A soft chime, whether or not the thread is in view") {
                    SettingsSwitch(isOn: $settings.chimeWhenFinished)
                }
                // Switching it on plays the chime once, so you hear what you are getting.
                .onChange(of: settings.chimeWhenFinished) { _, isOn in
                    if isOn { FinishChime.play() }
                }
                ChromeRowDivider()
                ChromeRow(title: "Confirm before deleting threads") {
                    SettingsSwitch(isOn: $settings.confirmBeforeDeleting)
                }
                ChromeRowDivider()
                ChromeRow(title: "Continue after a usage limit", detail: "When the provider's limit is spent, the chat waits for the reset and then tells the agent to carry on") {
                    SettingsSwitch(isOn: $settings.autoContinueAfterLimit)
                }
                ChromeRowDivider()
                ChromeRow(
                    title: "Show a usage panel",
                    detail: "The plan's limits and credits in a floating panel beside every chat, for the model in use or a pair's two; the usage popover's pop-out button switches it on as well, and it keeps the corner it was last dragged to"
                ) {
                    SettingsSwitch(isOn: $settings.showsUsagePanel)
                }
            }
        }
        ChromeSection(title: "Projects") {
            ChromeCard {
                ChromeRow(title: "Projects", detail: "Activates every project at once unless explicitly overridden") {
                    SettingsSwitch(isOn: $settings.projectsEnabled)
                }
                ChromeRowDivider()
                ChromeRow(title: "Marks", detail: "An emoji or symbol for each project, drawn before the thread's name in the activity list and on the project's own row") {
                    ProjectMarksRow()
                }
            }
        }
        ChromeSection(title: "Finished threads") {
            ChromeCard {
                ChromeRow(title: "Done with a thread", detail: settings.threadFinishAction.detail) {
                    ChromeVisualPicker(options: ThreadFinishAction.allCases.map { ($0, $0.title) }, selection: $settings.threadFinishAction) { action in
                        Image(systemName: action == .settle ? "checkmark" : "archivebox")
                    }
                }
                ChromeRowDivider()
                ChromeRow(title: "Sound when settling", detail: "A small note as the thread settles") {
                    SettingsSwitch(isOn: $settings.settleSound)
                }
                // Switching it on plays the note once, so you hear what you are getting.
                .onChange(of: settings.settleSound) { _, isOn in
                    if isOn { SettleChime.play() }
                }
                .disabled(settings.threadFinishAction != .settle)
                .opacity(settings.threadFinishAction == .settle ? 1 : 0.5)
            }
        }
    }
}

/// The window's look: theme, transparency, sidebar and activity styling, the wallpaper
/// behind the glass, and the conversation's text size.
private struct AppearanceSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        ChromeSection(title: "Appearance") {
            ChromeCard {
                ChromeRow(title: "Theme", detail: settings.theme.detail) {
                    ThemePickerButton(selection: $settings.theme)
                }
                ChromeRowDivider()
                ChromeRow(title: "Transparency", detail: "How much shows through the window") {
                    BackdropOpacitySlider(value: $settings.backdropOpacity)
                }
                .disabled(settings.performanceMode)
                .opacity(settings.performanceMode ? 0.5 : 1)
                ChromeRowDivider()
                ChromeRow(title: "Performance Mode", detail: "Disable window transparency, blurs, glows and background effects for lowest GPU usage") {
                    SettingsSwitch(isOn: $settings.performanceMode)
                }
                ChromeRowDivider()
                ChromeRow(title: "Sidebar", detail: settings.sidebarMode.detail) {
                    ChromeVisualPicker(options: SidebarMode.allCases.map { ($0, $0.title) }, selection: $settings.sidebarMode) { mode in
                        Image(systemName: mode == .column ? "sidebar.left" : (mode == .floating ? "macwindow.on.rectangle" : "macwindow"))
                    }
                }
                ChromeRowDivider()
                ChromeRow(title: "Activity list", detail: settings.activityThreadStyle.detail) {
                    ChromeVisualPicker(options: ActivityThreadStyle.allCases.map { ($0, $0.title) }, selection: $settings.activityThreadStyle) { style in
                        Image(systemName: style == .icon ? "list.bullet" : "text.alignleft")
                    }
                }
                ChromeRowDivider()
                // Meaningless without a column: dimmed while only the panel is shown.
                ChromeRow(title: "Open the sidebar at launch", detail: "Collapsed otherwise; the list button in the toolbar shows and hides it any time") {
                    SettingsSwitch(isOn: Binding(
                        get: { model.sidebar.startsOpen },
                        set: { model.sidebar.startsOpen = $0 }
                    ))
                }
                .disabled(settings.sidebarMode == .panelOnly)
                .opacity(settings.sidebarMode == .panelOnly ? 0.5 : 1)
            }
            WallpaperCard()
            AppZoomCard(percent: $settings.appZoom)
        }
    }
}

/// The app-wide zoom: Zoom out and Zoom in step through the levels, the stock size is a
/// click away, and the percentage says where it sits.
private struct AppZoomCard: View {
    @Binding var percent: Int

    private var current: Int { AppZoom.normalized(percent) }

    var body: some View {
        ChromeCard {
            ChromeRow(title: "Zoom", detail: current == 100 ? "The stock size" : "\(current)% of the stock size") {
                HStack(spacing: 8) {
                    Button {
                        percent = AppZoom.next(percent, increasing: false)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(.subheadline))
                            .foregroundStyle(Chrome.secondaryText)
                            .frame(width: 22, height: 22)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(current == AppZoom.levels.first)
                    .help("Zoom out")
                    Text("\(current)%")
                        .font(.system(.subheadline, weight: .medium).monospacedDigit())
                        .foregroundStyle(Chrome.primaryText)
                        .frame(minWidth: 46)
                    Button {
                        percent = AppZoom.next(percent, increasing: true)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(.subheadline))
                            .foregroundStyle(Chrome.secondaryText)
                            .frame(width: 22, height: 22)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(current == AppZoom.levels.last)
                    .help("Zoom in")
                    Button {
                        percent = 100
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(Chrome.secondaryText)
                            .frame(width: 22, height: 22)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(current == 100)
                    .opacity(current == 100 ? 0 : 1)
                    .help("Back to the stock size")
                }
                .animation(.snappy(duration: 0.2), value: current)
            }
        }
    }
}

/// Clear glass on the left, a solid base on the right, the stock look in the middle,
/// with a reset that shows only once the slider has left the stock look.
private struct BackdropOpacitySlider: View {
    @Binding var value: Double

    private var isOffStock: Bool { abs(value - AppSettings.defaultBackdropOpacity) >= 0.005 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted")
                .font(.system(.subheadline))
                .foregroundStyle(Chrome.secondaryText)
                .help("Clear")
            Slider(value: $value, in: 0...1)
                .controlSize(.small)
                .frame(width: 140)
            Image(systemName: "circle.fill")
                .font(.system(.subheadline))
                .foregroundStyle(Chrome.secondaryText)
                .help("Solid")
        }
        // The reset takes no room in the row, so the slider ends flush with the card's
        // other controls whether or not it shows; it fades in to the slider's left once
        // the value has left the stock look.
        .overlay(alignment: .leading) {
            if isOffStock {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { value = AppSettings.defaultBackdropOpacity }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Chrome.secondaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Back to the stock look")
                .offset(x: -28)
                .transition(.opacity.combined(with: .offset(x: 6)))
            }
        }
        .animation(.snappy(duration: 0.2), value: isOffStock)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Window transparency"))
    }
}

private struct ProvidersRefreshButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ChromeCapsule {
            ChromeIconButton(
                symbol: "arrow.clockwise",
                isEnabled: !model.providers.isRefreshing,
                help: model.providers.isRefreshing ? "Checking providers…" : "Check providers again"
            ) {
                Task { await model.providers.refreshEverything() }
            }
        }
    }
}

/// Shows what launch (or the refresh button) last found: opening or scrolling the page checks no provider.
/// The reads it starts on its own are the CLI release feeds (cached for fifteen minutes) and each
/// signed-in account's usage limits, which the registry throttles to once a minute, so the numbers are on screen without a trip through a chat.
private struct ProvidersSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        /// "Configured" means authenticated: a signed-in provider.
        let configured: (ProviderKind) -> Bool = { provider in
            if case .signedIn = model.providers.status(provider).auth { return true }
            return false
        }
        // Configured providers lead, the rest follow; each group keeps allCases' own
        // order (a stable split, not a sort). An auth refresh reorders instantly.
        let providers = ProviderKind.allCases.filter(configured) + ProviderKind.allCases.filter { !configured($0) }
        // One card, one compact row per provider, every row collapsed until opened. Eager on
        // purpose: lazy rows were rebuilt while scrolling, which reset their fields and
        // re-ran every check they started on appear.
        ChromeCard {
            ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
                if index > 0 { ChromeRowDivider() }
                ProviderSettingsSection(
                    provider: provider,
                    isExpanded: Binding(
                        get: { ProviderRowExpansion.shared.expanded.contains(provider) },
                        set: { expanded in
                            if expanded {
                                ProviderRowExpansion.shared.expanded.insert(provider)
                            } else {
                                ProviderRowExpansion.shared.expanded.remove(provider)
                            }
                        }
                    )
                )
            }
        }
        // Opening the page asks the release feeds again when the last answer is a while old.
        .task { await model.providers.checkCLIUpdates(freshness: ProviderRegistry.cliCheckFreshnessOnOpen) }
    }
}

/// Which provider rows are open, for this run of the app only: Settings reopens on the rows
/// left open, a relaunch starts with every row collapsed.
@MainActor
@Observable
final class ProviderRowExpansion {
    static let shared = ProviderRowExpansion()
    var expanded: Set<ProviderKind> = []
}

private struct ProviderSettingsSection: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind
    /// Whether the row is open (`ProviderRowExpansion`): every row starts collapsed.
    @Binding var isExpanded: Bool

    @State private var binaryPath = ""
    @State private var apiKey = ""
    @State private var showsAPIKey = false
    @State private var keyCheck: Task<Void, Never>?

    /// Limits and credits belong to a signed-in account, so a missing or signed-out provider shows none.
    private var showsUsage: Bool {
        guard PlanLimitsReader.exposesLimits(provider) || CreditsReader.exposesCredits(provider) else { return false }
        let status = model.providers.status(provider)
        return status.isInstalled && status.auth != .signedOut
    }

    /// Whether the page offers a sign-in row: hidden while the provider is signed in and
    /// working, and while a check runs, so it never flashes in before the answer.
    private var showsSignIn: Bool {
        let status = model.providers.status(provider)
        if case .signedIn = status.auth { return false }
        return !status.isChecking
    }

    /// The row's second line: the provider's state. A CLI's version and its update follow
    /// on a line of their own (`ProviderUpdateSubtitle`).
    private var rowSubtitle: String {
        let status = model.providers.status(provider)
        if status.isChecking { return "Checking…" }
        if provider.isAPIKeyBased, status.apiKeyConfigured, let host = provider.apiHost {
            return "Native API · \(host)"
        }
        return status.summary
    }

    /// Whether the row has anything to open. Every provider has a binary path or a key
    /// today; the chevron goes for any that ends up with nothing to show.
    private var hasDetails: Bool {
        !provider.isAPIKeyBased || provider.acceptsAPIKey || showsUsage || showsAccounts
    }

    /// Providers that take several logins list them; the others show their one account's usage.
    private var showsAccounts: Bool {
        provider.supportsAccounts && model.providers.status(provider).isInstalled
    }

    var body: some View {
        let status = model.providers.status(provider)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    guard hasDetails else { return }
                    withAnimation(Chrome.panelSlide) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        ProviderIcon(provider: provider, size: 16)
                            .foregroundStyle(Chrome.primaryText)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Chrome.overlay(0.06))
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: provider.displayName)
                                .font(.system(.body, weight: .medium))
                                .foregroundStyle(Chrome.primaryText)
                            Text(verbatim: rowSubtitle)
                                .font(.system(.subheadline))
                                .foregroundStyle(Chrome.secondaryText)
                                .lineLimit(1)
                            // A CLI's version, a newer one when it is out, and the update's progress.
                            if !provider.isAPIKeyBased {
                                ProviderUpdateSubtitle(provider: provider)
                            }
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(ChromeQuietButtonStyle())
                .accessibilityLabel(Text(provider.displayName))
                .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
                // Update when a newer CLI is out, Install while it is missing.
                if !provider.isAPIKeyBased {
                    ProviderUpdateAction(provider: provider)
                }
                if hasDetails {
                    Button {
                        withAnimation(Chrome.panelSlide) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Chrome.secondaryText)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 22, height: 22)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Hide the \(provider.displayName) settings" : "Show the \(provider.displayName) settings")
                    .accessibilityHidden(true)
                }
                SettingsSwitch(isOn: Binding(
                    get: { model.settings.isEnabled(provider) },
                    set: { model.settings.setEnabled($0, for: provider) }
                ))
            }
            .padding(.leading, 12)
            .padding(.trailing, Chrome.rowControlTrailingPadding)
            .padding(.vertical, 9)
            ChromeRevealLayout(fraction: isExpanded ? 1 : 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if showsAccounts {
                        ChromeRowDivider()
                        ProviderAccountsSection(provider: provider, isExpanded: isExpanded)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    } else if showsUsage {
                        ChromeRowDivider()
                        VStack(alignment: .leading, spacing: 14) {
                            if PlanLimitsReader.exposesLimits(provider) {
                                PlanLimitsView(provider: provider)
                            }
                            if CreditsReader.exposesCredits(provider) {
                                CreditsView(provider: provider)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    if provider.acceptsAPIKey {
                        ChromeRowDivider()
                        ChromeRow(
                            title: provider.isAPIKeyBased ? "API key" : "API key (optional)",
                            detail: provider.isAPIKeyBased
                                ? "Stored in your Keychain. Get one at \(provider.apiKeySource ?? "the provider dashboard")."
                                : "Instead of `\(provider.loginCommand)`: a Studio key from \(provider.apiKeySource ?? "the provider dashboard"), stored in your Keychain and handed to the CLI."
                        ) {
                            HStack(spacing: 8) {
                                Group {
                                    if showsAPIKey {
                                        TextField("", text: $apiKey, prompt: Text("sk-…"))
                                    } else {
                                        SecureField("", text: $apiKey, prompt: Text("sk-…"))
                                    }
                                }
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 200)
                                Button {
                                    showsAPIKey.toggle()
                                } label: {
                                    Image(systemName: showsAPIKey ? "eye.slash" : "eye")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Chrome.secondaryText)
                                .help(showsAPIKey ? "Hide the API key" : "Show the API key")
                            }
                        }
                        if provider.isAPIKeyBased, !status.isInstalled {
                            ChromeRowDivider()
                            ChromeRow(title: "Get a key", detail: "\(provider.displayName) needs an API key. Nothing to install.") {
                                Link(destination: provider.installURL) {
                                    Text(verbatim: "Get a \(provider.displayName) key")
                                        .frame(height: Chrome.rowButtonLabelHeight)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                    if !provider.isAPIKeyBased {
                        ChromeRowDivider()
                        ChromeRow(title: "Binary path", detail: status.executable?.path) {
                            TextField("", text: $binaryPath, prompt: Text(provider.executableName))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 200)
                        }
                        if status.isInstalled {
                            ChromeRowDivider()
                            ProviderUpdateMonitoringRow(provider: provider)
                        }
                        if !status.isInstalled {
                            ChromeRowDivider()
                            ChromeRow(title: "Install", detail: "\(provider.displayName) was not found on your PATH.") {
                                Link(destination: provider.installURL) {
                                    Text(verbatim: "Get \(provider.displayName)")
                                        .frame(height: Chrome.rowButtonLabelHeight)
                                }
                                .buttonStyle(.glass)
                            }
                        } else if showsSignIn, !showsAccounts {
                            // Providers with accounts sign each one in from its own row.
                            ChromeRowDivider()
                            ChromeRow(title: "Sign in", detail: "Click here to login again.") {
                                Button {
                                    Workspace.openTerminal(running: provider.loginCommand)
                                } label: {
                                    Text(verbatim: "Login").frame(height: Chrome.rowButtonLabelHeight)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                }
            }
            // Collapsed content is neither focusable, tappable nor in the accessibility
            // tree; the clip reveals it top-anchored as the fraction slides.
            .clipped()
            .disabled(!isExpanded)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
        }
        .onAppear {
            binaryPath = model.settings.binaryPath(for: provider)
            if provider.acceptsAPIKey { apiKey = model.settings.apiKeyInput(for: provider) }
        }
        .onChange(of: showsUsage, initial: true) { _, shows in
            // Fires once when the page opens on a signed-in account and again when a check signs
            // one in. Sections are eager, so scrolling never re-fires it, and the registry hands
            // back what it read within the last minute instead of asking the provider again.
            guard shows else { return }
            model.providers.refreshPlanLimits(provider)
            model.providers.refreshCredits(provider)
        }
        .onChange(of: binaryPath) { _, value in
            guard value != model.settings.binaryPath(for: provider) else { return }
            model.settings.setBinaryPath(value, for: provider)
        }
        .onChange(of: apiKey) { _, value in
            // Only an edit counts: loading the stored key into the field must not save or check it.
            guard provider.acceptsAPIKey, value != model.settings.apiKeyInput(for: provider) else { return }
            model.settings.setAPIKeyInput(value, for: provider)
            keyCheck?.cancel()
            keyCheck = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                await model.providers.refresh(provider)
                await model.providers.loadCatalog(provider, force: true)
            }
        }
        .onChange(of: model.settings.apiKeyInput(for: provider)) { _, value in
            guard provider.acceptsAPIKey, value != apiKey else { return }
            apiKey = value
        }
    }
}

private struct SourceControlSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        GitHubSettingsSection()
        ChromeSection(title: "Text generation") {
            ChromeCard {
                ChromeRow(
                    title: "Thread titles and commit messages",
                    detail: "Automatic uses the thread's own provider. Claude uses Haiku, Codex your default model."
                ) {
                    GlassPickerButton(options: TextGenerationChoice.allCases.map { ($0, $0.title) }, selection: $settings.textGeneration, asset: { ProviderKind(rawValue: $0.rawValue)?.iconName })
                }
            }
        }
        ChromeSection(title: "Commit message instructions") {
            ChromeCard {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $settings.commitInstructions)
                        .font(.system(.body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90)
                    if settings.commitInstructions.isEmpty {
                        Text("For example: use conventional commit prefixes")
                            .font(.system(.body))
                            .foregroundStyle(Chrome.secondaryText)
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(12)
            }
        }
        ChromeSection(title: "Worktrees and pull requests") {
            ChromeCard {
                ChromeRow(title: "Worktrees", detail: Storage.worktreesDirectory.path) {
                    Button("Reveal") { Workspace.revealInFinder(Storage.worktreesDirectory.path) }
                        .buttonStyle(.glass)
                }
                ChromeRowDivider()
                ChromeRow(title: "Pull requests", detail: "Opened with the GitHub CLI (gh) or GitLab CLI (glab) from your PATH.") {
                    EmptyView()
                }
            }
        }
    }
}

/// Clears the whole archive from the page's chrome row, asking first the way a single
/// delete does when the setting is on. The question hangs off the button as a popover,
/// like the sidebar's delete menu, rather than a sheet over the whole window.
private struct ArchiveDeleteAllButton: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirming = false

    var body: some View {
        let count = model.archivedThreads.count
        ChromeTextButton(
            symbol: "trash",
            title: "Delete all",
            help: "Delete every archived thread",
            isEnabled: count > 0,
            isDestructive: true
        ) {
            if model.settings.confirmBeforeDeleting {
                isConfirming = true
            } else {
                model.deleteArchivedThreads()
            }
        }
        .popover(isPresented: $isConfirming, arrowEdge: .bottom) {
            PopoverMenu {
                PopoverSectionHeader(count == 1 ? "Delete the archived thread?" : "Delete all archived threads?")
                PopoverNote(count == 1
                    ? "Its history will be removed. Files in your project stay as they are."
                    : "The histories of all \(count) threads will be removed. Files in your projects stay as they are.")
                PopoverDivider()
                PopoverItem(count == 1 ? "Delete thread" : "Delete \(count) threads", symbol: "trash", isDestructive: true) {
                    model.deleteArchivedThreads()
                }
            }
        }
    }
}

/// The archived threads. The empty archive never reaches this page: the pane shows its symbol instead.
private struct ArchiveSettingsPage: View {
    @Environment(AppModel.self) private var model

    /// The row waiting on its confirmation, or nil. One deletion is ever in flight, so one
    /// dialog on the card serves every row.
    @State private var pendingDeletion: ChatThread?

    var body: some View {
        let archived = model.archivedThreads
        ChromeCard(lazy: true) {
            ForEach(Array(archived.enumerated()), id: \.element.id) { index, thread in
                if index > 0 { ChromeRowDivider() }
                ChromeRow(title: thread.title, detail: model.project(thread.projectID)?.name) {
                    HStack(spacing: 8) {
                        Button("Restore") { model.unarchive(thread.id) }
                            .buttonStyle(.glass)
                        // The same check the sidebar and Delete all honour: a row here
                        // used to delete a history on the first click.
                        Button("Delete", role: .destructive) {
                            if model.settings.confirmBeforeDeleting {
                                pendingDeletion = thread
                            } else {
                                model.delete(thread.id)
                            }
                        }
                        .buttonStyle(.glass)
                    }
                    .controlSize(.small)
                }
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Delete \"\($0.title)\"?" } ?? "Delete the archived thread?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { thread in
            Button("Delete thread", role: .destructive) {
                model.delete(thread.id)
                pendingDeletion = nil
            }
        } message: { _ in
            Text("Its history will be removed. Files in your project stay as they are.")
        }
    }
}

private struct AboutSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Chrome.sectionSpacing) {
            AboutSoftwareUpdateSection()
            appCard
            ChromeSection(title: "Credits") {
                ChromeCard {
                    MadeByRow()
                    ChromeRowDivider()
                    ChromeRow(title: "Website", detail: "ensembyte.vercel.app") {
                        CreditLink(title: "Open website", url: URL(string: "https://ensembyte.vercel.app")!)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "GitHub Profile", detail: "Soumya Chakraborty on GitHub (@soumyachk101)") {
                        CreditLink(title: "@soumyachk101", url: URL(string: "https://github.com/soumyachk101")!)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Source code", detail: "Ensembyte repository on GitHub.") {
                        CreditLink(title: "soumyachk101/Ensembyte", url: URL(string: "https://github.com/soumyachk101/Ensembyte")!)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Releases", detail: "Latest release builds and changelog.") {
                        CreditLink(title: "Releases", url: URL(string: "https://github.com/soumyachk101/Ensembyte/releases")!)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Working indicators", detail: "Ported from Zeron by Wing, MIT License.") {
                        CreditLink(title: "zeronsh/zeron", url: URL(string: "https://github.com/zeronsh/zeron")!)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Terminal", detail: "SwiftTerm by Miguel de Icaza, MIT License.") {
                        CreditLink(title: "SwiftTerm", url: URL(string: "https://github.com/migueldeicaza/SwiftTerm")!)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Welcome tour", detail: "Ported from TourKit by Ram Patra, MIT License.") {
                        CreditLink(title: "rampatra/TourKit", url: URL(string: "https://github.com/rampatra/TourKit")!)
                    }
                    ChromeRowDivider()
                    LicensesRow()
                }
            }
        }
    }

    private var appCard: some View {
        ChromeCard {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ensembyte")
                        .font(.system(.title3, weight: .semibold))
                    Text(verbatim: "Version \(AppInfo.version) (\(AppInfo.build))")
                        .font(.system(.callout))
                        .foregroundStyle(Chrome.secondaryText)
                }
                Spacer()
            }
            .padding(16)
            ChromeRowDivider()
            ChromeRow(title: "Welcome tour", detail: "The slideshow from the first launch: Hydra, the effort slider, panels and themes.") {
                Button("Show") { Tour.present(model: model) }.buttonStyle(.glass).controlSize(.small)
            }
            ChromeRowDivider()
            AboutUpdateCheckRow()
            ChromeRowDivider()
            Text("The coding app by Soumya Chakraborty: a native home for your coding agents, built in Swift with Liquid Glass.")
                .font(.system(.body))
                .padding(.leading, 16)
                .padding(.trailing, Chrome.rowControlTrailingPadding)
                .padding(.vertical, 11)
            ChromeRowDivider()
            Text("Ensembyte and SwiftTerm are MIT licensed.")
                .font(.system(.callout))
                .foregroundStyle(Chrome.secondaryText)
                .padding(.leading, 16)
                .padding(.trailing, Chrome.rowControlTrailingPadding)
                .padding(.vertical, 11)
        }
    }
}

/// The license, the third-party notices and the trademark policy, as shipped in the bundle,
/// read in a popover: every copy of the app carries the notices for what it builds on.
private struct LicensesRow: View {
    @State private var isPresented = false

    private static let files: [(title: String, resource: String)] = [
        ("Ensembyte", "LICENSE"),
        ("Third-party notices", "THIRD_PARTY_NOTICES"),
        ("Trademarks", "TRADEMARK"),
    ]

    var body: some View {
        ChromeRow(title: "Licenses", detail: "MIT, with the notices for what the app builds on.") {
            Button("Show") { isPresented = true }
                .buttonStyle(.glass)
                .controlSize(.small)
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Self.files, id: \.resource) { file in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(verbatim: file.title)
                                        .font(.system(.body, weight: .semibold))
                                    MarkdownView(text: Self.text(of: file.resource)).equatable()
                                        .environment(\.markdownPointSize, 12)
                                        .foregroundStyle(Chrome.secondaryText)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 480, height: 440)
                    .presentedChrome()
                }
        }
    }

    /// Read from the bundle once: the popover's body runs on every hover and scroll, and
    /// the markdown it now renders is parsed from this text each time as it is.
    private static let texts: [String: String] = Dictionary(uniqueKeysWithValues: files.map { file in
        let url = Bundle.main.url(forResource: file.resource, withExtension: file.resource == "LICENSE" ? nil : "md")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "The \(file.resource) file is missing from this copy of the app."
        return (file.resource, text)
    })

    private static func text(of resource: String) -> String {
        texts[resource] ?? "The \(resource) file is missing from this copy of the app."
    }
}

private struct MadeByRow: View {
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image("ensembyte-logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Made by Soumya Chakraborty")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                Text("Ensembyte is a coding app by Soumya Chakraborty for Mac.")
                    .font(.system(.subheadline))
                    .foregroundStyle(Chrome.secondaryText)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                CreditLink(title: "Website", url: URL(string: "https://ensembyte.vercel.app")!)
                CreditLink(title: "GitHub", url: URL(string: "https://github.com/soumyachk101")!)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, Chrome.rowControlTrailingPadding + 4)
        .padding(.vertical, 12)
        .accessibilityLabel(Text("Made by Soumya Chakraborty."))
    }
}

private struct CreditLink: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                Image(systemName: "arrow.up.right")
                    .font(.system(.footnote, weight: .semibold))
            }
            .font(.system(.callout, weight: .medium))
            .foregroundStyle(Chrome.accent)
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }
}


/// The per-project marks behind one button: the Projects card stays two rows long, and the
/// list of projects with their marks opens in a popover off this row.
private struct ProjectMarksRow: View {
    @Environment(AppModel.self) private var model

    @State private var isPresented = false

    var body: some View {
        Button("Edit") { isPresented = true }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(model.projects.isEmpty)
            .help("Choose a mark for each project")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.projects.enumerated()), id: \.element.id) { index, project in
                        if index > 0 { ChromeRowDivider() }
                        ChromeRow(title: project.name, detail: project.path) {
                            ProjectIconButton(icon: icon(for: project.id))
                        }
                    }
                }
                .frame(width: 400)
            }
    }

    private func icon(for id: UUID) -> Binding<ProjectIcon?> {
        Binding(
            get: { model.project(id)?.icon },
            set: { newIcon in model.updateProject(id) { $0.icon = newIcon } }
        )
    }
}

/// The theme menu: System on top, then the dark and the light themes in their
/// own sections, each with a swatch of its surface and accent.
private struct ThemePickerButton: View {
    @Binding var selection: AppTheme

    @State private var isPresented = false
    @State private var isHovering = false

    private static let dark = AppTheme.allCases.filter { $0.scheme == .dark }
    private static let light = AppTheme.allCases.filter { $0.scheme == .light }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                selection.swatch
                    .frame(width: 14, height: 14)
                Text(verbatim: selection.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Chrome.secondaryText)
            }
            .foregroundStyle(Chrome.primaryText.opacity(isHovering || isPresented ? 1 : 0.92))
            .padding(.horizontal, Chrome.capsuleHorizontalPadding)
            .frame(height: Chrome.capsuleContentHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .chromeGlassCapsule()
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PopoverMenu {
                item(.system)
                PopoverSectionHeader("Dark")
                ForEach(Self.dark) { item($0) }
                PopoverSectionHeader("Light")
                ForEach(Self.light) { item($0) }
            }
        }
    }

    private func item(_ theme: AppTheme) -> some View {
        PopoverItem(theme.displayName, leading: AnyView(theme.swatch), isChecked: theme == selection) {
            selection = theme
        }
    }
}
