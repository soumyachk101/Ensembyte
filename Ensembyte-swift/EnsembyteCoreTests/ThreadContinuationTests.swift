import XCTest
@testable import Ensembyte

final class ThreadContinuationTests: XCTestCase {
    private let sourceID = UUID()

    private func user(_ text: String, hydra: Bool = false, attachment: Attachment? = nil) -> TimelineItem {
        var message = UserMessage(text: text)
        if hydra { message.hydraHeads = [0] }
        message.attachments = attachment.map { [$0] } ?? []
        return TimelineItem(turnID: nil, date: .distantPast, content: .user(message))
    }

    private func assistant(_ text: String) -> TimelineItem {
        TimelineItem(turnID: nil, date: .distantPast, content: .assistant(AssistantMessage(text: text)))
    }

    private func document(_ items: [TimelineItem], continuation: ThreadContinuation? = nil) -> ThreadDocument {
        var document = ThreadDocument(threadID: sourceID)
        document.items = items
        document.continuation = continuation
        return document
    }

    private func attachment(_ path: String) -> Attachment {
        Attachment(name: (path as NSString).lastPathComponent, path: path, mimeType: "text/markdown")
    }

    // MARK: - Basic capture

    func testPlainChatCapturesUserAndAssistant() {
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "Old chat",
                                                 document: document([user("Do the thing"), assistant("Done the thing")]))
        XCTAssertEqual(snapshot.sourceThreadID, sourceID)
        XCTAssertEqual(snapshot.sourceTitle, "Old chat")
        XCTAssertEqual(snapshot.context, "User: Do the thing\n\nAssistant: Done the thing")
        XCTAssertFalse(snapshot.isTruncated)
        XCTAssertTrue(snapshot.attachments.isEmpty)
    }

    func testHydraSpeechIsExcluded() {
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "chat",
            document: document([user("Plan it"), user("head 0: built it", hydra: true), assistant("Reported")]))
        XCTAssertEqual(snapshot.context, "User: Plan it\n\nAssistant: Reported")
    }

    func testBlankUserMessageIsDropped() {
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "chat",
            document: document([user("   \n "), user("real"), assistant("ok")]))
        // The blank user message contributes nothing; order is user first, assistant after.
        XCTAssertEqual(snapshot.context, "User: real\n\nAssistant: ok")
    }

    func testAttachmentRidesWithTheMessage() {
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "chat",
            document: document([user("look", attachment: attachment("/tmp/notes.md"))]))
        XCTAssertEqual(snapshot.context, "User: look\nAttachments: notes.md (/tmp/notes.md)")
        XCTAssertEqual(snapshot.attachments.map(\.path), ["/tmp/notes.md"])
    }

    // MARK: - Delegation blocks

    func testDelegationBlockStrippedFromAssistantText() {
        let reply = "Planned it.\n```hydra\n[{\"title\":\"build\",\"instructions\":\"do it\"}]\n```"
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "chat",
                                                   document: document([user("do it"), assistant(reply)]))
        XCTAssertEqual(snapshot.context, "User: do it\n\nAssistant: Planned it.")
    }

    func testAssistantWithOnlyDelegationBlockIsDropped() {
        let reply = "```hydra\n[]\n```"
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "chat",
                                                   document: document([user("do it"), assistant(reply), assistant("real text")]))
        XCTAssertEqual(snapshot.context, "User: do it\n\nAssistant: real text")
    }

    // MARK: - Re-capture

    func testForwardingWithOnlyHydraSpeechReusesPrevious() {
        // A thread whose only new content is Hydra's own speech re-forwards the previous
        // snapshot untouched: no double-wrapping, no re-truncation.
        let previous = ThreadContinuation(sourceThreadID: sourceID, sourceTitle: "Old",
                                          context: "User: hello", isTruncated: false)
        let document = document([user("head report", hydra: true)], continuation: previous)
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "Old", document: document)
        XCTAssertEqual(snapshot.context, previous.context)
        XCTAssertEqual(snapshot.isTruncated, previous.isTruncated)
    }

    func testForwardingWithNoNewContentReusesThePreviousSnapshot() {
        let previous = ThreadContinuation(sourceThreadID: sourceID, sourceTitle: "Old",
                                          context: "User: hello\n\nAssistant: hi", attachments: [attachment("/tmp/a.md")],
                                          isTruncated: false)
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "Old",
                                                  document: document([], continuation: previous))
        XCTAssertEqual(snapshot.context, previous.context)
        XCTAssertEqual(snapshot.attachments, previous.attachments)
        XCTAssertFalse(snapshot.isTruncated)
    }

    // MARK: - Budget

    func testFirstRequestIsKeptWhole() {
        let longFirst = String(repeating: "x", count: ThreadContinuation.firstRequestLimit - 500)
        let rest = String(repeating: "y", count: 500)
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "chat",
            document: document([user(longFirst), assistant(rest), user("tail")]))
        XCTAssertTrue(snapshot.context.contains("User: " + longFirst))
        XCTAssertTrue(snapshot.context.contains("User: tail"))
        XCTAssertFalse(snapshot.isTruncated, "the whole budget comfortably fits these messages")
    }

    func testOversizedFirstRequestIsStillKeptButMarkedTruncated() {
        let longFirst = String(repeating: "x", count: ThreadContinuation.firstRequestLimit * 4)
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "chat",
                                                  document: document([user(longFirst), assistant("later")]))
        XCTAssertTrue(snapshot.isTruncated)
        // The first request is never dropped, but its render is length-limited:
        // `[message shortened]` appears and the full block does not survive.
        XCTAssertTrue(snapshot.context.contains(String(repeating: "x", count: 200)))
        XCTAssertFalse(snapshot.context.contains(longFirst))
    }

    func testBudgetTruncationFromTheEnd() {
        var items: [TimelineItem] = [user(String(repeating: "1", count: 2_000)), assistant("work")]
        // Fill up to well past the budget with more turns.
        while !ThreadContinuation.capture(sourceID: sourceID, title: "chat", document: document(items)).isTruncated {
            items.append(user(String(repeating: "f", count: 3_000)))
            items.append(assistant("ok"))
        }
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "chat", document: document(items))
        XCTAssertTrue(snapshot.isTruncated, "a chat past the budget must be marked truncated")
        // The first request always survives.
        XCTAssertTrue(snapshot.context.hasPrefix("User: " + String(repeating: "1", count: 2_000)))
        XCTAssertTrue(snapshot.context.contains(ThreadContinuation.truncationMarker))
        // Never exceeds the budget.
        XCTAssertLessThanOrEqual(snapshot.context.count, ThreadContinuation.contextBudget)
    }

    func testPreviousContextIsInherited() {
        let previous = ThreadContinuation(sourceThreadID: sourceID, sourceTitle: "Old",
                                          context: "User: ancient\n\nAssistant: ancient answer", isTruncated: false)
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "Old",
            document: document([user("new")], continuation: previous))
        XCTAssertTrue(snapshot.context.contains("User: ancient\n\nAssistant: ancient answer"))
        XCTAssertTrue(snapshot.context.contains("User: new"))
        // Inherited text comes before the new capture.
        XCTAssertLessThan(snapshot.context.range(of: "ancient")!.lowerBound, snapshot.context.range(of: "User: new")!.lowerBound)
    }

    func testInheritedAttachmentsAreKeptOnce() {
        let attachment = attachment("/tmp/a.md")
        let previous = ThreadContinuation(sourceThreadID: sourceID, sourceTitle: "Old",
                                          context: "User: old", attachments: [attachment], isTruncated: false)
        let snapshot = ThreadContinuation.capture(sourceID: sourceID, title: "Old",
            document: document([user("new", attachment: attachment)], continuation: previous))
        XCTAssertEqual(snapshot.attachments.map(\.path), ["/tmp/a.md"], "the same path must not appear twice")
    }

    // MARK: - Prompt construction

    func testPromptWrapsContextWithMarkers() {
        let snapshot = ThreadContinuation(sourceThreadID: sourceID, sourceTitle: "My Chat",
                                          context: "User: hi", attachments: [attachment("/tmp/a.md")], isTruncated: true)
        let prompt = snapshot.prompt
        XCTAssertTrue(prompt.hasPrefix("The user forwarded their earlier chat \"My Chat\" into this new thread."))
        XCTAssertTrue(prompt.contains("----- BEGIN FORWARDED CONTEXT -----"))
        XCTAssertTrue(prompt.contains("----- END FORWARDED CONTEXT -----"))
        XCTAssertTrue(prompt.contains("\nUser: hi\n"))
        XCTAssertTrue(prompt.contains("Some messages were shortened or omitted"))
        XCTAssertTrue(prompt.contains("The forwarded chat referenced a file still kept in this app's storage"))
    }

    func testPromptIsQuietAboutTruncationWhenComplete() {
        let snapshot = ThreadContinuation(sourceThreadID: sourceID, sourceTitle: "My Chat",
                                          context: "User: hi", isTruncated: false)
        let prompt = snapshot.prompt
        XCTAssertFalse(prompt.contains("Some messages were shortened"))
        XCTAssertFalse(prompt.contains("referenced a file"))
    }

    func testPromptPluralFiles() {
        let snapshot = ThreadContinuation(sourceThreadID: sourceID, sourceTitle: "c", context: "x",
                                          attachments: [attachment("/a"), attachment("/b")], isTruncated: false)
        XCTAssertTrue(snapshot.prompt.contains("referenced files still kept"))
    }
}
