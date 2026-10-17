//
//  TestResultsView.swift
//  Ensembyte
//
//  Interactive Test Results & AI Fix Runner view component.
//

import SwiftUI
import AppKit

public struct TestResultsView: View {
    public let report: TestReport
    public let rawOutput: String
    public var onAskToFix: ((String) -> Void)? = nil

    @State private var filter: TestFilter = .all
    @State private var searchQuery: String = ""
    @State private var showsRawLog: Bool = false
    @State private var expandedSuites: Set<String> = []
    @State private var expandedFailures: Set<String> = []

    public enum TestFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case failed = "Failed"
        case passed = "Passed"
        case skipped = "Skipped"

        public var id: String { rawValue }
    }

    public init(
        report: TestReport,
        rawOutput: String,
        onAskToFix: ((String) -> Void)? = nil
    ) {
        self.report = report
        self.rawOutput = rawOutput
        self.onAskToFix = onAskToFix
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            if !showsRawLog {
                progressBar
                filterControls
                suitesList
                if report.hasFailures {
                    failureActionsFooter
                }
            } else {
                rawLogView
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Chrome.overlay(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            // Expand all failing suites by default
            for suite in report.suites where suite.failedCount > 0 {
                expandedSuites.insert(suite.id)
            }
            if expandedSuites.isEmpty, let first = report.suites.first {
                expandedSuites.insert(first.id)
            }
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 10) {
            // Framework Badge & Status
            HStack(spacing: 6) {
                Image(systemName: report.hasFailures ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(report.hasFailures ? Chrome.danger : Chrome.success)

                Text(report.framework.rawValue.capitalized + " Tests")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
            }

            // Duration Pill
            if let duration = report.durationSeconds {
                Text(String(format: "%.2fs", duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Chrome.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
            }

            Spacer()

            // View Mode Toggle (Results vs Raw Log)
            Button {
                showsRawLog.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showsRawLog ? "chart.bar.doc.horizontal" : "terminal")
                        .font(.system(size: 10))
                    Text(showsRawLog ? "Results View" : "Raw Log")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Chrome.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        GeometryReader { proxy in
            let total = max(1, report.totalCount)
            let passedW = (CGFloat(report.passedCount) / CGFloat(total)) * proxy.size.width
            let failedW = (CGFloat(report.failedCount) / CGFloat(total)) * proxy.size.width
            let skippedW = (CGFloat(report.skippedCount) / CGFloat(total)) * proxy.size.width

            HStack(spacing: 2) {
                if report.passedCount > 0 {
                    Rectangle()
                        .fill(Chrome.success)
                        .frame(width: max(3, passedW))
                }
                if report.failedCount > 0 {
                    Rectangle()
                        .fill(Chrome.danger)
                        .frame(width: max(3, failedW))
                }
                if report.skippedCount > 0 {
                    Rectangle()
                        .fill(Chrome.warning)
                        .frame(width: max(3, skippedW))
                }
            }
            .frame(height: 6)
            .clipShape(Capsule(style: .continuous))
        }
        .frame(height: 6)
    }

    // MARK: - Filter Controls
    private var filterControls: some View {
        HStack(spacing: 8) {
            // Filter Pills
            HStack(spacing: 4) {
                filterPill(.all, count: report.totalCount)
                if report.failedCount > 0 {
                    filterPill(.failed, count: report.failedCount, color: Chrome.danger)
                }
                if report.passedCount > 0 {
                    filterPill(.passed, count: report.passedCount, color: Chrome.success)
                }
                if report.skippedCount > 0 {
                    filterPill(.skipped, count: report.skippedCount, color: Chrome.secondaryText)
                }
            }

            Spacer()

            // Search Bar
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Chrome.secondaryText)
                TextField("Filter tests…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 90)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Chrome.overlay(0.08), lineWidth: 1)
            )
        }
    }

    private func filterPill(_ target: TestFilter, count: Int, color: Color? = nil) -> some View {
        let isSelected = filter == target
        return Button {
            filter = target
        } label: {
            HStack(spacing: 4) {
                Text(target.rawValue)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color ?? (isSelected ? .white : Chrome.secondaryText))
            }
            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .white : Chrome.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isSelected ? Chrome.accent : Color.primary.opacity(0.04),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Suites List
    private var suitesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(filteredSuites) { suite in
                suiteCard(suite)
            }
        }
    }

    private var filteredSuites: [TestSuite] {
        report.suites.compactMap { suite in
            let filteredCases = suite.cases.filter { c in
                let matchesFilter: Bool
                switch filter {
                case .all: matchesFilter = true
                case .failed: matchesFilter = c.status == .failed
                case .passed: matchesFilter = c.status == .passed
                case .skipped: matchesFilter = c.status == .skipped
                }
                let matchesSearch = searchQuery.isEmpty || c.name.localizedCaseInsensitiveContains(searchQuery)
                return matchesFilter && matchesSearch
            }
            if filteredCases.isEmpty && !searchQuery.isEmpty { return nil }
            var s = suite
            s.cases = filteredCases
            return s
        }
    }

    private func suiteCard(_ suite: TestSuite) -> some View {
        let isExpanded = expandedSuites.contains(suite.id)
        return VStack(alignment: .leading, spacing: 0) {
            // Suite Header
            Button {
                if isExpanded {
                    expandedSuites.remove(suite.id)
                } else {
                    expandedSuites.insert(suite.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Chrome.secondaryText)
                        .frame(width: 12)

                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.accent)

                    Text(suite.name)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Chrome.primaryText)
                        .lineLimit(1)

                    Spacer()

                    if suite.failedCount > 0 {
                        Text("\(suite.failedCount) failed")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Chrome.danger)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Chrome.danger.opacity(0.12), in: Capsule(style: .continuous))
                    }
                    if suite.passedCount > 0 {
                        Text("\(suite.passedCount) passed")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Chrome.success)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.025))
            }
            .buttonStyle(.plain)

            // Test Cases
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(suite.cases) { c in
                        testCaseRow(suite: suite, testCase: c)
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.015))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Chrome.overlay(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Test Case Row
    private func testCaseRow(suite: TestSuite, testCase: TestCase) -> some View {
        let isFailed = testCase.status == .failed
        let isExpandedFailure = expandedFailures.contains(testCase.id)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Status Icon
                Group {
                    switch testCase.status {
                    case .passed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Chrome.success)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Chrome.danger)
                    case .skipped:
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Chrome.secondaryText)
                    case .running:
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .font(.system(size: 11))
                .frame(width: 14)

                Text(testCase.name)
                    .font(.system(size: 11.5, weight: isFailed ? .semibold : .regular))
                    .foregroundStyle(isFailed ? Chrome.danger : Chrome.primaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)

                Spacer()

                if let duration = testCase.durationMs {
                    Text(String(format: "%.1fms", duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Chrome.secondaryText)
                }

                // If failed: Toggle failure details or Ask Agent to Fix
                if isFailed {
                    Button {
                        if isExpandedFailure {
                            expandedFailures.remove(testCase.id)
                        } else {
                            expandedFailures.insert(testCase.id)
                        }
                    } label: {
                        Text(isExpandedFailure ? "Hide Error" : "Details")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Chrome.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        askToFix(suite: suite, testCase: testCase)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                            Text("Ask to fix")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Chrome.accent, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Failure Details Drawer
            if isFailed && (isExpandedFailure || testCase.failureMessage != nil) {
                if let msg = testCase.failureMessage, !msg.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Failure Details")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Chrome.danger)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(msg, forType: .string)
                            }
                            .font(.system(size: 9.5))
                            .buttonStyle(.link)
                        }
                        Text(msg)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Chrome.primaryText)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
        }
        .background(isFailed ? Chrome.danger.opacity(0.04) : Color.clear)
        .overlay(
            Divider().opacity(0.4),
            alignment: .bottom
        )
    }

    // MARK: - Actions Footer
    private var failureActionsFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Chrome.danger)
                .font(.system(size: 12))

            Text("\(report.failedCount) failing tests need resolution")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Chrome.primaryText)

            Spacer()

            Button {
                askToFixAll()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Ask Agent to Fix All")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Chrome.accent, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: - Raw Log View
    private var rawLogView: some View {
        ScrollView {
            Text(rawOutput)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Chrome.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 260)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Helper Actions
    private func askToFix(suite: TestSuite, testCase: TestCase) {
        var prompt = "Please investigate and fix the failing test in suite `\(suite.name)`:\n\n"
        prompt += "- Test Case: `\(testCase.name)`\n"
        if let msg = testCase.failureMessage, !msg.isEmpty {
            prompt += "- Error:\n```\n\(msg)\n```\n"
        }
        prompt += "\nPlease make the required code adjustments and ensure all tests pass."
        onAskToFix?(prompt)
    }

    private func askToFixAll() {
        var prompt = "Please fix all the failing tests from the test run:\n\n"
        prompt += report.failureSummary
        prompt += "\n\nPlease make the necessary code fixes so that the test suite passes."
        onAskToFix?(prompt)
    }
}
