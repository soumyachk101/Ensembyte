import AppKit
import SwiftUI

/// The browser as a full-bleed column beside the conversation: a slim header, the tab strip,
/// the back/forward/reload + address toolbar, and the page below. Sized by its own column,
/// not by a drag — the handle on its edge lives on the parent. Every page the app has open
/// lives in the one `BrowserStore` on the model, so it shows the same tabs as the panel.
struct BrowserSectionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.browser
        VStack(spacing: 0) {
            header
            tabStrip(store)
            toolbar(store)
            validationStrip(store)
            pageBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // An opaque base: the theme's surface carries the web content and the empty states
        // in both appearances, and it is always an alpha-1 color (see `AppTheme.spec`).
        .background { Chrome.glassTint }
        // A hairline on the section's leading edge, separating it from the chat column.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Chrome.overlay(0.1))
                .frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Browser"))
    }

    /// The header row: the globe and the title. The section is toggled from the chrome row
    /// elsewhere, so there is no close mark.
    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(Chrome.inlineIconFont)
                    .foregroundStyle(Chrome.primaryText.opacity(0.92))
                Text("Browser")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Chrome.primaryText.opacity(0.92))
            }
            Spacer()
        }
        .padding(.top, Chrome.chromeTopPadding)
        .padding(.horizontal, Chrome.chromeHorizontalPadding)
    }

    /// One row per open page, in the store's own order, with a `+` that opens an empty page.
    private func tabStrip(_ store: BrowserStore) -> some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.pageIDs, id: \.self) { id in
                        if let page = store.pages[id] {
                            BrowserTab(
                                page: page,
                                isActive: id == store.activePageID,
                                onSelect: { store.selectPage(id) },
                                onClose: { store.closePage(id) }
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
            ChromeIconButton(symbol: "plus", help: "New tab") {
                store.openPage(url: nil)
            }
        }
        .padding(.horizontal, Chrome.chromeHorizontalPadding)
        .padding(.bottom, 4)
    }

    /// Back and forward, reload, the address field, and "open in the default browser". The
    /// history and reload controls stand down when there is nothing to act on; the address
    /// field always has room, and a small "Go" surfaces while it differs from what loaded.
    private func toolbar(_ store: BrowserStore) -> some View {
        let page = store.activePage
        let hasURL = page?.state.url != nil
        return HStack(spacing: 6) {
            ChromeIconButton(symbol: "arrow.left", isEnabled: page?.state.canBack ?? false, help: "Go back") {
                page?.goBack()
            }
            ChromeIconButton(symbol: "arrow.right", isEnabled: page?.state.canForward ?? false, help: "Go forward") {
                page?.goForward()
            }
            ChromeIconButton(symbol: "arrow.clockwise", isEnabled: hasURL, help: "Reload page") {
                page?.reload()
            }
            addressField(page)
                .frame(maxWidth: .infinity)
            ChromeIconButton(symbol: "arrow.up.forward", isEnabled: hasURL, help: "Open in default browser") {
                model.browser.activePage?.openInDefaultBrowser()
            }
        }
        .padding(.horizontal, Chrome.chromeHorizontalPadding)
        .padding(.bottom, 6)
    }

    /// The address bar: a globe, the field bound to the page's own text, and a "Go" while the
    /// text differs from what is loaded. Return submits; Escape restores and clears focus.
    @ViewBuilder
    private func addressField(_ page: BrowserPageModel?) -> some View {
        let text = page?.addressText ?? ""
        let loaded = page?.state.url ?? ""
        let showGo = !text.isEmpty && text != loaded
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
                .accessibilityHidden(true)
            if let page {
                BrowserAddressField(
                    page: page,
                    placeholder: "Website or localhost:3000",
                    onSubmit: { page.submitAddress() },
                    onEscape: {
                        page.addressText = page.state.url ?? ""
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(verbatim: "Website or localhost:3000")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Chrome.secondaryText.opacity(0.6))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showGo {
                Button {
                    page?.submitAddress()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(Chrome.inlineIconFont)
                        .foregroundStyle(Chrome.primaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Go to address")
                .accessibilityLabel(Text("Go to address"))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background { Capsule(style: .continuous).fill(Chrome.overlay(0.06)) }
        .contentShape(Capsule(style: .continuous))
        .background { NoWindowDragArea() }
    }

    /// A bad address, under the toolbar, in the danger tone.
    @ViewBuilder
    private func validationStrip(_ store: BrowserStore) -> some View {
        if let message = store.activePage?.validationMessage {
            Text(verbatim: message)
                .font(.system(size: 11))
                .foregroundStyle(Chrome.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Chrome.chromeHorizontalPadding)
                .padding(.vertical, 6)
        }
    }

    /// The page: its web view when something loaded, the empty state when it has nothing to
    /// show yet, and the error state when the last load failed.
    @ViewBuilder
    private var pageBody: some View {
        let store = model.browser
        if let page = store.activePage {
            if let error = page.state.error {
                errorState(page: page, error: error)
            } else if page.state.url == nil {
                emptyState(page: page)
            } else {
                BrowserWebView(model: page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // No tabs at all: open an empty one, so the strip and the field have a home.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { model.browser.openPage(url: nil) }
        }
    }

    /// An empty page: a globe in a rounded box, the why, and the door to type an address.
    private func emptyState(page: BrowserPageModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 22))
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 44, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Chrome.overlay(0.05))
                }
            Text(verbatim: "Preview your work")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Chrome.primaryText)
            Text(verbatim: "Preview your local app or keep a website beside your conversation.")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button {
                page.focusAddress()
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: "Enter an address")
                        .font(.system(size: 12, weight: .medium))
                    Text(verbatim: "⌘L")
                        .font(.system(size: 10))
                        .foregroundStyle(Chrome.secondaryText)
                }
                .foregroundStyle(Chrome.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background { Capsule(style: .continuous).fill(Chrome.overlay(0.07)) }
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Enter an address")
            .accessibilityLabel(Text("Enter an address"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// A failed load, in place of the page: what went wrong and the retry.
    private func errorState(page: BrowserPageModel, error: String) -> some View {
        VStack(spacing: 12) {
            Text(verbatim: "Couldn't load this page")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Chrome.primaryText)
            Text(verbatim: error)
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button {
                page.reload()
            } label: {
                Text(verbatim: "Try again")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Chrome.primaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background { Capsule(style: .continuous).fill(Chrome.overlay(0.07)) }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Try again")
            .accessibilityLabel(Text("Try again"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// One tab in the strip: the page's title, a globe standing in for its favicon, a spinner
/// while it loads, and a close mark. Tapping the label selects the page. Duplicated from
/// `BrowserPanel` so this file stands on its own.
private struct BrowserTab: View {
    let page: BrowserPageModel
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        let label = page.state.label()
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                Text(verbatim: label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)
                if page.state.loading {
                    MiniSpinner()
                }
            }
            .contentShape(.rect)
            .onTapGesture { onSelect() }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Close tab")
            .accessibilityLabel(Text("Close tab"))
        }
        .foregroundStyle(isActive ? Chrome.primaryText : Chrome.secondaryText)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background {
            Capsule(style: .continuous)
                .fill(isActive ? Chrome.accent.opacity(0.14) : Chrome.overlay(0.05))
        }
        .contentShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isButton)
        .help("Select \(label)")
    }
}
