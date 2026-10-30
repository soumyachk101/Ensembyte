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

/// The app's browser: its open tabs, which one is front, and the commands that move them.
@MainActor
@Observable
final class BrowserStore {
    var pageIDs: [UUID] = []
    var activePageID: UUID?
    var pages: [UUID: BrowserPageModel] = [:]

    var activePage: BrowserPageModel? {
        activePageID.flatMap { pages[$0] }
    }

    /// Opens a tab at `url` (blank when nil) and brings it to the front.
    @discardableResult
    func openPage(url: URL?) -> BrowserPageModel {
        let model = BrowserPageModel()
        pages[model.id] = model
        pageIDs.append(model.id)
        activePageID = model.id
        if let url { model.load(url) }
        return model
    }

    func closePage(_ id: UUID) {
        guard let index = pageIDs.firstIndex(where: { $0 == id }) else { return }
        pages[id]?.page.stop()
        pages[id] = nil
        pageIDs.remove(at: index)
        if activePageID == id {
            activePageID = index < pageIDs.count ? pageIDs[index] : pageIDs.last
        }
    }

    func selectPage(_ id: UUID) {
        guard pages[id] != nil else { return }
        activePageID = id
    }

    /// Does a command against the front tab; a new tab starts when none is open.
    func perform(_ command: BrowserCommand) {
        switch command {
        case .newTab:
            openPage(url: nil)
        case .focusAddress:
            activePage?.focusAddress()
        case .closeTab:
            if let page = activePage { closePage(page.id) }
        case .back:
            activePage?.goBack()
        case .forward:
            activePage?.goForward()
        case .reload:
            activePage?.reload()
        }
    }
}
