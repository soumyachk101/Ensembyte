import AppKit
import Foundation
import Observation

/// The commands the browser chrome can be asked for: the shortcuts', the menus', and the
/// panel's own controls all post these.
enum BrowserCommand: String, Sendable {
    case focusAddress
    case newTab
    case closeTab
    case back
    case forward
    case reload
}

/// One browser tab: the page host behind it and the address bar's state.
@MainActor
@Observable
final class BrowserPageModel: Identifiable {
    let id = UUID()
    var state = BrowserPageState()
    var addressText = ""
    /// The last refused address, in the words the policy shows.
    var validationMessage: String?
    /// Counts the focus requests, so a second request on an already-focused field
    /// still reaches the field: the panel watches this and focuses it on each new one.
    var addressFocusCount = 0

    /// The tab's host: the WKWebView and its navigation delegate.
    @ObservationIgnored let page: BrowserPage

    /// The address field's keyboard: it takes the focus and the selection when the
    /// tab is asked to focus it.
    @ObservationIgnored let addressField = BrowserAddressController()

    init() {
        let host = BrowserPage()
        page = host
        host.stateHandler = { [weak self] newState in
            self?.state = newState
        }
    }

    /// The page's URL as it stands, settled into the form the policy writes.
    var currentURL: URL? {
        state.url.flatMap(URL.init(string:))
    }

    /// The command bar's submit: normalizes what's in the field and either sets the
    /// row's error or loads the settled address.
    func submitAddress() {
        switch BrowserURLPolicy.normalizeAddress(addressText) {
        case let .failure(error):
            validationMessage = error.message
        case let .success(normalized):
            validationMessage = nil
            addressText = normalized
            if let url = URL(string: normalized) {
                load(url)
            }
        }
    }

    func load(_ url: URL) {
        validationMessage = nil
        addressText = url.absoluteString
        page.load(url)
    }

    func reload() {
        page.reload()
    }

    func goBack() {
        page.goBack()
    }

    func goForward() {
        page.goForward()
    }

    /// Opens the current page in the system's default browser.
    func openInDefaultBrowser() {
        guard let url = currentURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Takes the address field's focus, with its text selected.
    func focusAddress() {
        addressFocusCount += 1
        addressField.focus()
    }
}

/// The app's browser: the open tabs per thread, which one is front in each, and the
/// commands that move them.
@MainActor
@Observable
final class BrowserStore {
    /// The open tabs per thread, in order.
    var pageIDs: [UUID: [UUID]] = [:]
    /// The front tab per thread: nil where the thread has no tabs.
    var activePageID: [UUID: UUID?] = [:]
    /// The pages across every thread: a web view outlives its view, so a page is only
    /// dropped when its thread's tab closes.
    var pages: [UUID: BrowserPageModel] = [:]

    /// Opens a tab at `url` in `thread` (blank when nil) and brings it to the front. A
    /// request that lands on a thread already showing a tab loads into that tab instead
    /// of piling up: the front page keeps the front.
    @discardableResult
    func openPage(url: URL?, in thread: UUID) -> BrowserPageModel {
        if let url, let active = activePage(in: thread) {
            active.load(url)
            return active
        }
        let model = BrowserPageModel()
        pages[model.id] = model
        pageIDs[thread, default: []].append(model.id)
        activePageID[thread] = model.id
        if let url { model.load(url) }
        return model
    }

    func closePage(_ id: UUID, in thread: UUID) {
        let ids = pageIDs[thread] ?? []
        guard let index = ids.firstIndex(where: { $0 == id }) else { return }
        pages[id]?.page.stop()
        pages[id] = nil
        var remaining = ids
        remaining.remove(at: index)
        if remaining.isEmpty {
            pageIDs[thread] = nil
            activePageID[thread] = nil
        } else {
            pageIDs[thread] = remaining
            if activePageID[thread] == id {
                activePageID[thread] = index < remaining.count ? remaining[index] : remaining.last
            }
        }
    }

    func selectPage(_ id: UUID, in thread: UUID) {
        guard pages[id] != nil, (pageIDs[thread] ?? []).contains(id) else { return }
        activePageID[thread] = id
    }

    func activePage(in thread: UUID) -> BrowserPageModel? {
        (activePageID[thread] ?? nil).flatMap { pages[$0] }
    }

    func pages(in thread: UUID) -> [BrowserPageModel] {
        (pageIDs[thread] ?? []).compactMap { pages[$0] }
    }

    /// Closes every tab of `thread`, stopping their web views and dropping the models.
    func resetThread(_ thread: UUID) {
        for id in pageIDs[thread] ?? [] {
            pages[id]?.page.stop()
            pages[id] = nil
        }
        pageIDs[thread] = nil
        activePageID[thread] = nil
    }

    /// Does a command against the thread's front tab; a new tab starts when it has none.
    func perform(_ command: BrowserCommand, in thread: UUID) {
        switch command {
        case .newTab:
            openPage(url: nil, in: thread)
        case .focusAddress:
            activePage(in: thread)?.focusAddress()
        case .closeTab:
            if let page = activePage(in: thread) { closePage(page.id, in: thread) }
        case .back:
            activePage(in: thread)?.goBack()
        case .forward:
            activePage(in: thread)?.goForward()
        case .reload:
            activePage(in: thread)?.reload()
        }
    }
}
