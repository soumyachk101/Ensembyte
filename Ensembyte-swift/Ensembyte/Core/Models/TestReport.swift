//
//  TestReport.swift
//  Ensembyte
//
//  Interactive Test Results & AI Fix Runner data models and output parsers.
//

import Foundation

public enum TestStatus: String, Codable, Sendable {
    case passed
    case failed
    case skipped
    case running
}

public enum TestFramework: String, Codable, Sendable {
    case vitest
    case jest
    case cargo
    case pytest
    case swift
    case go
    case generic
}

public struct TestCase: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var status: TestStatus
    public var durationMs: Double?
    public var failureMessage: String?
    public var expected: String?
    public var received: String?
    public var location: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        status: TestStatus,
        durationMs: Double? = nil,
        failureMessage: String? = nil,
        expected: String? = nil,
        received: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.durationMs = durationMs
        self.failureMessage = failureMessage
        self.expected = expected
        self.received = received
        self.location = location
    }
}

public struct TestSuite: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var status: TestStatus
    public var durationSeconds: Double?
    public var cases: [TestCase]

    public var passedCount: Int { cases.filter { $0.status == .passed }.count }
    public var failedCount: Int { cases.filter { $0.status == .failed }.count }
    public var skippedCount: Int { cases.filter { $0.status == .skipped }.count }
    public var totalCount: Int { cases.count }

    public init(
        id: String = UUID().uuidString,
        name: String,
        status: TestStatus = .passed,
        durationSeconds: Double? = nil,
        cases: [TestCase] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.durationSeconds = durationSeconds
        self.cases = cases
    }
}

public struct TestReport: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var command: String
    public var framework: TestFramework
    public var suites: [TestSuite]
    public var passedCount: Int
    public var failedCount: Int
    public var skippedCount: Int
    public var totalCount: Int
    public var durationSeconds: Double?
    public var summaryText: String

    public var hasFailures: Bool { failedCount > 0 }
    public var isSuccess: Bool { failedCount == 0 && totalCount > 0 }

    public var failureSummary: String {
        var lines: [String] = []
        for suite in suites where suite.failedCount > 0 {
            lines.append("Suite: \(suite.name)")
            for c in suite.cases where c.status == .failed {
                var item = "  - \(c.name)"
                if let msg = c.failureMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
                    let firstLine = msg.components(separatedBy: .newlines).first ?? msg
                    item += ": \(firstLine)"
                }
                lines.append(item)
            }
        }
        return lines.joined(separator: "\n")
    }

    public init(
        id: UUID = UUID(),
        command: String,
        framework: TestFramework = .generic,
        suites: [TestSuite] = [],
        passedCount: Int = 0,
        failedCount: Int = 0,
        skippedCount: Int = 0,
        durationSeconds: Double? = nil,
        summaryText: String = ""
    ) {
        self.id = id
        self.command = command
        self.framework = framework
        self.suites = suites
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.totalCount = passedCount + failedCount + skippedCount
        self.durationSeconds = durationSeconds
        self.summaryText = summaryText
    }
}

// MARK: - Test Output Parser

public enum TestOutputParser {
    private static let testCommands = [
        "cargo test", "cargo nextest",
        "npm test", "npm run test", "pnpm test", "yarn test", "bun test",
        "vitest", "jest", "pytest", "python -m unittest",
        "swift test", "xcodebuild test",
        "go test", "ctest", "playwright test"
    ]

    private static let testSignatures = [
        "test result:", "Test Suites:", "=== RUN", "=== FAIL",
        "PASSED [", "FAILED [", "tests passed", "failures:"
    ]

    public static func isTestCommand(_ command: String) -> Bool {
        let trimmed = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return testCommands.contains { trimmed.contains($0) }
    }

    public static func containsTestOutput(_ output: String) -> Bool {
        return testSignatures.contains { output.contains($0) }
    }

    public static func parse(command: String, output: String) -> TestReport? {
        let lowerCmd = command.lowercased()
        if lowerCmd.contains("cargo") || output.contains("test result:") {
            if let report = parseCargo(command: command, output: output) { return report }
        }
        if lowerCmd.contains("vitest") || lowerCmd.contains("jest") || lowerCmd.contains("npm") || lowerCmd.contains("bun") || lowerCmd.contains("pnpm") || lowerCmd.contains("yarn") || output.contains("Test Suites:") {
            if let report = parseVitestOrJest(command: command, output: output) { return report }
        }
        if lowerCmd.contains("pytest") || output.contains("PASSED [") || output.contains("FAILED [") {
            if let report = parsePytest(command: command, output: output) { return report }
        }
        if lowerCmd.contains("swift test") || lowerCmd.contains("xcodebuild") || output.contains("Test Case '-") {
            if let report = parseSwiftTest(command: command, output: output) { return report }
        }
        if lowerCmd.contains("go test") || output.contains("=== RUN") {
            if let report = parseGoTest(command: command, output: output) { return report }
        }
        return parseGeneric(command: command, output: output)
    }

