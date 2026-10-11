import AppKit
import SwiftUI

/// What a thread shows over its box before its first message: the app icon and a question
/// about the project.
/// The project name opens a popover to move the empty thread to another project.
struct NewThreadPrompt: View {
    @Environment(AppModel.self) private var model
    let threadID: UUID
    let projectName: String?

    @State private var isChoosingProject = false
    @State private var isHoveringName = false

    var body: some View {
        // Stands over the new thread's box, which the chat column places (see
        // `ComposerDock`); in a short pane the icon gives way before the question does.
        ViewThatFits(in: .vertical) {
            VStack(spacing: 26) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                question
            }
            question
        }
        .padding(.horizontal, 40)
    }

    private var question: some View {
        HStack(spacing: 0) {
            if let projectName, !projectName.isEmpty {
                Text("What should we build in ")
                Button {
                    isChoosingProject.toggle()
                } label: {
                    Text(verbatim: projectName)
                        .underline(true, pattern: .dot, color: isHoveringName ? Chrome.primaryText : Chrome.secondaryText)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringName = $0 }
                .help("Choose another project")
                .popover(isPresented: $isChoosingProject, arrowEdge: .bottom) {
                    projectChoices
                }
                Text("?")
            } else {
                Text("What should we build?")
            }
        }
        .font(.system(size: 28, weight: .regular))
        .foregroundStyle(Chrome.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var projectChoices: some View {
        let current = model.thread(threadID)?.projectID
        return PopoverMenu {
            PopoverSectionHeader("Projects")
            ForEach(model.projects) { project in
                PopoverItem(project.name, leading: AnyView(ProjectIconMark(icon: project.icon, size: 12)), isChecked: project.id == current) {
                    move(to: project)
                }
            }
            PopoverDivider()
            PopoverItem("Add project…", symbol: "plus") {
                guard let added = model.addProjectsFromPanel() else { return }
                move(to: added)
            }
            PopoverItem("Clone from GitHub…", leading: AnyView(Image("mcp-github").resizable().scaledToFit().frame(width: 12, height: 12))) {
                isChoosingProject = false
                GitHubClonePanel.shared.present(model: model) { project in
                    move(to: project)
                }
            }
        }
    }

    private func move(to project: Project) {
        guard let thread = model.thread(threadID), thread.projectID != project.id else { return }
        isChoosingProject = false
        withAnimation(Chrome.panelSlide) {
            model.moveThread(threadID, toProject: project)
        }
    }
}