    // MARK: - Cargo Test Parser
    private static func parseCargo(command: String, output: String) -> TestReport? {
        var cases: [TestCase] = []
        let lines = output.components(separatedBy: .newlines)
        var passed = 0
        var failed = 0
        var skipped = 0
        var duration: Double? = nil

        var collectingFailures = false
        var currentFailedName: String? = nil
        var currentFailureLines: [String] = []
        var failureDetails: [String: String] = [:]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("test ") && (trimmed.hasSuffix(" ... ok") || trimmed.hasSuffix(" ... FAILED") || trimmed.hasSuffix(" ... ignored")) {
                let parts = trimmed.components(separatedBy: " ... ")
                if parts.count >= 2 {
                    let name = parts[0].replacingOccurrences(of: "test ", with: "")
                    let statusStr = parts[1]
                    let status: TestStatus
                    if statusStr.contains("ok") {
                        status = .passed
                        passed += 1
                    } else if statusStr.contains("FAILED") {
                        status = .failed
                        failed += 1
                    } else {
                        status = .skipped
                        skipped += 1
                    }
                    cases.append(TestCase(id: name, name: name, status: status))
                }
            } else if trimmed == "failures:" {
                collectingFailures = true
            } else if collectingFailures && trimmed.hasPrefix("---- ") && trimmed.hasSuffix(" ----") {
                if let prevName = currentFailedName {
                    failureDetails[prevName] = currentFailureLines.joined(separator: "\n")
                }
                currentFailedName = trimmed.replacingOccurrences(of: "---- ", with: "").replacingOccurrences(of: " ----", with: "")
                currentFailureLines = []
            } else if collectingFailures && trimmed.hasPrefix("test result:") {
                if let prevName = currentFailedName {
                    failureDetails[prevName] = currentFailureLines.joined(separator: "\n")
                }
                collectingFailures = false
                // Parse duration: finished in 0.05s
                if let range = trimmed.range(of: "finished in ") {
                    let rest = trimmed[range.upperBound...]
                    let secs = rest.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)
                    duration = Double(secs)
                }
            } else if collectingFailures && currentFailedName != nil {
                currentFailureLines.append(line)
            }
        }

        // Attach failure messages
        cases = cases.map { c in
            var updated = c
            if c.status == .failed, let detail = failureDetails[c.name] {
                updated.failureMessage = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return updated
        }

        guard !cases.isEmpty || output.contains("test result:") else { return nil }

        let suite = TestSuite(name: "Cargo Test Suite", status: failed > 0 ? .failed : .passed, cases: cases)
        let summary = failed > 0 ? "\(failed) failed, \(passed) passed" : "\(passed) passed"
        return TestReport(
            command: command,
            framework: .cargo,
            suites: [suite],
            passedCount: passed,
            failedCount: failed,
            skippedCount: skipped,
            durationSeconds: duration,
            summaryText: summary
        )
    }

    // MARK: - Vitest & Jest Parser
    private static func parseVitestOrJest(command: String, output: String) -> TestReport? {
        var suites: [TestSuite] = []
        var currentSuite: TestSuite? = nil
        var currentSuiteCases: [TestCase] = []

        let lines = output.components(separatedBy: .newlines)
        var passed = 0
        var failed = 0
        var skipped = 0
        var duration: Double? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("PASS ") || trimmed.hasPrefix("FAIL ") {
                if var s = currentSuite {
                    s.cases = currentSuiteCases
                    suites.append(s)
                    currentSuiteCases = []
                }
                let isPass = trimmed.hasPrefix("PASS ")
                let suiteName = trimmed.replacingOccurrences(of: "PASS ", with: "").replacingOccurrences(of: "FAIL ", with: "").trimmingCharacters(in: .whitespaces)
                currentSuite = TestSuite(name: suiteName, status: isPass ? .passed : .failed)
            } else if trimmed.contains("✓ ") || trimmed.contains("✕ ") || trimmed.contains("↓ ") || trimmed.contains("○ ") {
                let status: TestStatus
                if trimmed.contains("✓ ") {
                    status = .passed
                    passed += 1
                } else if trimmed.contains("✕ ") {
                    status = .failed
                    failed += 1
                } else {
                    status = .skipped
                    skipped += 1
                }
                var cleanName = trimmed
                for glyph in ["✓ ", "✕ ", "↓ ", "○ "] {
                    cleanName = cleanName.replacingOccurrences(of: glyph, with: "")
                }
                currentSuiteCases.append(TestCase(name: cleanName.trimmingCharacters(in: .whitespaces), status: status))
            } else if trimmed.hasPrefix("Time:") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2, let secs = Double(parts[1].replacingOccurrences(of: "s", with: "")) {
                    duration = secs
                }
            }
        }

        if var s = currentSuite {
            s.cases = currentSuiteCases
            suites.append(s)
        }

        guard !suites.isEmpty || output.contains("Test Suites:") else { return nil }

        let summary = failed > 0 ? "\(failed) failed, \(passed) passed" : "\(passed) passed"
        return TestReport(
            command: command,
            framework: .vitest,
            suites: suites,
            passedCount: passed,
            failedCount: failed,
            skippedCount: skipped,
            durationSeconds: duration,
            summaryText: summary
        )
    }

    // MARK: - Pytest Parser
    private static func parsePytest(command: String, output: String) -> TestReport? {
        var cases: [TestCase] = []
        let lines = output.components(separatedBy: .newlines)
        var passed = 0
        var failed = 0
        var skipped = 0
        var duration: Double? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(" PASSED") || trimmed.contains(" FAILED") || trimmed.contains(" SKIPPED") {
                let status: TestStatus
                if trimmed.contains(" PASSED") {
                    status = .passed
                    passed += 1
                } else if trimmed.contains(" FAILED") {
                    status = .failed
                    failed += 1
                } else {
                    status = .skipped
                    skipped += 1
                }
                let name = trimmed.components(separatedBy: .whitespaces).first ?? trimmed
                cases.append(TestCase(name: name, status: status))
            } else if trimmed.contains(" in ") && trimmed.hasSuffix("s ====") {
                let parts = trimmed.components(separatedBy: " in ")
                if parts.count == 2 {
                    let secPart = parts[1].replacingOccurrences(of: "s ====", with: "").trimmingCharacters(in: .whitespaces)
                    duration = Double(secPart)
                }
            }
        }

        guard !cases.isEmpty || output.contains("pytest") else { return nil }
        let suite = TestSuite(name: "Pytest Suite", status: failed > 0 ? .failed : .passed, cases: cases)
        let summary = failed > 0 ? "\(failed) failed, \(passed) passed" : "\(passed) passed"
        return TestReport(
            command: command,
            framework: .pytest,
            suites: [suite],
            passedCount: passed,
            failedCount: failed,
            skippedCount: skipped,
            durationSeconds: duration,
            summaryText: summary
        )
    }

    // MARK: - Swift Test Parser
    private static func parseSwiftTest(command: String, output: String) -> TestReport? {
        var cases: [TestCase] = []
        let lines = output.components(separatedBy: .newlines)
        var passed = 0
        var failed = 0
        var duration: Double? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Test Case '") && (trimmed.contains("passed") || trimmed.contains("failed")) {
                let isPass = trimmed.contains("passed")
                let status: TestStatus = isPass ? .passed : .failed
                if isPass { passed += 1 } else { failed += 1 }

                let parts = trimmed.components(separatedBy: "' ")
                let name = parts.first?.replacingOccurrences(of: "Test Case '", with: "") ?? trimmed
                cases.append(TestCase(name: name, status: status))
            } else if trimmed.hasPrefix("Executed ") && trimmed.contains("seconds") {
                if let inRange = trimmed.range(of: " in ") {
                    let rest = trimmed[inRange.upperBound...]
                    let secs = rest.components(separatedBy: .whitespaces).first ?? ""
                    duration = Double(secs)
                }
            }
        }

        guard !cases.isEmpty else { return nil }
        let suite = TestSuite(name: "Swift Test Suite", status: failed > 0 ? .failed : .passed, cases: cases)
        let summary = failed > 0 ? "\(failed) failed, \(passed) passed" : "\(passed) passed"
        return TestReport(
            command: command,
            framework: .swift,
            suites: [suite],
            passedCount: passed,
            failedCount: failed,
            skippedCount: 0,
            durationSeconds: duration,
            summaryText: summary
        )
    }

    // MARK: - Go Test Parser
    private static func parseGoTest(command: String, output: String) -> TestReport? {
        var cases: [TestCase] = []
        let lines = output.components(separatedBy: .newlines)
        var passed = 0
        var failed = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("--- PASS:") || trimmed.hasPrefix("--- FAIL:") {
                let isPass = trimmed.hasPrefix("--- PASS:")
                let status: TestStatus = isPass ? .passed : .failed
                if isPass { passed += 1 } else { failed += 1 }
                let parts = trimmed.components(separatedBy: .whitespaces)
                let name = parts.count >= 3 ? parts[2] : trimmed
                cases.append(TestCase(name: name, status: status))
            }
        }

        guard !cases.isEmpty else { return nil }
        let suite = TestSuite(name: "Go Tests", status: failed > 0 ? .failed : .passed, cases: cases)
        let summary = failed > 0 ? "\(failed) failed, \(passed) passed" : "\(passed) passed"
        return TestReport(
            command: command,
            framework: .go,
            suites: [suite],
            passedCount: passed,
            failedCount: failed,
            skippedCount: 0,
            durationSeconds: nil,
            summaryText: summary
        )
    }

    // MARK: - Generic Parser
    private static func parseGeneric(command: String, output: String) -> TestReport? {
        guard containsTestOutput(output) || isTestCommand(command) else { return nil }
        return TestReport(
            command: command,
            framework: .generic,
            suites: [],
            passedCount: 0,
            failedCount: 0,
            skippedCount: 0,
            durationSeconds: nil,
            summaryText: "Completed test execution"
        )
    }
}
